import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/utils/profile_stats.dart';

void main() {
  group('safeCount', () {
    test('lista hosszát adja', () => expect(safeCount([1, 2, 3]), 3));
    test('számot egészre vág', () => expect(safeCount(4.7), 4));
    test('egyébre 0', () => expect(safeCount('x'), 0));
    test('null-ra 0', () => expect(safeCount(null), 0));
  });

  group('safeInt', () {
    test('int marad', () => expect(safeInt(5), 5));
    test('num egészre', () => expect(safeInt(5.9), 5));
    test('számként parse-olható string', () => expect(safeInt('42'), 42));
    test('nem-szám stringre 0', () => expect(safeInt('abc'), 0));
  });

  group('rankMedal', () {
    test('dobogó emojik', () {
      expect(rankMedal(1), '🥇');
      expect(rankMedal(2), '🥈');
      expect(rankMedal(3), '🥉');
    });
    test('dobogón kívül #N', () => expect(rankMedal(7), '#7'));
  });

  group('conditionText', () {
    test('minden ismert típus', () {
      expect(conditionText('station_count', 3), '3 állomás');
      expect(conditionText('event_count', 2), '2 esemény');
      expect(conditionText('qr_count', 5), '5 QR-kód');
      expect(conditionText('points_threshold', 140), '140 pont');
      expect(conditionText('trip_complete', 1), '1 teljesített túra');
      expect(conditionText('top_n', 3), 'Top 3 helyezés');
      expect(conditionText('manual', 0), 'Manuális');
    });
    test('ismeretlen típusra üres', () => expect(conditionText('xyz', 1), ''));
  });

  group('nextPointTarget', () {
    final defs = [
      {'conditionType': 'points_threshold', 'conditionValue': 50},
      {'conditionType': 'points_threshold', 'conditionValue': 140},
      {'conditionType': 'station_count', 'conditionValue': 3}, // nem küszöb
    ];

    test('a legközelebbi, még el nem ért küszöböt adja', () {
      expect(nextPointTarget(30, defs), 50);
      expect(nextPointTarget(70, defs), 140);
    });
    test('minden küszöb fölött a legmagasabbat', () {
      expect(nextPointTarget(200, defs), 140);
    });
    test('küszöb nélkül alapértéket (140)', () {
      expect(nextPointTarget(10, const []), 140);
    });
  });
}
