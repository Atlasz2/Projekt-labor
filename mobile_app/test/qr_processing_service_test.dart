import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/leaderboard_service.dart';
import 'package:mobile_app/services/qr_processing_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  const uid = 'test-user';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    QrProcessingService.firestore = firestore;
    LeaderboardService.firestore = firestore;
  });

  Future<void> seedProgress({
    int totalPoints = 0,
    List<String> stations = const [],
    List<String> events = const [],
  }) {
    return firestore.collection('user_progress').doc(uid).set({
      'name': 'Teszt Elek',
      'totalPoints': totalPoints,
      'completedStations': stations,
      'completedEvents': events,
    });
  }

  group('állomás QR', () {
    test('qrCode alapján megtalálja az állomást és pontot ír jóvá', () async {
      await seedProgress();
      await firestore.collection('stations').doc('st1').set({
        'name': 'Kinizsi vár',
        'qrCode': 'VAR-001',
        'points': 25,
      });

      final result = await QrProcessingService.processByCode(
        uid: uid,
        code: 'VAR-001',
      );

      expect(result.kind, QrTargetKind.station);
      expect(result.alreadyDone, isFalse);
      expect(result.updatedPoints, 25);
      expect(result.completedStationsCount, 1);

      final progress = await firestore
          .collection('user_progress')
          .doc(uid)
          .get();
      expect(progress.data()!['totalPoints'], 25);
      expect(progress.data()!['completedStations'], ['st1']);

      final lb = await firestore
          .collection('public_leaderboard')
          .doc(uid)
          .get();
      expect(lb.data()!['points'], 25);
    });

    test('doc-id fallback működik, ha nincs qrCode találat', () async {
      await seedProgress();
      await firestore.collection('stations').doc('st-direct').set({
        'name': 'Malom',
        'points': 10,
      });

      final result = await QrProcessingService.processByCode(
        uid: uid,
        code: 'st-direct',
      );

      expect(result.kind, QrTargetKind.station);
      expect(result.updatedPoints, 10);
    });

    test('ismételt beolvasás nem duplázza a pontot', () async {
      await seedProgress(totalPoints: 25, stations: ['st1']);
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
      expect(result.updatedPoints, 25);

      final progress = await firestore
          .collection('user_progress')
          .doc(uid)
          .get();
      expect(progress.data()!['totalPoints'], 25);
    });
  });

  group('esemény QR', () {
    test('qrCode alapján megtalálja az eseményt és pontot ír jóvá', () async {
      await seedProgress(totalPoints: 5, stations: ['st0']);
      await firestore.collection('events').doc('ev1').set({
        'name': 'Várjátékok',
        'qrCode': 'EVENT-2026',
        'points': 15,
      });

      final result = await QrProcessingService.processByCode(
        uid: uid,
        code: 'EVENT-2026',
      );

      expect(result.kind, QrTargetKind.event);
      expect(result.alreadyDone, isFalse);
      expect(result.updatedPoints, 20);
      expect(result.completedEventsCount, 1);
      expect(result.completedStationsCount, 1);

      final progress = await firestore
          .collection('user_progress')
          .doc(uid)
          .get();
      expect(progress.data()!['completedEvents'], ['ev1']);
      expect(progress.data()!['totalPoints'], 20);
      // Az állomás-lista érintetlen marad.
      expect(progress.data()!['completedStations'], ['st0']);
    });

    test('ismételt esemény-beolvasás alreadyDone-t ad', () async {
      await seedProgress(totalPoints: 15, events: ['ev1']);
      await firestore.collection('events').doc('ev1').set({
        'name': 'Várjátékok',
        'qrCode': 'EVENT-2026',
        'points': 15,
      });

      final result = await QrProcessingService.processByCode(
        uid: uid,
        code: 'EVENT-2026',
      );

      expect(result.alreadyDone, isTrue);
      expect(result.updatedPoints, 15);
    });

    test('event_count jutalom feloldódik esemény beolvasásakor', () async {
      await seedProgress();
      await firestore.collection('events').doc('ev1').set({
        'name': 'Várjátékok',
        'qrCode': 'EVENT-2026',
        'points': 15,
      });
      await firestore.collection('achievements').doc('event_hunter').set({
        'name': 'Eseményvadász',
        'conditionType': 'event_count',
        'conditionValue': 1,
      });

      final result = await QrProcessingService.processByCode(
        uid: uid,
        code: 'EVENT-2026',
      );

      expect(result.newAchievements, hasLength(1));
      expect(result.newAchievements.first['id'], 'event_hunter');

      final unlocked = await firestore
          .collection('user_progress')
          .doc(uid)
          .collection('unlocked_achievements')
          .doc('event_hunter')
          .get();
      expect(unlocked.exists, isTrue);
    });
  });

  group('ismeretlen kód', () {
    test('QrCodeNotFoundException-t dob, ha se állomás, se esemény', () async {
      await seedProgress();

      expect(
        () => QrProcessingService.processByCode(uid: uid, code: 'NEMLETEZIK'),
        throwsA(isA<QrCodeNotFoundException>()),
      );
    });

    test("'/'-t tartalmazó kódra sem dob ArgumentError-t", () async {
      await seedProgress();

      expect(
        () => QrProcessingService.processByCode(
          uid: uid,
          code: 'https://example.com/valami',
        ),
        throwsA(isA<QrCodeNotFoundException>()),
      );
    });
  });

  test('hiányzó user_progress doksit nullázva hozza létre, majd jóváír',
      () async {
    await firestore.collection('stations').doc('st1').set({
      'name': 'Kinizsi vár',
      'qrCode': 'VAR-001',
      'points': 25,
    });

    final result = await QrProcessingService.processByCode(
      uid: uid,
      code: 'VAR-001',
    );

    expect(result.updatedPoints, 25);
    final progress = await firestore
        .collection('user_progress')
        .doc(uid)
        .get();
    expect(progress.data()!['totalPoints'], 25);
    expect(progress.data()!['completedEvents'], isEmpty);
  });
}
