import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Túraútvonal-tervezés két szolgáltatóval:
/// 1. Valhalla (OSM-alapú erdei/túraösvények, gyalogos profillal),
/// 2. tartalékként OSRM foot (túrázási sebességre korrigálva).
/// Ha egyik sem elérhető, a nyers töréspontokat adja vissza légvonalban.
///
/// A visszatérési map kulcsai: `points` (List&lt;LatLng&gt;), `distanceLabel`,
/// `durationLabel`, továbbá `osrm: true` az OSRM-, `fallback: true` a
/// légvonal-eredménynél — a hívó ebből tudja, milyen minőségű az útvonal.
class HikingRouteService {
  const HikingRouteService._();

  static Future<Map<String, dynamic>> fetchRoute(List<LatLng> waypoints) async {
    if (waypoints.length < 2) {
      return {
        'points': <LatLng>[],
        'distanceLabel': 'Nincs adat',
        'durationLabel': 'Nincs adat',
      };
    }

    final locations = waypoints
        .map(
          (p) =>
              '{"lon": ${p.longitude}, "lat": ${p.latitude}, "type": "break"}',
        )
        .join(',');
    final body =
        '{"locations": [$locations], "costing": "pedestrian", "costing_options": {"pedestrian": {"use_tracks": 1.0, "use_hills": 0.6, "walking_speed": 3.5, "transit_start_end_max_distance": 0}}, "directions_type": "none"}';

    // 1. Valhalla: OSM-alapu erdei/turaoszvenyek
    try {
      final valhallaClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 14);
      try {
        final request = await valhallaClient.postUrl(
          Uri.parse('https://valhalla1.openstreetmap.de/route'),
        );
        request.headers.contentType = ContentType('application', 'json');
        request.write(body);
        final response = await request.close().timeout(
          const Duration(seconds: 12),
        );
        if (response.statusCode == 200) {
          final responseBody = await response
              .transform(utf8.decoder)
              .join()
              .timeout(const Duration(seconds: 10));
          final data = jsonDecode(responseBody);
          if (data is Map && data['trip'] is Map) {
            final trip = data['trip'] as Map;
            final legs = trip['legs'];
            if (legs is List && legs.isNotEmpty) {
              final points = <LatLng>[];
              for (final item in legs) {
                if (item is! Map) continue;
                final shape = item['shape'] as String?;
                if (shape == null || shape.isEmpty) continue;
                appendRoutePoints(points, decodePolyline6(shape));
              }
              final summary = trip['summary'] as Map?;
              if (points.length >= 2) {
                final lengthKm = (summary?['length'] as num? ?? 0).toDouble();
                final timeSec = (summary?['time'] as num? ?? 0).toDouble();
                return {
                  'points': points,
                  'distanceLabel': formatDistance(lengthKm * 1000),
                  'durationLabel': formatDuration(timeSec),
                };
              }
            }
          }
        }
      } finally {
        valhallaClient.close(force: true);
      }
    } catch (e) {
      // Az elsődleges (Valhalla) útvonaltervező elérhetetlen — jön az OSRM.
      debugPrint('Valhalla útvonaltervezés sikertelen: $e');
    }

