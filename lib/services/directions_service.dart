import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

/// Egy gyalogos/túra útvonal alternatíva
class RouteChoice {
  final List<gmap.LatLng> points;
  final int walkDistanceMeters;
  final int walkDurationSec;
  final String summary;

  RouteChoice({
    required this.points,
    required this.walkDistanceMeters,
    required this.walkDurationSec,
    required this.summary,
  });
}

/// Autós elérhetőség összefoglalása
class DrivingOverview {
  final bool available;
  final int? distanceMeters;
  final int? durationSec;

  DrivingOverview({
    required this.available,
    this.distanceMeters,
    this.durationSec,
  });
}

/// Útvonaltervező szolgáltatás:
/// - Gyalog/túra: OpenRouteService (foot-hiking)
/// - Autó: Google Directions (driving)
class DirectionsService {
  final String googleApiKey;
  final String orsApiKey;

  DirectionsService({
    required this.googleApiKey,
    required this.orsApiKey,
  });

    // ---------------------------------------------------------------------------
  // 1) TÚRA / GYALOG ÚTVONAL – OpenRouteService, profil: foot-hiking
  // ---------------------------------------------------------------------------
  Future<List<RouteChoice>> getWalkingAlternatives({
    required gmap.LatLng origin,
    required gmap.LatLng destination,
    List<gmap.LatLng> waypoints = const <gmap.LatLng>[],
  }) async {
    // ORS API-ban a koordináta sorrend: [lon, lat]
    final List<List<double>> coordinates = <List<double>>[
      <double>[origin.longitude, origin.latitude],
      ...waypoints.map(
        (p) => <double>[p.longitude, p.latitude],
      ),
      <double>[destination.longitude, destination.latitude],
    ];

    // Kifejezetten geojson végpontot hívunk
    final uri = Uri.parse(
      'https://api.openrouteservice.org/v2/directions/foot-hiking/geojson',
    );

    final response = await http.post(
      uri,
      headers: <String, String>{
        'Authorization': orsApiKey,
        'Content-Type': 'application/json; charset=utf-8',
        'Accept':
            'application/json, application/geo+json, application/gpx+xml, img/png; charset=utf-8',
      },
      body: jsonEncode(<String, dynamic>{
        'coordinates': coordinates,
        'instructions': false,
      }),
    );

    // HTTP hiba – pl. rossz kulcs, quota, stb.
    if (response.statusCode != 200) {
      throw Exception(
          'ORS hiba (${response.statusCode}): ${response.body}');
    }

    final Map<String, dynamic> data =
        jsonDecode(response.body) as Map<String, dynamic>;

    // ORS saját error mezője (itt szokott lenni az igazi üzenet)
    if (data.containsKey('error')) {
      final err = data['error'] as Map<String, dynamic>;
      throw Exception('ORS hiba: ${err['message']}');
    }

    final List features = data['features'] as List? ?? <dynamic>[];
    if (features.isEmpty) {
      // Ez az az eset, amikor tényleg nincs útvonal a megadott pontok közt
      throw Exception(
          'ORS: nincs útvonal a megadott pontok között (foot-hiking).');
    }

    final Map<String, dynamic> feature =
        features.first as Map<String, dynamic>;
    final Map<String, dynamic> properties =
        feature['properties'] as Map<String, dynamic>;
    final Map<String, dynamic> summary =
        properties['summary'] as Map<String, dynamic>;

    final int distance =
        (summary['distance'] as num).round(); // méter
    final int duration =
        (summary['duration'] as num).round(); // másodperc

    final Map<String, dynamic> geometry =
        feature['geometry'] as Map<String, dynamic>;
    final List coordsRaw = geometry['coordinates'] as List;

    final List<gmap.LatLng> points = coordsRaw.map<gmap.LatLng>((dynamic item) {
      final List coord = item as List;
      final double lon = (coord[0] as num).toDouble();
      final double lat = (coord[1] as num).toDouble();
      return gmap.LatLng(lat, lon);
    }).toList();

    return <RouteChoice>[
      RouteChoice(
        points: points,
        walkDistanceMeters: distance,
        walkDurationSec: duration,
        summary: 'Túraútvonal',
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // 2) AUTÓS ÖSSZEFOGLALÓ – Google Directions (driving)
  // ---------------------------------------------------------------------------
  Future<DrivingOverview> getDrivingOverview({
    required gmap.LatLng origin,
    required gmap.LatLng destination,
    List<gmap.LatLng> waypoints = const <gmap.LatLng>[],
  }) async {
    final buffer = StringBuffer();
    buffer.write(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?mode=driving'
        '&origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}');

    if (waypoints.isNotEmpty) {
      buffer.write('&waypoints=');
      buffer.write(
        waypoints
            .map((p) => '${p.latitude},${p.longitude}')
            .join('|'),
      );
    }

    buffer.write('&key=$googleApiKey');

    final uri = Uri.parse(buffer.toString());
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      return DrivingOverview(available: false);
    }

    final Map<String, dynamic> data =
        jsonDecode(response.body) as Map<String, dynamic>;

    if (data['status'] != 'OK' || (data['routes'] as List).isEmpty) {
      return DrivingOverview(available: false);
    }

    final Map<String, dynamic> firstRoute =
        (data['routes'] as List).first as Map<String, dynamic>;
    final Map<String, dynamic> firstLeg =
        (firstRoute['legs'] as List).first as Map<String, dynamic>;

    final int dist = (firstLeg['distance']['value'] as num).round(); // méter
    final int dur = (firstLeg['duration']['value'] as num).round(); // másodperc

    return DrivingOverview(
      available: true,
      distanceMeters: dist,
      durationSec: dur,
    );
  }
}
