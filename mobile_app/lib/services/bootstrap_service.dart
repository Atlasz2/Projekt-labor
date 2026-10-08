import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'local_cache.dart';
import 'offline_sync_service.dart';
import 'trip_route_service.dart';
import '../utils/project_filter.dart';
import '../utils/station_trips.dart';

/// Első induláskor, 12 óránként, illetve a gyorsítótár-formátum változásakor
/// letölti az offline működéshez szükséges adatokat:
///
/// - a túrákat, állomásokat és jutalmakat a saját (Hive) gyorsítótárba;
/// - a rendezvényeket, szállás- és vendéglátóhelyeket, elérhetőségeket és a
///   település történetét – ezek a Firestore offline gyorsítótárába kerülnek,
///   így a képernyőik hálózat nélkül is betöltődnek;
/// - minden túra útvonalát (ha még nincs meg), hogy offline se légvonal
///   jelenjen meg.
///
/// Hálózati hiba esetén csendben visszalép – a felület sosem blokkolódik.
class BootstrapService {
  static bool _running = false;

  /// A tartalmi kollekciók, amelyeket a képernyők közvetlenül a Firestore-ból
  /// olvasnak; az előtöltés ezeket a Firestore gyorsítótárába tölti.
  @visibleForTesting
  static const contentCollections = [
    'events',
    'accommodations',
    'restaurants',
    'contact',
    'about',
  ];

  static VoidCallback? _onlineListener;

  /// Előtöltés most, és minden alkalommal, amikor az eszköz (igazoltan)
  /// visszakapja a hálózatot – így az offline indulás után is pótlódik.
  static Future<void> start() async {
    final sync = OfflineSyncService();
    await sync.init();
    if (_onlineListener == null) {
      void onlineChanged() {
        if (sync.onlineNotifier.value) unawaited(run());
      }

      _onlineListener = onlineChanged;
      sync.onlineNotifier.addListener(onlineChanged);
    }
    await run();
  }

  static void stop() {
    final listener = _onlineListener;
    if (listener != null) {
      OfflineSyncService().onlineNotifier.removeListener(listener);
      _onlineListener = null;
    }
  }

  static Future<void> run({bool force = false}) async {
    if (_running) return;
    if (!force &&
        LocalCache.hasData &&
        !LocalCache.isCacheStale &&
        !LocalCache.bootstrapOutdated) {
      return;
    }
    _running = true;
    try {
      final db = FirebaseFirestore.instance;
      final results = await Future.wait([
        db.collection('trips').get(),
        db.collection('stations').get(),
        db.collection('achievements').get(),
        for (final name in contentCollections) db.collection(name).get(),
      ]).timeout(const Duration(seconds: 25));

      // Az offline gyorsítótárba csak ennek a településnek a tartalma kerül.
      final trips = results[0].docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .where(inActiveProject)
          .toList();
      final stations = results[1].docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .where(inActiveProject)
          .toList();
      final achievements = results[2].docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .toList();

      await Future.wait([
        LocalCache.saveTrips(trips),
        LocalCache.saveStations(stations),
        LocalCache.saveAchievements(achievements),
      ]);
      await LocalCache.markBootstrapped();

      // Az útvonalak számítása lassabb (külső szolgáltatások), ezért a
      // fenti adatok mentése után, a háttérben fut.
      await prefetchRoutes(trips, stations);
    } catch (e) {
      // Nincs hálózat vagy Firestore-hiba – a gyorsítótárazott adat továbbra
      // is használható.
      debugPrint('Offline előtöltés sikertelen: $e');
    } finally {
      _running = false;
    }
  }

  /// Minden aktív túra útvonalának előzetes kiszámítása és mentése, ha még
  /// nincs offline elérhető útvonala. Sorban, egyenként fut, hogy a külső
  /// útvonaltervezőket ne terhelje.
  @visibleForTesting
  static Future<void> prefetchRoutes(
    List<Map<String, dynamic>> trips,
    List<Map<String, dynamic>> stations,
  ) async {
    for (final trip in trips) {
      if (trip['isActive'] == false) continue;
      final tripId = trip['id']?.toString();
      if (tripId == null || TripRouteService.available(tripId, trip) != null) {
        continue;
      }
      final points = stationsForTrip(
        stations,
        tripId,
      ).map(_stationPoint).whereType<LatLng>().toList();
      if (points.length < 2) continue;
      await TripRouteService.resolve(
        tripId: tripId,
        trip: trip,
        stationPoints: points,
      );
    }
  }

  static LatLng? _stationPoint(Map<String, dynamic> station) {
    num? asNum(dynamic v) => v is num ? v : null;
    final loc = station['location'];
    final lat =
        asNum(station['latitude']) ??
        (loc is Map ? asNum(loc['latitude']) : null);
    final lng =
        asNum(station['longitude']) ??
        (loc is Map ? asNum(loc['longitude']) : null);
    if (lat == null || lng == null || (lat == 0 && lng == 0)) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }
}
