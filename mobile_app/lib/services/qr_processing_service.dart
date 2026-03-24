import 'package:cloud_firestore/cloud_firestore.dart';

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

class QrProcessingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<QrProcessResult> processByCode({
    required String uid,
    required String code,
  }) async {
    final station = await _findStationByCode(code);
    if (station == null) {
      throw Exception('Ismeretlen QR kod: $code');
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

    await _syncLeaderboardEntry(
      uid: uid,
      points: updatedPoints,
      completedStationsCount: completed.length,
      completedEventsCount: completedEvents.length,
      displayName: progressData['name']?.toString(),
    );

    return QrProcessResult(
      station: stationData,
      alreadyDone: alreadyDone,
      newAchievements: newAchievements,
      updatedPoints: updatedPoints,
      completedStationsCount: completed.length,
      completedEventsCount: completedEvents.length,
    );
  }

  static Future<void> _syncLeaderboardEntry({
    required String uid,
    required int points,
    required int completedStationsCount,
    required int completedEventsCount,
    String? displayName,
  }) async {
    var effectiveName = displayName?.trim() ?? '';
    if (effectiveName.isEmpty) {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final userData = userDoc.data() ?? <String, dynamic>{};
      effectiveName =
          userData['displayName']?.toString() ??
          userData['name']?.toString() ??
          'Felhasznalo';
    }

    await _firestore.collection('public_leaderboard').doc(uid).set({
      'displayName': effectiveName,
      'points': points,
      'completedStationsCount': completedStationsCount,
      'completedEventsCount': completedEventsCount,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
          await _firestore
              .collection('user_progress')
              .doc(uid)
              .collection('unlocked_achievements')
              .doc(id)
              .set({'unlockedAt': FieldValue.serverTimestamp()});

          await _firestore.collection('achievements').doc(id).update({
            'unlockedCount': FieldValue.increment(1),
          });

          newlyUnlocked.add({'id': id, ...achData});
        }
      }

      if (newlyUnlocked.isNotEmpty) {
        final first = newlyUnlocked.first;
        await _firestore.collection('user_progress').doc(uid).set({
          'pendingAchievementBanner': {
            'title': first['name']?.toString() ?? 'Jutalom feloldva! 🏆',
            'subtitle': newlyUnlocked.length == 1
                ? (first['description']?.toString() ?? '')
                : '${newlyUnlocked.length} uj jutalom feloldva!',
          },
        }, SetOptions(merge: true));
      }

      return newlyUnlocked;
    } catch (_) {
      return [];
    }
  }
}
