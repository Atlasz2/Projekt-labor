import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/data_export_pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  pw.Font font(String name) => pw.Font.ttf(
    File('assets/fonts/$name').readAsBytesSync().buffer.asByteData(),
  );

  group('DataExportPdf', () {
    test('a callable időbélyeg-formátumait is érti', () {
      final fromMap = DataExportPdf.parseDate({'_seconds': 1760000000});
      expect(fromMap, DateTime.fromMillisecondsSinceEpoch(1760000000000));
      expect(
        DataExportPdf.parseDate(1760000000000),
        DateTime.fromMillisecondsSinceEpoch(1760000000000),
      );
      expect(DataExportPdf.parseDate('2026-10-09T15:40:00'), isNotNull);
      expect(DataExportPdf.parseDate(null), isNull);
      expect(DataExportPdf.parseDate({'mas': 1}), isNull);
    });

    test('magyar dátumformátum', () {
      expect(
        DataExportPdf.formatDate(DateTime(2026, 10, 9, 15, 4)),
        '2026. 10. 09. 15:04',
      );
    });

    test('teljes exportból érvényes PDF készül (ékezetes szöveggel)', () async {
      final bytes = await DataExportPdf.build(
        {
          'uid': 'titkos-uid-123',
          'profile': {
            'displayName': 'Kőműves Ödön',
            'email': 'odon@example.com',
            'createdAt': {'_seconds': 1760000000},
          },
          'progress': {
            'totalPoints': 35,
            'completedStations': ['st1', 'torolt'],
            'completedEvents': ['ev1'],
            'completedTripIds': [],
            'completedStationsAt': {
              'st1': {'_seconds': 1760000500},
            },
          },
          'progressDetails': {
            'completed_stations': [],
            'completed_events': [],
            'unlocked_achievements': [
              {
                'id': 'a1',
                'unlockedAt': {'_seconds': 1760000600},
              },
            ],
          },
          'leaderboardEntry': {'displayName': 'Kőműves Ödön', 'points': 35},
          'bugReports': [
            {
              'description': 'Nem tölt a térkép',
              'created_at_ms': 1760000700000,
            },
          ],
        },
        regular: font('Roboto-Regular.ttf'),
        bold: font('Roboto-Bold.ttf'),
        stationNames: {'st1': 'Kinizsi-vár'},
        eventNames: {'ev1': 'Várjátékok'},
        achievementNames: {'a1': 'Első lépések'},
        now: DateTime(2026, 10, 9),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    });

    test('üres (frissen regisztrált) fiókra sem hibázik', () async {
      final bytes = await DataExportPdf.build(
        const {},
        regular: font('Roboto-Regular.ttf'),
        bold: font('Roboto-Bold.ttf'),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });
}
