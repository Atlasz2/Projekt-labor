import 'dart:async';

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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final MobileScannerController _scannerController = MobileScannerController();

  final List<Map<String, dynamic>> _scanHistory = [];
  final Set<String> _completedStationIds = <String>{};
  final Set<String> _completedEventIds = <String>{};
  List<Map<String, dynamic>> _achievements = [];
  Set<String> _unlockedAchievementIds = <String>{};
  Set<String> _completedTripIds = <String>{};

  bool _isLoading = true;
  bool _isProcessing = false;
  String? _error;
  int _totalPoints = 0;

  bool _showFeedbackOverlay = false;
  bool _showAchievementOverlay = false;
  bool _feedbackSuccess = true;
  String _feedbackTitle = '';
  String _feedbackSubtitle = '';
  int? _feedbackPoints;
  String _achievementTitle = '';
  String _achievementSubtitle = '';

  String? _lastCode;
  DateTime _lastScanAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _scanCooldown = Duration(milliseconds: 1800);
  DateTime _nextAllowedScanAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _overlayTimer;
  Timer? _achievementTimer;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    _achievementTimer?.cancel();
    _scannerController.dispose();
    super.dispose();
  }

  int _safeInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

  Future<void> _initData() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
        _error = 'Nincs bejelentkezett felhasznalo.';
      });
      return;
    }

    try {
      await _ensureProgressDoc(user);
      await _loadProgress(user.uid);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Hiba a QR adatok betoltesekor: $e';
        });
      }
    }
  }

  Future<void> _ensureProgressDoc(User user) async {
    final progressRef = _firestore.collection('user_progress').doc(user.uid);
    final progressDoc = await progressRef.get();
    if (!progressDoc.exists) {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};
      await progressRef.set({
        'name': userData['displayName'] ?? userData['name'] ?? 'Felhasznalo',
        'email': user.email ?? userData['email'] ?? '',
        'completedStations': <String>[],
        'completedEvents': <String>[],
        'totalPoints': 0,
        'currentTrip': 'Nincs tura',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _loadProgress(String userId) async {
    final progressDoc = await _firestore.collection('user_progress').doc(userId).get();
    final progressData = progressDoc.data() ?? {};

    final completedStations = (progressData['completedStations'] as List?)
            ?.map((item) => item.toString())
            .toSet() ??
        <String>{};
    final completedEvents = (progressData['completedEvents'] as List?)
            ?.map((item) => item.toString())
            .toSet() ??
        <String>{};

    final stationHistorySnapshot = await _firestore
        .collection('user_progress')
        .doc(userId)
        .collection('completed_stations')
        .get();
    final eventHistorySnapshot = await _firestore
        .collection('user_progress')
        .doc(userId)
        .collection('completed_events')
        .get();

    final history = <Map<String, dynamic>>[];

    for (final item in stationHistorySnapshot.docs) {
      final data = item.data();
      final ts = data['scannedAt'];
      history.add({
        'id': item.id,
        'type': 'station',
        'name': (data['stationName'] ?? 'Ismeretlen allomas').toString(),
        'points': _safeInt(data['points']),
        'date': ts is Timestamp ? ts.toDate() : null,
      });
    }

    for (final item in eventHistorySnapshot.docs) {
      final data = item.data();
      final ts = data['scannedAt'];
      history.add({
        'id': item.id,
        'type': 'event',
        'name': (data['eventName'] ?? 'Ismeretlen esemeny').toString(),
        'points': _safeInt(data['points']),
        'date': ts is Timestamp ? ts.toDate() : null,
      });
    }

    history.sort((a, b) {
      final ad = a['date'] as DateTime?;
      final bd = b['date'] as DateTime?;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });

    final achSnap = await _firestore.collection('achievements').get();
    final achievements = achSnap.docs
        .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
        .toList();
    final unlockedSnap = await _firestore
        .collection('user_progress')
        .doc(userId)
        .collection('unlocked_achievements')
        .get();
    final unlockedIds = unlockedSnap.docs.map((d) => d.id).toSet();
    final completedTripIds =
        ((progressData['completedTripIds'] as List<dynamic>?) ?? [])
            .map((e) => e.toString())
            .toSet();
    setState(() {
      _completedStationIds
        ..clear()
        ..addAll(completedStations);
      _completedEventIds
        ..clear()
        ..addAll(completedEvents);
      _scanHistory
        ..clear()
        ..addAll(history);
      _totalPoints = _safeInt(progressData['totalPoints']);
      _achievements = achievements;
      _unlockedAchievementIds = unlockedIds;
      _completedTripIds = completedTripIds;
    });
  }

  Set<String> _extractCandidates(String raw) {
    final candidates = <String>{};

    void add(String? value) {
      if (value == null) return;
      final v = value.trim();
      if (v.isEmpty) return;
      candidates.add(v);
      candidates.add(v.toLowerCase());
      candidates.add(v.toUpperCase());
      if (v.contains(':')) {
        final split = v.split(':');
        if (split.length > 1) {
          add(split.last);
        }
      }
    }

    add(raw);
    add(Uri.decodeComponent(raw));

    final uri = Uri.tryParse(raw);
    if (uri != null) {
      if (uri.pathSegments.isNotEmpty) {
        add(uri.pathSegments.last);
      }
      for (final entry in uri.queryParameters.entries) {
        add(entry.value);
      }
    }

    return candidates;
  }

  Future<Map<String, dynamic>?> _findTargetByCode(String rawCode) async {
    final candidates = _extractCandidates(rawCode);

    for (final candidate in candidates) {
      final stationByQr = await _firestore
          .collection('stations')
          .where('qrCode', isEqualTo: candidate)
          .limit(1)
          .get();
      if (stationByQr.docs.isNotEmpty) {
        final doc = stationByQr.docs.first;
        final data = doc.data();
        return {
          'kind': 'station',
          'id': doc.id,
          'name': (data['name'] ?? 'Ismeretlen allomas').toString(),
          'points': _safeInt(data['points'], fallback: 10),
          'tripId': (data['tripId'] ?? '').toString(),
          'description': (data['description'] ?? '').toString(),
          'funFact': (data['funFact'] ?? '').toString(),
          'unlockContent': (data['unlockContent'] ?? '').toString(),
          'extraInfo': (data['extraInfo'] ?? '').toString(),
        };
      }
    }

    for (final candidate in candidates) {
      final stationDoc = await _firestore.collection('stations').doc(candidate).get();
      if (stationDoc.exists) {
        final data = stationDoc.data() ?? {};
        return {
          'kind': 'station',
          'id': stationDoc.id,
          'name': (data['name'] ?? 'Ismeretlen allomas').toString(),
          'points': _safeInt(data['points'], fallback: 10),
          'tripId': (data['tripId'] ?? '').toString(),
          'description': (data['description'] ?? '').toString(),
          'funFact': (data['funFact'] ?? '').toString(),
          'unlockContent': (data['unlockContent'] ?? '').toString(),
          'extraInfo': (data['extraInfo'] ?? '').toString(),
        };
      }
    }

    for (final candidate in candidates) {
      final eventByQr = await _firestore
          .collection('events')
          .where('qrCode', isEqualTo: candidate)
          .limit(1)
          .get();
      if (eventByQr.docs.isNotEmpty) {
        final doc = eventByQr.docs.first;
        final data = doc.data();
        return {
          'kind': 'event',
          'id': doc.id,
          'name': (data['name'] ?? 'Ismeretlen esemeny').toString(),
          'points': _safeInt(data['points'], fallback: 20),
        };
      }
    }

    for (final candidate in candidates) {
      final eventDoc = await _firestore.collection('events').doc(candidate).get();
      if (eventDoc.exists) {
        final data = eventDoc.data() ?? {};
        return {
          'kind': 'event',
          'id': eventDoc.id,
          'name': (data['name'] ?? 'Ismeretlen esemeny').toString(),
          'points': _safeInt(data['points'], fallback: 20),
        };
      }
    }

    return null;
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing || capture.barcodes.isEmpty) return;
    final now = DateTime.now();
    if (now.isBefore(_nextAllowedScanAt)) return;

    final rawValue = capture.barcodes.first.rawValue?.trim();
    if (rawValue == null || rawValue.isEmpty) return;

    final sameAsLast = _lastCode == rawValue;
    if (sameAsLast && now.difference(_lastScanAt) < _scanCooldown) return;

    _lastCode = rawValue;
    _lastScanAt = now;
    _processScan(rawValue);
  }

  Future<void> _processScan(String code) async {
    final user = _auth.currentUser;
    if (user == null) {
      _showFeedback(success: false, title: 'Nincs bejelentkezes', subtitle: 'Jelentkezz be az appba.');
      _showSnack('Nincs bejelentkezett felhasznalo.');
      return;
    }

    _isProcessing = true;

    try {
      final target = await _findTargetByCode(code);
      if (target == null) {
        _showFeedback(success: false, title: 'Ismeretlen QR-kod', subtitle: 'Ezt a kodot nem talaltam az adatbazisban.');
        _showSnack('Ismeretlen QR-kod.');
        return;
      }

      final id = target['id'] as String;
      final kind = target['kind'] as String;
      final name = target['name'] as String;
      final points = target['points'] as int;
      final tripId = (target['tripId'] ?? '').toString();
      final beforeStations = _completedStationIds.length;
      final beforeEvents = _completedEventIds.length;
      final beforePoints = _totalPoints;

      if (kind == 'station' && _completedStationIds.contains(id)) {
        _showFeedback(success: false, title: 'Mar beolvasva', subtitle: '$name mar korabban rogzitve lett.');
        _showSnack('Ez az allomas mar be lett olvasva.');
        return;
      }
      if (kind == 'event' && _completedEventIds.contains(id)) {
        _showFeedback(success: false, title: 'Mar beolvasva', subtitle: '$name esemeny pecset mar megvan.');
        _showSnack('Ehhez az esemenyhez mar megszerezted a pecsetet.');
        return;
      }

      final userProgressRef = _firestore.collection('user_progress').doc(user.uid);
      final batch = _firestore.batch();

      if (kind == 'station') {
        batch.set(userProgressRef, {
          'completedStations': FieldValue.arrayUnion([id]),
          'totalPoints': FieldValue.increment(points),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        batch.set(userProgressRef.collection('completed_stations').doc(id), {
          'stationId': id,
          'stationName': name,
          'points': points,
          'scannedCode': code,
          'scannedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        batch.set(userProgressRef, {
          'completedEvents': FieldValue.arrayUnion([id]),
          'totalPoints': FieldValue.increment(points),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        batch.set(userProgressRef.collection('completed_events').doc(id), {
          'eventId': id,
          'eventName': name,
          'points': points,
          'scannedCode': code,
          'scannedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await batch.commit();

      setState(() {
        if (kind == 'station') {
          _completedStationIds.add(id);
        } else {
          _completedEventIds.add(id);
        }
        _totalPoints += points;
        _scanHistory.insert(0, {
          'id': id,
          'type': kind,
          'name': name,
          'points': points,
          'date': DateTime.now(),
        });
      });

      _showFeedback(
        success: true,
        title: 'Sikeres beolvasas!',
        subtitle: name,
        points: points,
      );

      if (kind == 'station') {
        await _presentUnlockContent(target);
      }
      final afterStations = kind == 'station' ? beforeStations + 1 : beforeStations;
      final afterEvents = kind == 'event' ? beforeEvents + 1 : beforeEvents;
      final afterPoints = beforePoints + points;
      if (kind == 'station' && tripId.isNotEmpty) {
        await _checkAndMarkTripComplete(tripId, user.uid);
      }
      await _checkAndUnlockAchievements(
        stations: afterStations,
        events: afterEvents,
        points: afterPoints,
        uid: user.uid,
      );
            _showSnack(kind == 'event'
          ? 'Esemeny pecset megszerezve: $name (+$points pont)'
          : 'Sikeres beolvasas: $name (+$points pont)');
    } catch (e) {
      _showFeedback(success: false, title: 'Mentesi hiba', subtitle: '$e');
      _showSnack('Hiba a beolvasas mentesekor: $e');
    } finally {
      _isProcessing = false;
      _nextAllowedScanAt = DateTime.now().add(const Duration(milliseconds: 900));
    }
  }

  void _showFeedback({
    required bool success,
    required String title,
    required String subtitle,
    int? points,
  }) {
    _overlayTimer?.cancel();
    _achievementTimer?.cancel();
    if (!mounted) return;

    setState(() {
      _feedbackSuccess = success;
      _feedbackTitle = title;
      _feedbackSubtitle = subtitle;
      _feedbackPoints = points;
      _showFeedbackOverlay = true;
    });

    _overlayTimer = Timer(const Duration(milliseconds: 1450), () {
      if (!mounted) return;
      setState(() => _showFeedbackOverlay = false);
    });
  }


  Future<void> _presentUnlockContent(Map<String, dynamic> target) async {
    final unlockContent = (target['unlockContent'] ?? '').toString().trim();
    final funFact = (target['funFact'] ?? '').toString().trim();
    final stationDesc = (target['description'] ?? '').toString().trim();
    final extraInfo = (target['extraInfo'] ?? '').toString().trim();
    if (unlockContent.isEmpty && funFact.isEmpty && stationDesc.isEmpty && extraInfo.isEmpty) {
      return;
    }

    _nextAllowedScanAt = DateTime.now().add(const Duration(seconds: 4));
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;

    try {
      await _scannerController.stop();
    } catch (_) {}

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UnlockSheet(target: target),
    );

    if (!mounted) return;

    try {
      await _scannerController.start();
    } catch (_) {}

    _lastScanAt = DateTime.now();
    _nextAllowedScanAt = DateTime.now().add(const Duration(milliseconds: 1200));
  }
  Future<void> _checkAndMarkTripComplete(String tripId, String uid) async {
    if (_completedTripIds.contains(tripId)) return;
    try {
      await _firestore.collection('trips').doc(tripId).get();

      final stationsSnapshot = await _firestore
          .collection('stations')
          .where('tripId', isEqualTo: tripId)
          .get();
      final stationIds = stationsSnapshot.docs.map((d) => d.id).toSet();
      if (stationIds.isEmpty) return;
      final doneCount =
          stationIds.where((id) => _completedStationIds.contains(id)).length;
      if (doneCount >= stationIds.length) {
        _completedTripIds.add(tripId);
        await _firestore.collection('user_progress').doc(uid).set({
          'completedTripIds': FieldValue.arrayUnion([tripId]),
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  Future<void> _checkAndUnlockAchievements({
    required int stations,
    required int events,
    required int points,
    required String uid,
  }) async {
    final newlyUnlocked = <Map<String, String>>[];
    for (final ach in _achievements) {
      final id = (ach['id'] ?? '').toString();
      if (id.isEmpty || _unlockedAchievementIds.contains(id)) continue;
      final conditionType = (ach['conditionType'] ?? '').toString();
      final conditionValue = ((ach['conditionValue'] as num?)?.toInt()) ?? 1;
      final name = (ach['name'] ?? 'Achievement').toString();
      final icon = (ach['icon'] ?? '').toString();
      bool met = false;
      String subtitle = '';
      if (conditionType == 'station_count') {
        met = stations >= conditionValue;
        subtitle = '$conditionValue allomast latogatal meg!';
      } else if (conditionType == 'event_count') {
        met = events >= conditionValue;
        subtitle = '$conditionValue esemeryen reszt vettel!';
      } else if (conditionType == 'qr_count') {
        met = (stations + events) >= conditionValue;
        subtitle = 'Beolvastal $conditionValue QR-kodot!';
      } else if (conditionType == 'points_threshold') {
        met = points >= conditionValue;
        subtitle = 'Elerte a $conditionValue pontot!';
      } else if (conditionType == 'trip_complete') {
        met = _completedTripIds.length >= conditionValue;
        subtitle = '$conditionValue turat teljesitett!';
      } else if (conditionType == 'top_n') {
        try {
          final snap = await _firestore
              .collection('user_progress')
              .orderBy('totalPoints', descending: true)
              .limit(conditionValue)
              .get();
          met = snap.docs.any((d) => d.id == uid);
          subtitle = 'Bekerultel a top $conditionValue-be!';
        } catch (_) {}
      }
      if (met) {
        newlyUnlocked.add({'id': id, 'title': '$icon $name', 'subtitle': subtitle});
      }
    }
    if (newlyUnlocked.isEmpty) return;
    final userProgressRef = _firestore.collection('user_progress').doc(uid);
    for (final ach in newlyUnlocked) {
      _unlockedAchievementIds.add(ach['id']!);
      await userProgressRef
          .collection('unlocked_achievements')
          .doc(ach['id'])
          .set({'unlockedAt': FieldValue.serverTimestamp(), 'name': ach['title']});
    }
    final first = newlyUnlocked.first;
    _showAchievement(first['title']!, first['subtitle']!);
    await userProgressRef.set({
      'pendingAchievementBanner': {
        'title': first['title'],
        'subtitle': first['subtitle'],
        'createdAt': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));
  }

  void _showAchievement(String title, String subtitle) {
    _achievementTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _achievementTitle = title;
      _achievementSubtitle = subtitle;
      _showAchievementOverlay = true;
    });
    _achievementTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _showAchievementOverlay = false);
    });
  }
  String _formatDate(DateTime? date) {
    if (date == null) return 'Ismeretlen idopont';
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final h = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_totalPoints / 140).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('QR-kod beolvasas'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Chip(
              avatar: const Icon(Icons.star, color: Colors.amber),
              label: Text('$_totalPoints pont'),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _initData, child: const Text('Ujraprobalas')),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    Column(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Stack(
                            children: [
                              MobileScanner(
                                controller: _scannerController,
                                onDetect: _onDetect,
                              ),
                              Center(
                                child: Container(
                                  width: 260,
                                  height: 260,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.white, width: 3),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 16,
                                right: 16,
                                bottom: 18,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'Iranyitsd az allomas vagy esemeny QR-kodjat a keretbe',
                                    style: TextStyle(color: Colors.white),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Elorehaladas: ${(progress * 100).toStringAsFixed(0)}% (cel: 140 pont)',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 10,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Beolvasasi elozmenyek', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    Text('${_scanHistory.length} db'),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: _scanHistory.isEmpty
                                      ? const Center(child: Text('Meg nincs beolvasott allomas vagy esemeny.'))
                                      : ListView.builder(
                                          itemCount: _scanHistory.length,
                                          itemBuilder: (context, index) {
                                            final item = _scanHistory[index];
                                            final isEvent = item['type'] == 'event';
                                            return Card(
                                              child: ListTile(
                                                leading: Icon(
                                                  isEvent ? Icons.celebration : Icons.qr_code_2,
                                                  color: isEvent ? Colors.deepOrange : null,
                                                ),
                                                title: Text(item['name'] as String),
                                                subtitle: Text(_formatDate(item['date'] as DateTime?)),
                                                trailing: Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                  children: [
                                                    Text('+${item['points']} pont'),
                                                    Text(
                                                      isEvent ? 'esemeny' : 'allomas',
                                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    AnimatedOpacity(
                      opacity: _showAchievementOverlay ? 1 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: IgnorePointer(
                        ignoring: true,
                        child: Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 22),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF3A0CA3), Color(0xFFF72585)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.pinkAccent.withValues(alpha: 0.35),
                                  blurRadius: 24,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.emoji_events, color: Colors.amberAccent, size: 60),
                                const SizedBox(height: 8),
                                Text(_achievementTitle, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                                const SizedBox(height: 8),
                                Text(_achievementSubtitle, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: _showFeedbackOverlay ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: IgnorePointer(
                        ignoring: true,
                        child: Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 26),
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: _feedbackSuccess
                                  ? const Color(0xFF062B15).withValues(alpha: 0.88)
                                  : const Color(0xFF3A0B0B).withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: _feedbackSuccess
                                    ? Colors.lightGreenAccent.withValues(alpha: 0.45)
                                    : Colors.redAccent.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _feedbackSuccess
                                      ? (_feedbackPoints != null ? Icons.check_circle : Icons.done)
                                      : Icons.block,
                                  color: _feedbackSuccess ? Colors.lightGreenAccent : Colors.redAccent,
                                  size: 54,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _feedbackTitle,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _feedbackSubtitle,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                if (_feedbackPoints != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    '+$_feedbackPoints pont',
                                    style: const TextStyle(
                                      color: Colors.amber,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}




class _UnlockSheet extends StatelessWidget {
  final Map<String, dynamic> target;
  const _UnlockSheet({required this.target});

  @override
  Widget build(BuildContext context) {
    final name = (target['name'] ?? '') as String;
    final pts = target['points'] as int? ?? 0;
    final desc = (target['description'] ?? '') as String;
    final funFact = (target['funFact'] ?? '') as String;
    final unlockContent = (target['unlockContent'] ?? '') as String;
    final extraInfo = (target['extraInfo'] ?? '') as String;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 2),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF4f46e5), Color(0xFF7c3aed)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  const Text('\u{1F513}', style: TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Feloldott tartalom!',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '+$pts pont',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: sc,
                padding: const EdgeInsets.all(20),
                children: [
                  if (desc.isNotEmpty) ...[
                    const Text(
                      '\u{1F4D6} Le\u00EDr\u00E1s',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF374151),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      desc,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF4b5563),
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (funFact.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFeff6ff),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF93c5fd)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('\u{1F4A1}', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '\u00C9rdekess\u00E9g',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1d4ed8),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  funFact,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF1e40af),
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (unlockContent.isNotEmpty) ...[
                    const Text(
                      '\u{1F3DB} R\u00E9szletes t\u00F6rt\u00E9net',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF374151),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      unlockContent,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF4b5563),
                        height: 1.7,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (extraInfo.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFf0fdf4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF86efac)),
                      ),
                      child: Row(
                        children: [
                          const Text('\u2139\uFE0F', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              extraInfo,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF166534),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4f46e5),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Bez\u00E1r\u00E1s'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}



