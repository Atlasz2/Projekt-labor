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
    // A legtöbb teszt a legacy (kliensoldali) utat gyakorolja.
    QrProcessingService.serverRedeemEnabled = false;
    QrProcessingService.serverRedeemOverride = null;
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

  group('túra-teljesítés (legacy út)', () {
    test('az utolsó állomás beolvasásával a completedTripIds bővül és a trip_complete jutalom feloldódik',
        () async {
      await firestore.collection('user_progress').doc(uid).set({
        'name': 'Teszt Elek',
        'totalPoints': 10,
        'completedStations': ['st1'],
        'completedEvents': <String>[],
        'completedTripIds': <String>[],
      });
      await firestore.collection('stations').doc('st1').set({
        'name': 'Első',
        'tripId': 'trip1',
        'points': 10,
      });
      await firestore.collection('stations').doc('st2').set({
        'name': 'Második',
        'qrCode': 'ST2',
        'tripId': 'trip1',
        'points': 10,
      });
      await firestore.collection('achievements').doc('local_legend').set({
        'name': 'Helyi legenda',
        'conditionType': 'trip_complete',
        'conditionValue': 1,
      });

      final result = await QrProcessingService.processByCode(
        uid: uid,
        code: 'ST2',
      );

      final progress = await firestore
          .collection('user_progress')
          .doc(uid)
          .get();
      expect(progress.data()!['completedTripIds'], ['trip1']);
      expect(result.newAchievements.single['id'], 'local_legend');
    });

    test('hiányzó túra-állomásnál nem íródik completedTripIds', () async {
      await seedProgress();
      await firestore.collection('stations').doc('st1').set({
        'name': 'Első',
        'qrCode': 'ST1',
        'tripId': 'trip1',
        'points': 10,
      });
      await firestore.collection('stations').doc('st2').set({
        'name': 'Második',
        'tripId': 'trip1',
        'points': 10,
      });

      await QrProcessingService.processByCode(uid: uid, code: 'ST1');

      final progress = await firestore
          .collection('user_progress')
          .doc(uid)
          .get();
      expect(progress.data()!['completedTripIds'] ?? [], isEmpty);
    });
  });

  group('top_n jutalom (legacy út)', () {
    test('a friss pontszámmal top 2-be kerülve feloldódik', () async {
      await seedProgress();
      await firestore.collection('stations').doc('st1').set({
        'name': 'Kinizsi vár',
        'qrCode': 'VAR-001',
        'points': 50,
      });
      await firestore.collection('public_leaderboard').doc('masik-1').set({
        'displayName': 'Éllovas',
        'points': 100,
      });
      await firestore.collection('public_leaderboard').doc('masik-2').set({
        'displayName': 'Második',
        'points': 30,
      });
      await firestore.collection('achievements').doc('podium').set({
        'name': 'Dobogós',
        'conditionType': 'top_n',
        'conditionValue': 2,
      });

      final result = await QrProcessingService.processByCode(
        uid: uid,
        code: 'VAR-001',
      );

      expect(result.newAchievements.single['id'], 'podium');
    });

    test('rangon kívül nem oldódik fel', () async {
      await seedProgress();
      await firestore.collection('stations').doc('st1').set({
        'name': 'Kinizsi vár',
        'qrCode': 'VAR-001',
        'points': 5,
      });
      await firestore.collection('public_leaderboard').doc('masik-1').set({
        'displayName': 'A',
        'points': 100,
      });
      await firestore.collection('public_leaderboard').doc('masik-2').set({
        'displayName': 'B',
        'points': 90,
      });
      await firestore.collection('achievements').doc('podium').set({
        'name': 'Dobogós',
        'conditionType': 'top_n',
        'conditionValue': 2,
      });

      final result = await QrProcessingService.processByCode(
        uid: uid,
        code: 'VAR-001',
      );

      expect(result.newAchievements, isEmpty);
    });
  });

  group('szerveroldali jóváírás (redeemQr)', () {
    test('sikeres szerver-válaszból épül az eredmény, kliens-írás nélkül',
        () async {
      await seedProgress();
      QrProcessingService.serverRedeemEnabled = true;
      String? sentCode;
      QrProcessingService.serverRedeemOverride = (code, location) async {
        sentCode = code;
        return {
          'found': true,
          'kind': 'event',
          'targetId': 'ev1',
          'target': {'name': 'Várjátékok', 'points': 15},
          'alreadyDone': false,
          'newAchievements': [
            {'id': 'event_hunter', 'name': 'Eseményvadász'},
          ],
          'updatedPoints': 20,
          'completedStationsCount': 1,
          'completedEventsCount': 1,
        };
      };

      final result = await QrProcessingService.processByCode(
        uid: uid,
        code: 'EVENT-2026',
      );

      expect(sentCode, 'EVENT-2026');
      expect(result.kind, QrTargetKind.event);
      expect(result.updatedPoints, 20);
      expect(result.target['name'], 'Várjátékok');
      expect(result.newAchievements.single['id'], 'event_hunter');

      // A pontot a szerver írta — a kliens nem nyúlt a Firestore-hoz.
      final progress = await firestore
          .collection('user_progress')
          .doc(uid)
          .get();
      expect(progress.data()!['totalPoints'], 0);
    });

    test('found:false válaszra QrCodeNotFoundException, legacy út nem fut',
        () async {
      await seedProgress();
      await firestore.collection('stations').doc('st1').set({
        'name': 'Kinizsi vár',
        'qrCode': 'VAR-001',
        'points': 25,
      });
      QrProcessingService.serverRedeemEnabled = true;
      QrProcessingService.serverRedeemOverride =
          (_, _) async => {'found': false};

      await expectLater(
        QrProcessingService.processByCode(uid: uid, code: 'VAR-001'),
        throwsA(isA<QrCodeNotFoundException>()),
      );

      // Nem esett vissza a legacy útra: nem íródott pont.
      final progress = await firestore
          .collection('user_progress')
          .doc(uid)
          .get();
      expect(progress.data()!['totalPoints'], 0);
    });

    test('nem deployolt függvénynél legacy fallback fut és memoizálódik',
        () async {
      await seedProgress();
      await firestore.collection('stations').doc('st1').set({
        'name': 'Kinizsi vár',
        'qrCode': 'VAR-001',
        'points': 25,
      });
      QrProcessingService.serverRedeemEnabled = true;
      var calls = 0;
      QrProcessingService.serverRedeemOverride = (_, _) async {
        calls += 1;
        throw const QrServerUnavailableException();
      };

      final result = await QrProcessingService.processByCode(
        uid: uid,
        code: 'VAR-001',
      );

      expect(result.updatedPoints, 25);
      expect(QrProcessingService.serverRedeemEnabled, isFalse);
      expect(calls, 1);
    });

    test('tranziens szerver-hiba továbbdobódik (offline queue újrapróbálja)',
        () async {
      await seedProgress();
      QrProcessingService.serverRedeemEnabled = true;
      QrProcessingService.serverRedeemOverride =
          (_, _) async => throw Exception('network down');

      await expectLater(
        QrProcessingService.processByCode(uid: uid, code: 'VAR-001'),
        throwsA(isA<Exception>()),
      );
      // A szerver-út bekapcsolva marad: tranziens hiba nem memoizálódik.
      expect(QrProcessingService.serverRedeemEnabled, isTrue);
    });

    test('szerver out_of_range válaszra QrOutOfRangeException, nincs jóváírás',
        () async {
      await seedProgress();
      QrProcessingService.serverRedeemEnabled = true;
      ScanLocation? sentLocation;
      QrProcessingService.serverRedeemOverride = (code, location) async {
        sentLocation = location;
        return {
          'found': true,
          'rejected': 'out_of_range',
          'kind': 'station',
          'targetId': 'st1',
          'target': {'name': 'Kinizsi vár'},
          'distance': 4200,
          'threshold': 150,
        };
      };

      await expectLater(
        QrProcessingService.processByCode(
          uid: uid,
          code: 'VAR-001',
          location: (lat: 47.2, lng: 17.9),
        ),
        throwsA(
          isA<QrOutOfRangeException>()
              .having((e) => e.distance, 'distance', 4200)
              .having((e) => e.threshold, 'threshold', 150),
        ),
      );
      // A pozíció eljutott a szerverhez.
      expect(sentLocation?.lat, 47.2);
      final progress = await firestore
          .collection('user_progress')
          .doc(uid)
          .get();
      expect(progress.data()!['totalPoints'], 0);
    });
  });

  group('legacy úti helyszín-ellenőrzés', () {
    setUp(() {
      QrProcessingService.serverRedeemEnabled = false;
    });

    test('távoli pozícióra QrOutOfRangeException, a pont nem íródik', () async {
      await seedProgress();
      await firestore.collection('stations').doc('st1').set({
        'name': 'Kinizsi vár',
        'qrCode': 'VAR-001',
        'points': 25,
        'latitude': 47.06,
        'longitude': 17.715,
      });

      await expectLater(
        QrProcessingService.processByCode(
          uid: uid,
          code: 'VAR-001',
          location: (lat: 47.2, lng: 17.9),
        ),
        throwsA(isA<QrOutOfRangeException>()),
      );

      final progress = await firestore
          .collection('user_progress')
          .doc(uid)
          .get();
      expect(progress.data()!['totalPoints'], 0);
    });

    test('helyszínen lévő pozícióval a jóváírás megtörténik', () async {
      await seedProgress();
      await firestore.collection('stations').doc('st1').set({
        'name': 'Kinizsi vár',
        'qrCode': 'VAR-001',
        'points': 25,
        'latitude': 47.06,
        'longitude': 17.715,
      });

      final result = await QrProcessingService.processByCode(
        uid: uid,
        code: 'VAR-001',
        location: (lat: 47.0601, lng: 17.7151),
      );

      expect(result.updatedPoints, 25);
    });

    test('pozíció nélkül a helyhez kötött állomás is jóváíródik (graceful)',
        () async {
      await seedProgress();
      await firestore.collection('stations').doc('st1').set({
        'name': 'Kinizsi vár',
        'qrCode': 'VAR-001',
        'points': 25,
        'latitude': 47.06,
        'longitude': 17.715,
      });

      final result = await QrProcessingService.processByCode(
        uid: uid,
        code: 'VAR-001',
      );

      expect(result.updatedPoints, 25);
    });

    test('koordináta nélküli állomásnál a pozíció irreleváns', () async {
      await seedProgress();
      await firestore.collection('stations').doc('st1').set({
        'name': 'Koordináta nélküli',
        'qrCode': 'VAR-001',
        'points': 25,
      });

      final result = await QrProcessingService.processByCode(
        uid: uid,
        code: 'VAR-001',
        location: (lat: 47.9, lng: 18.9),
      );

      expect(result.updatedPoints, 25);
    });

    test('az állomás radius mezője kitágítja a megengedett kört', () async {
      await seedProgress();
      await firestore.collection('stations').doc('st1').set({
        'name': 'Nagy hatókörű',
        'qrCode': 'VAR-001',
        'points': 25,
        'latitude': 47.06,
        'longitude': 17.715,
        'radius': 2000,
      });

      // ~758 m — az alap 150 m-en kívül, de a 2000 m-es radiuson belül.
      final result = await QrProcessingService.processByCode(
        uid: uid,
        code: 'VAR-001',
        location: (lat: 47.06, lng: 17.725),
      );

      expect(result.updatedPoints, 25);
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
