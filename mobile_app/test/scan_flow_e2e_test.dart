import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/services/leaderboard_service.dart';
import 'package:mobile_app/services/qr_processing_service.dart';
import 'package:mobile_app/utils/image_normalizer.dart';
import 'package:mobile_app/widgets/scan_result_view.dart';

/// Végponttól végpontig (E2E) folyamatteszt: egy QR-kód beolvasásától a
/// pontjóváíráson át az achievement feloldásáig és a beolvasás-eredmény
/// képernyő megjelenítéséig. A teljes kliensoldali (legacy) utat gyakorolja
/// fake Firestore-ral, majd a szolgáltatás eredményét ugyanúgy adja át a
/// [ScanResultView]-nak, mint éles működésben a camera_screen.
///
/// Eszköz nélkül fut a szokásos `flutter test`-ben (nincs kamera/hálózat).
void main() {
  late FakeFirebaseFirestore firestore;
  const uid = 'e2e-user';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    QrProcessingService.firestore = firestore;
    LeaderboardService.firestore = firestore;
    // A kliensoldali (legacy) utat gyakoroljuk – valódi jóváírás + achievement.
    QrProcessingService.serverRedeemEnabled = false;
    QrProcessingService.serverRedeemOverride = null;
  });

  testWidgets(
    'scan → pont → achievement: a teljes folyamat jóváír, felold és megjelenít',
    (tester) async {
      // 1) Adatok: üres haladás, egy állomás és egy "első beolvasás" jutalom.
      await firestore.collection('user_progress').doc(uid).set({
        'name': 'Teszt Elek',
        'totalPoints': 0,
        'completedStations': <String>[],
        'completedEvents': <String>[],
      });
      await firestore.collection('stations').doc('st1').set({
        'name': 'Kinizsi vár',
        'qrCode': 'VAR-001',
        'points': 25,
      });
      await firestore.collection('achievements').doc('first_scan').set({
        'name': 'Első felfedezés',
        'description': 'Beolvastad az első QR-kódot',
        'icon': '🧭',
        'conditionType': 'station_count',
        'conditionValue': 1,
      });

      // 2) A QR-kód feldolgozása (a beolvasás magja).
      final result = await QrProcessingService.processByCode(
        uid: uid,
        code: 'VAR-001',
      );

      // 3) A jóváírás eredménye helyes.
      expect(result.alreadyDone, isFalse);
      expect(result.updatedPoints, 25);
      expect(result.newAchievements, hasLength(1));
      expect(result.newAchievements.first['name'], 'Első felfedezés');

      // 4) Az adatbázisban is megjelent a pont, a teljesítés és a feloldás.
      final progress =
          await firestore.collection('user_progress').doc(uid).get();
      expect((progress.data()!['totalPoints'] as num).toInt(), 25);
      expect(
        List<String>.from(progress.data()!['completedStations']),
        contains('st1'),
      );
      final unlocked = await firestore
          .collection('user_progress')
          .doc(uid)
          .collection('unlocked_achievements')
          .doc('first_scan')
          .get();
      expect(unlocked.exists, isTrue);

      // 5) A beolvasás-eredmény képernyő ugyanabból a map-ből épül, mint élesben.
      final stationForView = <String, dynamic>{
        ...result.target,
        'imageUrl': primaryPhotoFromDoc(result.target),
        'alreadyDone': result.alreadyDone,
        'newAchievements': result.newAchievements,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScanResultView(
              station: stationForView,
              onScanAgain: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 6) A megjelenítés a pontot és a feloldott jutalmat is mutatja.
      expect(find.text('Kinizsi vár'), findsOneWidget);
      expect(find.text('+25 pont'), findsOneWidget);
      expect(find.text('Új jutalom feloldva! 🎉'), findsOneWidget);
      expect(find.text('Első felfedezés'), findsOneWidget);
    },
  );

  testWidgets(
    'ugyanaz a kód másodszorra már nem ír jóvá pontot (idempotens)',
    (tester) async {
      await firestore.collection('user_progress').doc(uid).set({
        'name': 'Teszt Elek',
        'totalPoints': 25,
        'completedStations': <String>['st1'],
        'completedEvents': <String>[],
      });
      await firestore.collection('stations').doc('st1').set({
        'name': 'Kinizsi vár',
        'qrCode': 'VAR-001',
        'points': 25,
      });

      final result = await QrProcessingService.processByCode(
        uid: uid,
        code: 'VAR-001',
      );

      expect(result.alreadyDone, isTrue);
      expect(result.updatedPoints, 25); // nincs újabb jóváírás
      final progress =
          await firestore.collection('user_progress').doc(uid).get();
      expect((progress.data()!['totalPoints'] as num).toInt(), 25);
    },
  );
}
