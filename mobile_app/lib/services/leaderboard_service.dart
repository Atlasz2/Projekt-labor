import 'package:cloud_firestore/cloud_firestore.dart';

class LeaderboardService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> syncEntry({
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
          'Felhasználó';
    }

    await _firestore.collection('public_leaderboard').doc(uid).set({
      'displayName': effectiveName,
      'points': points,
      'completedStationsCount': completedStationsCount,
      'completedEventsCount': completedEventsCount,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  const LeaderboardService._();
}