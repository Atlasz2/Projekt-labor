import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _controller = MobileScannerController();

  bool _scanning = true;
  bool _loading = false;
  Map<String, dynamic>? _station;
  String? _errorMsg;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await _firestore.collection('user_progress').doc(uid).get();
      final data = doc.data() ?? {};
      final completed = List<String>.from(data['completedStations'] ?? []);
      if (completed.isEmpty) return;
      final stSnap = await _firestore.collection('stations').get();
      final all = {
        for (final d in stSnap.docs)
          d.id: <String, dynamic>{'id': d.id, ...d.data()},
      };
      if (!mounted) return;
      setState(() {
        _history = completed
            .map((id) => all[id] ?? {'name': id})
            .toList()
            .reversed
            .take(10)
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _syncLeaderboardEntry({
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

  Future<void> _onQrDetected(String code) async {
    if (!_scanning || _loading) return;
    setState(() {
      _scanning = false;
      _loading = true;
      _errorMsg = null;
    });
    _controller.stop();

    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) throw Exception('Nincs bejelentkezett felhasznalo');

      var snap = await _firestore
          .collection('stations')
          .where('qrCode', isEqualTo: code)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        final byId = await _firestore.collection('stations').doc(code).get();
        if (byId.exists) {
          await _handleStationFound(uid, byId.id, <String, dynamic>{
            'id': byId.id,
            ...byId.data()!,
          });
          return;
        }
        throw Exception('Ismeretlen QR kod: $code');
      }

      final stDoc = snap.docs.first;
      final stData = stDoc.data();
      await _handleStationFound(uid, stDoc.id, <String, dynamic>{
        'id': stDoc.id,
        ...stData,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = 'Hiba: ${e.toString().replaceAll('Exception: ', '')}';
      });
    }
  }

  Future<void> _handleStationFound(
    String uid,
    String stationId,
    Map<String, dynamic> data,
  ) async {
    final progressRef = _firestore.collection('user_progress').doc(uid);
    final progressDoc = await progressRef.get();
    final progressData = progressDoc.data() ?? {};
    final completed = List<String>.from(
      progressData['completedStations'] ?? [],
    );
    final completedEvents = List<String>.from(
      progressData['completedEvents'] ?? [],
    );
    final alreadyDone = completed.contains(stationId);
    final stationPoints = (data['points'] as num?)?.toInt() ?? 10;
    final currentPoints = (progressData['totalPoints'] as num?)?.toInt() ?? 0;
    var updatedPoints = currentPoints;
    List<Map<String, dynamic>> newAch = [];

    if (!alreadyDone) {
      completed.add(stationId);
      updatedPoints = currentPoints + stationPoints;
      await progressRef.set({
        'completedStations': completed,
        'totalPoints': updatedPoints,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      newAch = await _checkAchievements(
        uid,
        completed,
        updatedPoints,
        progressData,
      );
    }

    await _syncLeaderboardEntry(
      uid: uid,
      displayName: progressData['name']?.toString(),
      points: updatedPoints,
      completedStationsCount: completed.length,
      completedEventsCount: completedEvents.length,
    );

    if (!mounted) return;
    setState(() {
      _station = {
        ...data,
        'alreadyDone': alreadyDone,
        'newAchievements': newAch,
      };
      _loading = false;
    });
    _loadHistory();
  }

  Future<List<Map<String, dynamic>>> _checkAchievements(
    String uid,
    List<String> completedStations,
    int totalPoints,
    Map<String, dynamic> progressData,
  ) async {
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
    } catch (e) {
      debugPrint('Achievement check failed: $e');
      return [];
    }
  }

  void _reset() {
    setState(() {
      _scanning = true;
      _station = null;
      _errorMsg = null;
    });
    _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Beolvasas'),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Elozmenyek',
              onPressed: () => _showHistory(context),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _station != null
          ? _buildResult()
          : _errorMsg != null
          ? _buildError()
          : _buildScanner(),
    );
  }

  Widget _buildScanner() {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(24),
            ),
            child: Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: (capture) {
                    final code = capture.barcodes.firstOrNull?.rawValue;
                    if (code != null) _onQrDetected(code);
                  },
                ),
                Center(
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.black54,
                    child: const Text(
                      'Iranyitsd a QR kodra a keretet',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_history.isNotEmpty)
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nemreg beolvasva (${_history.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _history.length,
                      itemBuilder: (_, i) => ListTile(
                        leading: const Icon(
                          Icons.check_circle,
                          color: Color(0xFF4CAF50),
                          size: 20,
                        ),
                        title: Text(
                          _history[i]['name'] ?? 'Ismeretlen',
                          style: const TextStyle(fontSize: 13),
                        ),
                        trailing: Text(
                          '${_history[i]['points'] ?? '?'} pt',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildResult() {
    final s = _station!;
    final alreadyDone = s['alreadyDone'] == true;
    final points = (s['points'] as num?)?.toInt() ?? 10;
    final name = s['name']?.toString() ?? 'Allomas';
    final unlockContent = s['unlockContent']?.toString() ?? '';
    final extraInfo = s['extraInfo']?.toString() ?? '';
    final imageUrl = s['imageUrl']?.toString() ?? '';
    final newAch =
        (s['newAchievements'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 12),
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                imageUrl,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, trace) => const SizedBox.shrink(),
              ),
            ),
          const SizedBox(height: 20),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: alreadyDone
                  ? Colors.grey.shade200
                  : const Color(0xFF4CAF50).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              alreadyDone ? Icons.repeat_rounded : Icons.check_circle_rounded,
              size: 48,
              color: alreadyDone ? Colors.grey : const Color(0xFF4CAF50),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: alreadyDone
                  ? Colors.grey.shade100
                  : Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.star_rounded,
                  color: alreadyDone ? Colors.grey : Colors.amber,
                ),
                const SizedBox(width: 6),
                Text(
                  alreadyDone ? 'Mar feloldott (+0 pt)' : '+$points pont',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: alreadyDone ? Colors.grey : Colors.amber.shade700,
                  ),
                ),
              ],
            ),
          ),
          if (newAch.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF9C4), Color(0xFFFFF3E0)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.emoji_events, color: Colors.amber, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Uj jutalom feloldva! 🎉',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...newAch.map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Text(
                            a['icon']?.toString() ?? '🏆',
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a['name']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                if ((a['description']?.toString() ?? '')
                                    .isNotEmpty)
                                  Text(
                                    a['description'].toString(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (unlockContent.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lock_open, color: Colors.amber, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Feloldott tartalom',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    unlockContent,
                    style: const TextStyle(fontSize: 14, height: 1.6),
                  ),
                ],
              ),
            ),
          ],
          if (extraInfo.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Color(0xFF667EEA),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      extraInfo,
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Ujabb beolvasas'),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMsg ?? 'Ismeretlen hiba',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh),
              label: const Text('Ujra probals'),
            ),
          ],
        ),
      ),
    );
  }

  void _showHistory(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Beolvasasi elozmenyek',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _history.length,
                itemBuilder: (_, i) {
                  final st = _history[i];
                  return ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF4CAF50),
                      child: Icon(Icons.check, color: Colors.white, size: 18),
                    ),
                    title: Text(st['name'] ?? 'Ismeretlen'),
                    subtitle: Text(st['description'] ?? ''),
                    trailing: Text(
                      '${st['points'] ?? '?'} pt',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
