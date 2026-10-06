import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/app_config.dart';

/// A település saját ranglistájának olvasása. A ranglistát kizárólag a szerver
/// írja (redeemQr), a kliens csak olvas.
class LeaderboardService {
  const LeaderboardService._();

  /// Tesztekben lecserélhető (fake_cloud_firestore); élesben az alapértelmezett.
  static FirebaseFirestore firestore = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _entries => firestore
      .collection('leaderboards')
      .doc(AppConfig.projectId)
      .collection('entries');

  /// Az első [limit] helyezett, pontszám szerint csökkenő sorrendben.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> top(
    int limit,
  ) async {
    final snap = await _entries
        .orderBy('points', descending: true)
        .limit(limit)
        .get();
    return snap.docs;
  }

  /// A felhasználó helyezése (1-alapú), vagy 0, ha még nincs a ranglistán.
  /// A teljes lista letöltése helyett egy számláló lekérdezést futtat: hány
  /// bejegyzés pontszáma nagyobb a sajátnál.
  static Future<int> rankOf(String uid) async {
    final mine = await _entries.doc(uid).get();
    final points = (mine.data()?['points'] as num?)?.toInt();
    if (points == null) return 0;
    final higher = await _entries
        .where('points', isGreaterThan: points)
        .count()
        .get();
    return (higher.count ?? 0) + 1;
  }
}
