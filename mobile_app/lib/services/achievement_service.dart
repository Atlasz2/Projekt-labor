import 'package:cloud_firestore/cloud_firestore.dart';

/// A jutalom-feloldás közös logikája. Egy adott haladás alapján eldönti, mely
/// jutalmak teljesültek, és feloldja azokat, amelyek még nincsenek feloldva.
///
/// A QR-beolvasás (qr_processing_service) csak a beolvasás pillanatában
/// ellenőriz; ez a "reconcile" ugyanazt a logikát futtatja képernyő-
/// betöltéskor is, így egy jutalom akkor is feloldódik, ha a feltétel nem friss
/// beolvasással teljesült (pl. utólag létrehozott jutalom, top-N rangváltozás,
/// vagy egy korábban elbukott feloldás).
class AchievementService {
  /// Tesztekben lecserélhető; élesben az alapértelmezett példány.
  static FirebaseFirestore firestore = FirebaseFirestore.instance;

  const AchievementService._();

  /// Kiszámolja, teljesült-e egy jutalom feltétele a megadott haladással.
  /// A `rank` a ranglistán elfoglalt hely (1-alapú); 0, ha nem ismert.
  static bool isConditionMet({
    required String type,
    required int target,
    required int stations,
    required int events,
    required int points,
    required int trips,
    required int rank,
  }) {
    switch (type) {
      case 'station_count':
        return stations >= target;
      case 'event_count':
        return events >= target;
      case 'qr_count':
        return (stations + events) >= target;
      case 'points_threshold':
        return points >= target;
      case 'trip_complete':
        return trips >= target;
      case 'top_n':
        return rank > 0 && rank <= target;
      default:
        // 'manual' és ismeretlen: nem oldódik fel automatikusan.
        return false;
    }
  }

  /// A már betöltött jutalmak és haladás alapján feloldja a teljesített, de még
  /// fel nem oldott jutalmakat. A hívó adja az adatokat (nincs dupla lekérdezés).
  /// Visszaadja az újonnan feloldott jutalmakat (bannerhez/értesítéshez).
  static Future<List<Map<String, dynamic>>> reconcileFromStats({
    required String uid,
    required List<Map<String, dynamic>> achievements,
    required Set<String> alreadyUnlocked,
    required int stations,
    required int events,
    required int points,
    required int trips,
    required int rank,
  }) async {
    final newlyUnlocked = <Map<String, dynamic>>[];
    final batch = firestore.batch();

    for (final ach in achievements) {
      final id = (ach['id'] ?? '').toString();
      if (id.isEmpty || alreadyUnlocked.contains(id)) continue;

      final type = ach['conditionType']?.toString() ?? '';
      final rawTarget = (ach['conditionValue'] as num?)?.toInt() ?? 1;
      final target = rawTarget <= 0 ? 1 : rawTarget;

      final met = isConditionMet(
        type: type,
        target: target,
        stations: stations,
        events: events,
        points: points,
        trips: trips,
        rank: rank,
      );
      if (!met) continue;

      batch.set(
        firestore
            .collection('user_progress')
            .doc(uid)
            .collection('unlocked_achievements')
            .doc(id),
        {'unlockedAt': FieldValue.serverTimestamp()},
      );
      newlyUnlocked.add(Map<String, dynamic>.from(ach));
    }

    if (newlyUnlocked.isEmpty) return const [];

    // Egy banner a főmenüben (a qr_processing ugyanezt a mezőt használja).
    final first = newlyUnlocked.first;
    batch.set(
      firestore.collection('user_progress').doc(uid),
      {
        'pendingAchievementBanner': {
          'title': first['name']?.toString() ?? 'Jutalom feloldva!',
          'subtitle': newlyUnlocked.length == 1
              ? (first['description']?.toString() ?? '')
              : '${newlyUnlocked.length} új jutalom feloldva!',
        },
      },
      SetOptions(merge: true),
    );

    await batch.commit();
    return newlyUnlocked;
  }
}
