import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/location_service.dart';

void main() {
  group('LocationService.distanceMeters (Haversine)', () {
    test('azonos pont távolsága 0', () {
      expect(
        LocationService.distanceMeters(47.06, 17.715, 47.06, 17.715),
        0,
      );
    });

    test('~0.01° hosszúságkülönbség ~47°-on kb. 758 m', () {
      final d = LocationService.distanceMeters(47.06, 17.715, 47.06, 17.725);
      expect(d, greaterThan(700));
      expect(d, lessThan(800));
    });

    test('szimmetrikus (a→b == b→a)', () {
      final ab = LocationService.distanceMeters(47.06, 17.715, 47.08, 17.75);
      final ba = LocationService.distanceMeters(47.08, 17.75, 47.06, 17.715);
      expect((ab - ba).abs(), lessThan(1e-6));
    });

    test('nagyobb távolság nagyobb értéket ad', () {
      final near = LocationService.distanceMeters(47.06, 17.715, 47.061, 17.716);
      final far = LocationService.distanceMeters(47.06, 17.715, 47.2, 17.9);
      expect(far, greaterThan(near));
      // A ~0.14°/0.185° eltérés jóval a városi távolság fölött (>15 km).
      expect(far, greaterThan(15000));
    });
  });
}
