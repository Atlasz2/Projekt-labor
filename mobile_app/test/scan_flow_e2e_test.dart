import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/services/qr_processing_service.dart';
import 'package:mobile_app/utils/image_normalizer.dart';
import 'package:mobile_app/widgets/scan_result_view.dart';

/// Folyamatteszt: egy QR-kód beolvasásától a szerver (redeemQr) válaszán át a
/// beolvasás-eredmény képernyő megjelenítéséig. A szerverhívást egy
/// helyettesítő adja, amely a redeemQr valódi válaszformátumát küldi; a
/// képernyő ugyanabból a map-ből épül, mint élesben a camera_screen-ben.
///
/// Eszköz nélkül fut a szokásos `flutter test`-ben (nincs kamera/hálózat).
void main() {
  tearDown(() => QrProcessingService.serverRedeemOverride = null);

  Future<void> pumpResult(WidgetTester tester, QrProcessResult result) async {
    final stationForView = <String, dynamic>{
      ...result.target,
      'imageUrl': primaryPhotoFromDoc(result.target),
      'alreadyDone': result.alreadyDone,
      'newAchievements': result.newAchievements,
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ScanResultView(station: stationForView, onScanAgain: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'scan → pont → jutalom: a szerver-válasz jóváírást és feloldást jelenít meg',
    (tester) async {
      QrProcessingService.serverRedeemOverride = (code, _) async {
        expect(code, 'VAR-001');
        return {
          'found': true,
          'kind': 'station',
          'targetId': 'st1',
          'target': {'name': 'Kinizsi vár', 'points': 25},
          'alreadyDone': false,
          'newAchievements': [
            {
              'id': 'first_scan',
              'name': 'Első felfedezés',
              'description': 'Beolvastad az első QR-kódot',
              'icon': '🧭',
            },
          ],
          'updatedPoints': 25,
          'completedStationsCount': 1,
          'completedEventsCount': 0,
        };
      };

      final result = await QrProcessingService.processByCode(code: 'VAR-001');
      await pumpResult(tester, result);

      expect(find.text('Kinizsi vár'), findsOneWidget);
      expect(find.text('+25 pont'), findsOneWidget);
      expect(find.text('Új jutalom feloldva! 🎉'), findsOneWidget);
      expect(find.text('Első felfedezés'), findsOneWidget);
    },
  );

  testWidgets(
    'ugyanaz a kód másodszorra már nem ér pontot (idempotens válasz)',
    (tester) async {
      QrProcessingService.serverRedeemOverride = (_, _) async => {
        'found': true,
        'kind': 'station',
        'target': {'name': 'Kinizsi vár', 'points': 25},
        'alreadyDone': true,
        'newAchievements': <Object>[],
        'updatedPoints': 25,
        'completedStationsCount': 1,
        'completedEventsCount': 0,
      };

      final result = await QrProcessingService.processByCode(code: 'VAR-001');
      await pumpResult(tester, result);

      expect(result.alreadyDone, isTrue);
      expect(find.text('Már feloldott (+0 pt)'), findsOneWidget);
      expect(find.text('Új jutalom feloldva! 🎉'), findsNothing);
    },
  );
}
