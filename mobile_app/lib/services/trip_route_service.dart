import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'hiking_route_service.dart';
import 'local_cache.dart';

/// Egy túra kirajzolható útvonala és a hozzá tartozó címkék.
@immutable
class TripRoute {
  const TripRoute({
    required this.points,
    required this.status,
    this.distance = 'Nincs adat',
    this.duration = 'Nincs adat',
    this.isReal = true,
  });

  final List<LatLng> points;
  final String status;
  final String distance;
  final String duration;

  /// Valódi (úthálózatot követő) útvonal-e; a légvonalas közelítés nem az.
  final bool isReal;

  Map<String, String> get metrics => {
    'status': status,
    'distance': distance,
    'duration': duration,
  };
}

typedef RouteFetcher = Future<Map<String, dynamic>> Function(List<LatLng>);

/// A túraútvonal feloldása – a térkép, a navigáció és az offline előtöltés
/// ugyanezt a sorrendet használja, így a két nézet sosem rajzol eltérően:
///
/// 1. a túra dokumentumában tárolt útvonal (az admin menti; a túrák offline
///    gyorsítótárában is benne van),
/// 2. az eszközön korábban elmentett útvonal,
/// 3. hálózati számítás (Valhalla/BRouter, tartalékként OSRM) – a valódi
///    eredmény elmentődik offline használatra,
/// 4. végső esetben légvonal az állomások között (ezt nem mentjük el, hogy
///    hálózat mellett a következő alkalommal újra próbálkozzon).
class TripRouteService {
  const TripRouteService._();

  static const fallbackStatus = 'Közelítő összekötés állomások között';

  /// Tesztekben lecserélhető hálózati útvonaltervező.
  @visibleForTesting
  static RouteFetcher fetcher = HikingRouteService.fetchRoute;

  /// A túra dokumentumában tárolt útvonal, ha van.
  static TripRoute? storedOnTrip(Map<String, dynamic> trip) {
    final points = HikingRouteService.decodeStoredRoute(
      trip['routeCoordinates'],
    );
    if (points.length < 2) return null;
    final distance = trip['distance'];
    final duration = trip['duration'];
    return TripRoute(
      points: points,
      status: 'Turistaútvonal',
      distance: distance is num
          ? '${distance.toStringAsFixed(1)} km'
          : (distance?.toString().trim().isNotEmpty ?? false)
          ? '$distance km'
          : 'Nincs adat',
      duration: (duration?.toString().trim().isNotEmpty ?? false)
          ? duration.toString()
          : 'Nincs adat',
    );
  }

  /// Az eszközön korábban elmentett útvonal, ha van.
  static TripRoute? persisted(String tripId) {
    final raw = LocalCache.getRoute(tripId);
    if (raw == null) return null;
    final points = HikingRouteService.decodeStoredRoute(raw['points']);
    if (points.length < 2) return null;
    final metrics = raw['metrics'];
    String metric(String key, String fallback) =>
        metrics is Map && metrics[key] != null
        ? metrics[key].toString()
        : fallback;
    return TripRoute(
      points: points,
      status: metric('status', 'Mentett útvonal'),
      distance: metric('distance', 'Nincs adat'),
      duration: metric('duration', 'Nincs adat'),
    );
  }

  /// Offline is elérhető útvonal (hálózati hívás nélkül), ha van.
  static TripRoute? available(String tripId, Map<String, dynamic> trip) =>
      storedOnTrip(trip) ?? persisted(tripId);

  /// A teljes feloldás; `allowNetwork: false` mellett nem hív hálózatot.
  static Future<TripRoute> resolve({
    required String tripId,
    required Map<String, dynamic> trip,
    required List<LatLng> stationPoints,
    bool allowNetwork = true,
  }) async {
    final offline = available(tripId, trip);
    if (offline != null) return offline;

    if (allowNetwork && stationPoints.length >= 2) {
      try {
        final data = await fetcher(stationPoints);
        final points = (data['points'] as List? ?? const [])
            .whereType<LatLng>()
            .toList();
        if (points.length >= 2 && data['fallback'] != true) {
          final route = TripRoute(
            points: points,
            status: data['osrm'] == true
                ? 'Gyalogos útvonal'
                : 'Turistaútvonal',
            distance: data['distanceLabel']?.toString() ?? 'Nincs adat',
            duration: data['durationLabel']?.toString() ?? 'Nincs adat',
          );
          await LocalCache.saveRoute(
            tripId,
            points
                .map((p) => ll.LatLng(p.latitude, p.longitude))
                .toList(growable: false),
            route.metrics,
          );
          return route;
        }
      } catch (e) {
        debugPrint('Útvonal-számítás sikertelen ($tripId): $e');
      }
    }

    return TripRoute(
      points: stationPoints,
      status: stationPoints.length >= 2
          ? fallbackStatus
          : 'Nincs elég állomás útvonalhoz',
      isReal: false,
    );
  }
}
