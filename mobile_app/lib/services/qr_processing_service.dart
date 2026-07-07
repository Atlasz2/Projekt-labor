import 'package:cloud_firestore/cloud_firestore.dart';

import 'leaderboard_service.dart';

class QrProcessResult {
  const QrProcessResult({
    required this.station,
    required this.alreadyDone,
    required this.newAchievements,
    required this.updatedPoints,
    required this.completedStationsCount,
    required this.completedEventsCount,
  });

  final Map<String, dynamic> station;
  final bool alreadyDone;
  final List<Map<String, dynamic>> newAchievements;
  final int updatedPoints;
  final int completedStationsCount;
  final int completedEventsCount;
}

/// Permanent failure: the scanned code maps to no existing station.
/// Distinct from transient (network/Firestore) errors so the offline queue
/// can drop poison codes instead of retrying them forever.
class QrStationNotFoundException implements Exception {
  const QrStationNotFoundException(this.code);

  final String code;

  @override
  String toString() => 'Ismeretlen QR kod: $code';
}

class QrProcessingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<QrProcessResult> processByCode({
    required String uid,
    required String code,
  }) async {
    final station = await _findStationByCode(code);
    if (station == null) {
      throw QrStationNotFoundException(code);
    }
    return _applyStationProgress(
      uid: uid,
      stationId: station['id'] as String,
      stationData: station,
    );
  }

  static Future<Map<String, dynamic>?> _findStationByCode(String code) async {
    final snap = await _firestore
        .collection('stations')
        .where('qrCode', isEqualTo: code)
        .limit(1)
        .get();

    if (snap.docs.isNotEmpty) {
      final d = snap.docs.first;
      return <String, dynamic>{'id': d.id, ...d.data()};
    }

    final byId = await _firestore.collection('stations').doc(code).get();
    if (byId.exists) {
      return <String, dynamic>{'id': byId.id, ...byId.data()!};
    }

    return null;
  }

  static Future<QrProcessResult> _applyStationProgress({
    required String uid,
    required String stationId,
    required Map<String, dynamic> stationData,
  }) async {
    final progressRef = _firestore.collection('user_progress').doc(uid);
    final progressDoc = await progressRef.get();
    final progressData = progressDoc.data() ?? <String, dynamic>{};

    final completed = List<String>.from(
      progressData['completedStations'] ?? [],
    );
    final completedEvents = List<String>.from(
      progressData['completedEvents'] ?? [],
    );

    final alreadyDone = completed.contains(stationId);
    final stationPoints = (stationData['points'] as num?)?.toInt() ?? 10;
    final currentPoints = (progressData['totalPoints'] as num?)?.toInt() ?? 0;

    var updatedPoints = currentPoints;
    List<Map<String, dynamic>> newAchievements = const [];

    if (!alreadyDone) {
      completed.add(stationId);
      updatedPoints = currentPoints + stationPoints;

      await progressRef.set({
        'completedStations': completed,
        'totalPoints': updatedPoints,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      newAchievements = await _checkAchievements(
        uid: uid,
        completedStations: completed,
        totalPoints: updatedPoints,
        progressData: progressData,
      );
    }

    if (!alreadyDone) {
      await LeaderboardService.syncEntry(
        uid: uid,
        points: updatedPoints,
        completedStationsCount: completed.length,
        completedEventsCount: completedEvents.length,
        displayName: progressData['name']?.toString(),
      );
    }

    return QrProcessResult(
      station: stationData,
      alreadyDone: alreadyDone,
      newAchievements: newAchievements,
      updatedPoints: updatedPoints,
      completedStationsCount: completed.length,
      completedEventsCount: completedEvents.length,
    );
  }

  static Future<List<Map<String, dynamic>>> _checkAchievements({
    required String uid,
    required List<String> completedStations,
    required int totalPoints,
    required Map<String, dynamic> progressData,
  }) async {
    try {
      final results = await Future.wait([
        _firestore.collection('achievements').get(),
        _firestore
            .collection('user_progress')
            .doc(uid)
            .collection('unlocked_achievements')
            .get(),
      ]);

      final achSnap = results[0] as QuerySnapshot;
      final unlockedSnap = results[1] as QuerySnapshot;
      final alreadyUnlocked = unlockedSnap.docs.map((d) => d.id).toSet();

      final completedEvents = List<String>.from(
        progressData['completedEvents'] ?? [],
      );
      final completedTripIds = List<String>.from(
        progressData['completedTripIds'] ?? [],
      );
      final newlyUnlocked = <Map<String, dynamic>>[];

      final batch = _firestore.batch();
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
            _firestore
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
          _firestore.collection('user_progress').doc(uid),
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
