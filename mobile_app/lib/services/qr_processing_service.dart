import 'package:cloud_firestore/cloud_firestore.dart';

import 'leaderboard_service.dart';

/// Mit azonosított a beolvasott QR-kód: állomást vagy eseményt.
enum QrTargetKind { station, event }

class QrProcessResult {
  const QrProcessResult({
    required this.target,
    required this.kind,
    required this.alreadyDone,
    required this.newAchievements,
    required this.updatedPoints,
    required this.completedStationsCount,
    required this.completedEventsCount,
  });

  /// A beolvasott állomás vagy esemény dokumentuma (`kind` mondja meg, melyik).
  final Map<String, dynamic> target;
  final QrTargetKind kind;
  final bool alreadyDone;
  final List<Map<String, dynamic>> newAchievements;
  final int updatedPoints;
  final int completedStationsCount;
  final int completedEventsCount;
}

/// Permanent failure: the scanned code maps to no existing station or event.
/// Distinct from transient (network/Firestore) errors so the offline queue
/// can drop poison codes instead of retrying them forever.
class QrCodeNotFoundException implements Exception {
  const QrCodeNotFoundException(this.code);

  final String code;

  @override
  String toString() => 'Ismeretlen QR kod: $code';
}

class _ProgressOutcome {
  const _ProgressOutcome({
    required this.alreadyDone,
    required this.updatedPoints,
    required this.completedStations,
    required this.completedEvents,
    required this.progressData,
  });

  final bool alreadyDone;
  final int updatedPoints;
  final List<String> completedStations;
  final List<String> completedEvents;
  final Map<String, dynamic> progressData;
}

class QrProcessingService {
  /// Tesztekben lecserélhető (fake_cloud_firestore); élesben az alapértelmezett.
  static FirebaseFirestore firestore = FirebaseFirestore.instance;

  static Future<QrProcessResult> processByCode({
    required String uid,
    required String code,
  }) async {
    final station = await _findByCode('stations', code);
    if (station != null) {
      return _applyProgress(
        uid: uid,
        kind: QrTargetKind.station,
        targetId: station['id'] as String,
        targetData: station,
      );
    }

    final event = await _findByCode('events', code);
    if (event != null) {
      return _applyProgress(
        uid: uid,
        kind: QrTargetKind.event,
        targetId: event['id'] as String,
        targetData: event,
      );
    }

    throw QrCodeNotFoundException(code);
  }

  static Future<Map<String, dynamic>?> _findByCode(
    String collection,
    String code,
  ) async {
    final snap = await firestore
        .collection(collection)
        .where('qrCode', isEqualTo: code)
        .limit(1)
        .get();

    if (snap.docs.isNotEmpty) {
      final d = snap.docs.first;
      return <String, dynamic>{'id': d.id, ...d.data()};
    }

    // Doc-id fallback. A '/'-t tartalmazó kód nem lehet érvényes dokumentum-út,
    // és a doc() hívás ArgumentError-t dobna rá.
    if (!code.contains('/')) {
      final byId = await firestore.collection(collection).doc(code).get();
      if (byId.exists) {
        return <String, dynamic>{'id': byId.id, ...byId.data()!};
      }
    }

    return null;
  }

