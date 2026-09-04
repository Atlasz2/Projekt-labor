import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/utils/station_trips.dart';

void main() {
  group('stationTripIds', () {
    test('az új tripIds listát adja vissza, ha van', () {
      expect(stationTripIds({'tripIds': ['t1', 't2']}), ['t1', 't2']);
    });

    test('kiszűri a duplikátumokat', () {
      expect(stationTripIds({'tripIds': ['t1', 't1', 't2']}), ['t1', 't2']);
    });

    test('visszamenőleg a régi tripId mezőt egyelemű listaként adja', () {
      expect(stationTripIds({'tripId': 't1'}), ['t1']);
    });

    test('se tripIds, se tripId -> üres lista', () {
      expect(stationTripIds({}), <String>[]);
      expect(stationTripIds({'tripIds': <String>[]}), <String>[]);
    });
  });

  group('stationBelongsToTrip', () {
    test('egy állomás több túrának is megállója lehet', () {
      final station = {'tripIds': ['t1', 't2']};
      expect(stationBelongsToTrip(station, 't1'), true);
      expect(stationBelongsToTrip(station, 't2'), true);
      expect(stationBelongsToTrip(station, 't3'), false);
    });
  });

  group('stationOrderIndexForTrip', () {
    test('a tripOrder map-ből olvas túránként külön sorrendet', () {
      final station = {
        'tripIds': ['t1', 't2'],
        'tripOrder': {'t1': 0, 't2': 3},
      };
      expect(stationOrderIndexForTrip(station, 't1'), 0);
      expect(stationOrderIndexForTrip(station, 't2'), 3);
    });

    test('régi egyetlen orderIndex mezőre visszamenőleg kompatibilis', () {
      final station = {'tripId': 't1', 'orderIndex': 2};
      expect(stationOrderIndexForTrip(station, 't1'), 2);
    });

    test('ismeretlen túrára 0', () {
      final station = {
        'tripIds': ['t1'],
        'tripOrder': {'t1': 5},
      };
      expect(stationOrderIndexForTrip(station, 't2'), 0);
    });
  });

  group('stationsForTrip', () {
    test('egy állomás két túra listájában is szerepelhet, egymástól független sorrenddel', () {
      final shared = {
        'id': 'shared',
        'tripIds': ['a', 'b'],
        'tripOrder': {'a': 0, 'b': 2},
      };
      final stations = [
        shared,
        {'id': 'a2', 'tripIds': ['a'], 'tripOrder': {'a': 1}},
        {'id': 'b1', 'tripIds': ['b'], 'tripOrder': {'b': 0}},
        {'id': 'b2', 'tripIds': ['b'], 'tripOrder': {'b': 1}},
      ];

      expect(
        stationsForTrip(stations, 'a').map((s) => s['id']).toList(),
        ['shared', 'a2'],
      );
      expect(
        stationsForTrip(stations, 'b').map((s) => s['id']).toList(),
        ['b1', 'b2', 'shared'],
      );
    });
  });
}
