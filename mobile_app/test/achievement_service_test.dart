import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/achievement_service.dart';

void main() {
  group('isConditionMet', () {
    test('station_count / event_count / qr_count', () {
      bool met(String type, int target, {int s = 0, int e = 0}) =>
          AchievementService.isConditionMet(
            type: type,
            target: target,
            stations: s,
            events: e,
            points: 0,
            trips: 0,
            rank: 0,
          );
      expect(met('station_count', 3, s: 3), isTrue);
      expect(met('station_count', 3, s: 2), isFalse);
      expect(met('event_count', 2, e: 2), isTrue);
      expect(met('qr_count', 4, s: 2, e: 2), isTrue);
      expect(met('qr_count', 5, s: 2, e: 2), isFalse);
    });

    test('points_threshold és trip_complete', () {
      expect(
        AchievementService.isConditionMet(
          type: 'points_threshold',
          target: 140,
          stations: 0,
          events: 0,
          points: 140,
          trips: 0,
          rank: 0,
        ),
        isTrue,
      );
      expect(
        AchievementService.isConditionMet(
          type: 'trip_complete',
          target: 1,
          stations: 0,
          events: 0,
          points: 0,
          trips: 1,
          rank: 0,
        ),
        isTrue,
      );
    });

    test('top_n: rangon belül teljesül, rang nélkül (0) nem', () {
      int rankMet(int target, int rank) => AchievementService.isConditionMet(
            type: 'top_n',
            target: target,
            stations: 0,
            events: 0,
            points: 0,
            trips: 0,
            rank: rank,
          )
          ? 1
          : 0;
      expect(rankMet(3, 2), 1);
      expect(rankMet(3, 3), 1);
      expect(rankMet(3, 4), 0);
      expect(rankMet(3, 0), 0); // ismeretlen rang
    });

    test('manual és ismeretlen típus nem oldódik fel automatikusan', () {
      expect(
        AchievementService.isConditionMet(
          type: 'manual',
          target: 1,
          stations: 99,
          events: 99,
          points: 99,
          trips: 99,
          rank: 1,
        ),
        isFalse,
      );
    });
  });

  group('reconcileFromStats', () {
    late FakeFirebaseFirestore firestore;
    const uid = 'u1';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      AchievementService.firestore = firestore;
    });

    test('feloldja a teljesített, de fel nem oldott jutalmat + bannert állít',
        () async {
      final newly = await AchievementService.reconcileFromStats(
        uid: uid,
        achievements: [
          {
            'id': 'explorer',
            'name': 'Felfedező',
            'description': '3 állomás',
            'conditionType': 'station_count',
            'conditionValue': 3,
          },
        ],
        alreadyUnlocked: <String>{},
        stations: 3,
        events: 0,
        points: 0,
        trips: 0,
        rank: 0,
      );

      expect(newly.single['id'], 'explorer');
      final doc = await firestore
          .collection('user_progress')
          .doc(uid)
          .collection('unlocked_achievements')
          .doc('explorer')
          .get();
      expect(doc.exists, isTrue);

      final banner = (await firestore.collection('user_progress').doc(uid).get())
          .data()!['pendingAchievementBanner'];
      expect(banner['title'], 'Felfedező');
    });

    test('a már feloldottat nem oldja fel újra', () async {
      final newly = await AchievementService.reconcileFromStats(
        uid: uid,
        achievements: [
          {'id': 'explorer', 'conditionType': 'station_count', 'conditionValue': 3},
        ],
        alreadyUnlocked: {'explorer'},
        stations: 5,
        events: 0,
        points: 0,
        trips: 0,
        rank: 0,
      );
      expect(newly, isEmpty);
    });

    test('a nem teljesítettet nem oldja fel', () async {
      final newly = await AchievementService.reconcileFromStats(
        uid: uid,
        achievements: [
          {'id': 'explorer', 'conditionType': 'station_count', 'conditionValue': 3},
        ],
        alreadyUnlocked: <String>{},
        stations: 2,
        events: 0,
        points: 0,
        trips: 0,
        rank: 0,
      );
      expect(newly, isEmpty);
      final doc = await firestore
          .collection('user_progress')
          .doc(uid)
          .collection('unlocked_achievements')
          .doc('explorer')
          .get();
      expect(doc.exists, isFalse);
    });

    test('több feloldásnál a banner az összesített üzenetet mutatja', () async {
      final newly = await AchievementService.reconcileFromStats(
        uid: uid,
        achievements: [
          {'id': 'a', 'name': 'A', 'conditionType': 'station_count', 'conditionValue': 1},
          {'id': 'b', 'name': 'B', 'conditionType': 'points_threshold', 'conditionValue': 10},
        ],
        alreadyUnlocked: <String>{},
        stations: 1,
        events: 0,
        points: 10,
        trips: 0,
        rank: 0,
      );
      expect(newly.length, 2);
      final banner = (await firestore.collection('user_progress').doc(uid).get())
          .data()!['pendingAchievementBanner'];
      expect(banner['subtitle'], '2 új jutalom feloldva!');
    });
  });
}
