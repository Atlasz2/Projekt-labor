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

  group('reconcile (szerveroldali egyeztetés)', () {
    tearDown(() => AchievementService.reconcileOverride = null);

    test('a szerver által feloldott jutalmakat adja vissza', () async {
      AchievementService.reconcileOverride = () async => [
            {'id': 'ket-allomas', 'name': 'Két állomás'},
          ];
      final newly = await AchievementService.reconcile();
      expect(newly.single['id'], 'ket-allomas');
    });

    test('hiba esetén üres listát ad, nem dob (a képernyő betölthető marad)',
        () async {
      AchievementService.reconcileOverride =
          () async => throw Exception('unavailable');
      expect(await AchievementService.reconcile(), isEmpty);
    });
  });
}
