import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mobile_app/services/hiking_route_service.dart';
import 'package:mobile_app/services/local_cache.dart';
import 'package:mobile_app/services/trip_route_service.dart';

void main() {
  late Directory dir;
  var fetchCalls = 0;

  const stations = [LatLng(47.05, 17.71), LatLng(47.06, 17.72)];
  const realRoute = [
    LatLng(47.05, 17.71),
    LatLng(47.055, 17.705),
    LatLng(47.06, 17.72),
  ];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('trip_route_test');
    Hive.init(dir.path);
    await LocalCache.init();
    fetchCalls = 0;
  });

  tearDown(() async {
    TripRouteService.fetcher = HikingRouteService.fetchRoute;
    await Hive.close();
    await dir.delete(recursive: true);
  });

  void fetchReturns(Map<String, dynamic> data) {
    TripRouteService.fetcher = (_) async {
      fetchCalls++;
      return data;
    };
  }

  test('a túrában tárolt útvonalat használja, hálózati hívás nélkül', () async {
    fetchReturns({'points': realRoute});
    final route = await TripRouteService.resolve(
      tripId: 't1',
      trip: {
        'routeCoordinates': [
          {'lat': 47.05, 'lng': 17.71},
          {'lat': 47.058, 'lng': 17.70},
          {'lat': 47.06, 'lng': 17.72},
        ],
        'distance': 2.4,
      },
      stationPoints: stations,
    );
    expect(route.points, hasLength(3));
    expect(route.isReal, isTrue);
    expect(route.distance, '2.4 km');
    expect(fetchCalls, 0);
  });

  test(
    'a hálózatról kapott valódi útvonal elmentődik, és offline is megvan',
    () async {
      fetchReturns({
        'points': realRoute,
        'osrm': true,
        'distanceLabel': '1.6 km',
      });
      final online = await TripRouteService.resolve(
        tripId: 't2',
        trip: const {},
        stationPoints: stations,
      );
      expect(online.points, realRoute);
      expect(online.status, 'Gyalogos útvonal');

      // Offline: ugyanaz az útvonal, nem légvonal.
      final offline = await TripRouteService.resolve(
        tripId: 't2',
        trip: const {},
        stationPoints: stations,
        allowNetwork: false,
      );
      expect(offline.points, realRoute);
      expect(offline.isReal, isTrue);
      expect(fetchCalls, 1);
    },
  );

  test(
    'a légvonalas közelítés nem mentődik el (online újra próbálkozik)',
    () async {
      fetchReturns({'points': stations, 'fallback': true});
      final first = await TripRouteService.resolve(
        tripId: 't3',
        trip: const {},
        stationPoints: stations,
      );
      expect(first.isReal, isFalse);
      expect(first.status, TripRouteService.fallbackStatus);
      expect(TripRouteService.available('t3', const {}), isNull);
    },
  );

  test(
    'hálózat nélkül és mentett útvonal nélkül légvonalat ad, hívás nélkül',
    () async {
      fetchReturns({'points': realRoute});
      final route = await TripRouteService.resolve(
        tripId: 't4',
        trip: const {},
        stationPoints: stations,
        allowNetwork: false,
      );
      expect(route.isReal, isFalse);
      expect(route.points, stations);
      expect(fetchCalls, 0);
    },
  );
}