  static Future<QrProcessResult> _applyProgress({
    required String uid,
    required QrTargetKind kind,
    required String targetId,
    required Map<String, dynamic> targetData,
  }) async {
    final progressRef = firestore.collection('user_progress').doc(uid);
    final listField = kind == QrTargetKind.station
        ? 'completedStations'
        : 'completedEvents';
    final points = (targetData['points'] as num?)?.toInt() ?? 10;

    // A security rules a user_progress létrehozását csak nullázott számlálókkal
    // engedik, ezért az increment előtt biztosítjuk, hogy a doksi létezzen.
    // (Normál esetben a regisztráció hozza létre; ez a legacy/edge eseteket fedi.)
    final existing = await progressRef.get();
    if (!existing.exists) {
      await progressRef.set({
        'totalPoints': 0,
        'completedStations': <String>[],
        'completedEvents': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // Atomi jóváírás: az olvasás és a feltételes írás egy tranzakcióban fut,
    // így két párhuzamos feldolgozás (pl. élő beolvasás + offline szinkron)
    // nem tudja ugyanazt a kódot kétszer jóváírni.
    final outcome = await firestore.runTransaction<_ProgressOutcome>((
      tx,
    ) async {
      final snap = await tx.get(progressRef);
      final data = snap.data() ?? <String, dynamic>{};

      final completedStations = List<String>.from(
        data['completedStations'] ?? [],
      );
      final completedEvents = List<String>.from(data['completedEvents'] ?? []);
      final currentPoints = (data['totalPoints'] as num?)?.toInt() ?? 0;

      final completedList = kind == QrTargetKind.station
          ? completedStations
          : completedEvents;
      final alreadyDone = completedList.contains(targetId);

      if (!alreadyDone) {
        completedList.add(targetId);
        // update (nem set+merge): a doksi létezését fentebb garantáltuk, és
        // így a transzformok a meglévő értékekre épülnek.
        tx.update(progressRef, {
          listField: FieldValue.arrayUnion([targetId]),
          'totalPoints': FieldValue.increment(points),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      return _ProgressOutcome(
        alreadyDone: alreadyDone,
        updatedPoints: alreadyDone ? currentPoints : currentPoints + points,
        completedStations: completedStations,
        completedEvents: completedEvents,
        progressData: data,
      );
    });

    List<Map<String, dynamic>> newAchievements = const [];
    if (!outcome.alreadyDone) {
      newAchievements = await _checkAchievements(
        uid: uid,
        completedStations: outcome.completedStations,
        completedEvents: outcome.completedEvents,
        totalPoints: outcome.updatedPoints,
        progressData: outcome.progressData,
      );

      await LeaderboardService.syncEntry(
        uid: uid,
        points: outcome.updatedPoints,
        completedStationsCount: outcome.completedStations.length,
        completedEventsCount: outcome.completedEvents.length,
        displayName: outcome.progressData['name']?.toString(),
      );
    }

    return QrProcessResult(
      target: targetData,
      kind: kind,
      alreadyDone: outcome.alreadyDone,
      newAchievements: newAchievements,
      updatedPoints: outcome.updatedPoints,
      completedStationsCount: outcome.completedStations.length,
      completedEventsCount: outcome.completedEvents.length,
    );
  }

  static Future<List<Map<String, dynamic>>> _checkAchievements({
    required String uid,
    required List<String> completedStations,
    required List<String> completedEvents,
    required int totalPoints,
    required Map<String, dynamic> progressData,
  }) async {
    try {
      final results = await Future.wait([
        firestore.collection('achievements').get(),
        firestore
            .collection('user_progress')
            .doc(uid)
            .collection('unlocked_achievements')
            .get(),
      ]);

      final achSnap = results[0] as QuerySnapshot;
      final unlockedSnap = results[1] as QuerySnapshot;
      final alreadyUnlocked = unlockedSnap.docs.map((d) => d.id).toSet();

      final completedTripIds = List<String>.from(
        progressData['completedTripIds'] ?? [],
      );
      final newlyUnlocked = <Map<String, dynamic>>[];

      final batch = firestore.batch();
      for (final doc in achSnap.docs) {
        final id = doc.id;
        if (alreadyUnlocked.contains(id)) continue;

        final achData = doc.data() as Map<String, dynamic>;
        final type = achData['conditionType']?.toString() ?? '';
        final target = (achData['conditionValue'] as num?)?.toInt() ?? 1;

        bool met = false;
        if (type == 'station_count') {
          met = completedStations.length >= target;
        } else if (type == 'event_count') {
          met = completedEvents.length >= target;
        } else if (type == 'qr_count') {
          met = (completedStations.length + completedEvents.length) >= target;
        } else if (type == 'points_threshold') {
          met = totalPoints >= target;
        } else if (type == 'trip_complete') {
          met = completedTripIds.length >= target;
        }

        if (met) {
          batch.set(
            firestore
                .collection('user_progress')
                .doc(uid)
                .collection('unlocked_achievements')
                .doc(id),
            {'unlockedAt': FieldValue.serverTimestamp()},
          );
          // NOTE: we intentionally do NOT increment achievements/{id}.unlockedCount
          // here — that collection is admin-write-only, so including it would make
          // the whole batch fail with permission-denied and the unlock (plus its
          // notification) would never commit.
          newlyUnlocked.add({'id': id, ...achData});
        }
      }

      if (newlyUnlocked.isNotEmpty) {
        final first = newlyUnlocked.first;
        batch.set(
          firestore.collection('user_progress').doc(uid),
          {
            'pendingAchievementBanner': {
              'title': first['name']?.toString() ?? 'Jutalom feloldva!',
              'subtitle': newlyUnlocked.length == 1
                  ? (first['description']?.toString() ?? '')
                  : "${newlyUnlocked.length} új jutalom feloldva!",
            },
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
      return newlyUnlocked;
    } catch (_) {
      return [];
    }
  }
}
