import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mobile_app/services/hiking_route_service.dart';

/// Google polyline6 KÓDOLÓ a round-trip teszthez (a service csak dekódol).
String encodePolyline6(List<LatLng> points) {
  final factor = math.pow(10, 6).toInt();
  final buffer = StringBuffer();
  int prevLat = 0;
  int prevLng = 0;

  void encodeValue(int value) {
    var v = value < 0 ? ~(value << 1) : (value << 1);
    while (v >= 0x20) {
      buffer.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    buffer.writeCharCode(v + 63);
  }

  for (final p in points) {
    final lat = (p.latitude * factor).round();
    final lng = (p.longitude * factor).round();
    encodeValue(lat - prevLat);
    encodeValue(lng - prevLng);
    prevLat = lat;
    prevLng = lng;
  }
  return buffer.toString();
}

void main() {
  group('decodePolyline6', () {
    test('round-trip: a kódolt pontsor pontosan visszajön', () {
      final original = [
        const LatLng(47.06, 17.715),
        const LatLng(47.061234, 17.716789),
        const LatLng(47.058111, 17.712345),
      ];

      final decoded =
          HikingRouteService.decodePolyline6(encodePolyline6(original));

      expect(decoded, hasLength(3));
      for (var i = 0; i < original.length; i++) {
        expect(decoded[i].latitude, closeTo(original[i].latitude, 1e-6));
        expect(decoded[i].longitude, closeTo(original[i].longitude, 1e-6));
      }
    });

    test('egyetlen pontból álló (érvénytelen) shape üres listát ad', () {
      final encoded = encodePolyline6([const LatLng(47.06, 17.715)]);
      expect(HikingRouteService.decodePolyline6(encoded), isEmpty);
    });
  });

  group('appendRoutePoints', () {
    test('az illesztési pont nem duplázódik', () {
      final target = [const LatLng(1, 1), const LatLng(2, 2)];
      HikingRouteService.appendRoutePoints(target, [
        const LatLng(2.000001, 2.000001), // tolerancián belül az utolsóhoz
        const LatLng(3, 3),
      ]);

      expect(target, hasLength(3));
      expect(target.last, const LatLng(3, 3));
    });

    test('nem érintkező szakasz teljes egészében hozzáfűződik', () {
      final target = [const LatLng(1, 1)];
      HikingRouteService.appendRoutePoints(target, [
        const LatLng(5, 5),
        const LatLng(6, 6),
      ]);
      expect(target, hasLength(3));
    });

    test('üres cél egyszerűen átveszi a szakaszt', () {
      final target = <LatLng>[];
      HikingRouteService.appendRoutePoints(target, [const LatLng(1, 1)]);
      expect(target, hasLength(1));
    });
  });

  group('decodeStoredRoute', () {
    test('koordináta-pár listát dekódol', () {
      final points = HikingRouteService.decodeStoredRoute([
        [47.06, 17.715],
        [47.07, 17.72],
      ]);
      expect(points, hasLength(2));
      expect(points.first.latitude, 47.06);
    });

    test('lat/lng map-eket is dekódol', () {
      final points = HikingRouteService.decodeStoredRoute([
        {'latitude': 47.06, 'longitude': 17.715},
        {'lat': 47.07, 'lng': 17.72},
      ]);
      expect(points, hasLength(2));
      expect(points.last.longitude, 17.72);
    });

    test('két pontnál kevesebbre üres listát ad', () {
      expect(HikingRouteService.decodeStoredRoute([[47.06, 17.715]]), isEmpty);
      expect(HikingRouteService.decodeStoredRoute('nem lista'), isEmpty);
    });
  });

  group('formázók', () {
    test('formatDistance méterből km-t képez', () {
      expect(HikingRouteService.formatDistance(5300), '5.3 km');
      expect(HikingRouteService.formatDistance(0), 'Nincs adat');
    });

    test('formatDuration óra-perc bontást ad', () {
      expect(HikingRouteService.formatDuration(3900), '1 ó 5 p');
      expect(HikingRouteService.formatDuration(600), '10 p');
      expect(HikingRouteService.formatDuration(0), 'Nincs adat');
    });
  });
}