    // 2. Tartalek: OSRM foot (turazasi sebesseggel korrigalva)
    final coords = waypoints
        .map((pt) => '${pt.longitude},${pt.latitude}')
        .join(';');
    final osrmUri = Uri.parse(
      'https://router.project-osrm.org/route/v1/foot/$coords?overview=full&geometries=geojson&steps=false&continue_straight=false',
    );
    final osrmClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await osrmClient.getUrl(osrmUri);
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode == 200) {
        final responseBody = await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 8));
        final data = jsonDecode(responseBody);
        if (data is Map &&
            data['code'] == 'Ok' &&
            data['routes'] is List &&
            (data['routes'] as List).isNotEmpty) {
          final route = (data['routes'] as List).first as Map;
          final geometry = route['geometry'];
          final coordsRaw = geometry is Map ? geometry['coordinates'] : null;
          if (coordsRaw is List && coordsRaw.isNotEmpty) {
            final points = <LatLng>[];
            for (final item in coordsRaw) {
              if (item is List && item.length >= 2) {
                final lng = item[0];
                final lat = item[1];
                if (lat is num && lng is num) {
                  points.add(LatLng(lat.toDouble(), lng.toDouble()));
                }
              }
            }
            if (points.length >= 2) {
              final dist = ((route['distance'] as num?) ?? 0).toDouble();
              // OSRM foot ~5 km/h, turazas ~3.5 km/h -> 1.43x
              final duration =
                  ((route['duration'] as num?) ?? 0).toDouble() * 1.43;
              return {
                'points': points,
                'distanceLabel': formatDistance(dist),
                'durationLabel': formatDuration(duration),
                'osrm': true,
              };
            }
          }
        }
      }
    } catch (e) {
      // Az OSRM tartalék is elhalt — légvonalban kötjük össze a pontokat.
      debugPrint('OSRM útvonaltervezés sikertelen: $e');
    } finally {
      osrmClient.close(force: true);
    }

    return {
      'points': waypoints,
      'distanceLabel': 'Nincs adat',
      'durationLabel': 'Nincs adat',
      'fallback': true,
    };
  }

  /// Firestore-ban tárolt útvonal (koordináta-párok vagy lat/lng map-ek
  /// listája) dekódolása. Két pontnál rövidebb eredményre üres listát ad.
  static List<LatLng> decodeStoredRoute(dynamic value) {
    if (value is! List) return const [];
    final points = <LatLng>[];

    for (final item in value) {
      if (item is List && item.length >= 2) {
        final lat = item[0];
        final lng = item[1];
        if (lat is num && lng is num) {
          points.add(LatLng(lat.toDouble(), lng.toDouble()));
        }
        continue;
      }

      if (item is Map) {
        final lat = item['latitude'] ?? item['lat'];
        final lng = item['longitude'] ?? item['lng'] ?? item['lon'];
        if (lat is num && lng is num) {
          points.add(LatLng(lat.toDouble(), lng.toDouble()));
        }
      }
    }

    return points.length >= 2 ? points : const [];
  }

  /// Google polyline6 formátum dekódolása (a Valhalla shape mezője).
  static List<LatLng> decodePolyline6(String encoded) {
    const precision = 6;
    final factor = math.pow(10, precision).toInt();
    final list = <LatLng>[];
    int index = 0;
    final len = encoded.length;
    int lat = 0;
    int lng = 0;
    while (index < len) {
      int result = 0;
      int shift = 0;
      int b = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      result = 0;
      shift = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      list.add(LatLng(lat / factor, lng / factor));
    }
    return list.length >= 2 ? list : const <LatLng>[];
  }

  /// Szakasz hozzáfűzése úgy, hogy az illesztési pont ne duplázódjon.
  static void appendRoutePoints(List<LatLng> target, List<LatLng> segment) {
    if (segment.isEmpty) return;
    if (target.isEmpty) {
      target.addAll(segment);
      return;
    }

    final first = segment.first;
    final last = target.last;
    if (pointsClose(last, first)) {
      target.addAll(segment.skip(1));
      return;
    }

    target.addAll(segment);
  }

  static bool pointsClose(LatLng a, LatLng b, [double tolerance = 0.00002]) {
    return (a.latitude - b.latitude).abs() <= tolerance &&
        (a.longitude - b.longitude).abs() <= tolerance;
  }

  static String formatDistance(double meters) {
    if (meters <= 0) return 'Nincs adat';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  static String formatDuration(double seconds) {
    if (seconds <= 0) return 'Nincs adat';
    final totalMinutes = (seconds / 60).round().clamp(1, 1 << 20);
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0) {
      return '$hours ó $minutes p';
    }
    return '$totalMinutes p';
  }
}
