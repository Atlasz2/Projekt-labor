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

  bool _isLoading = true;
  bool _isProcessing = false;
  bool _showSuccessOverlay = false;
  String _successName = '';
  int _successPoints = 0;
  String _successKind = 'station';
  String? _error;
  int _totalPoints = 0;

  String? _lastCode;
  DateTime _lastScanAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _scanCooldown = Duration(milliseconds: 1500);
  Timer? _successTimer;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _successTimer?.cancel();
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
        _error = 'Nincs bejelentkezett felhasználó.';
      });
      return;
    }

    try {
      await _ensureProgressDoc(user);
      await _loadProgress(user.uid);
      setState(() {
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Hiba a QR adatok betöltésekor: $e';
      });
    }
  }

  Future<void> _ensureProgressDoc(User user) async {
    final progressRef = _firestore.collection('user_progress').doc(user.uid);
    final progressDoc = await progressRef.get();
    if (!progressDoc.exists) {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};
      await progressRef.set({
        'name': userData['displayName'] ?? userData['name'] ?? 'Felhasználó',
        'email': user.email ?? userData['email'] ?? '',
        'completedStations': <String>[],
        'completedEvents': <String>[],
        'totalPoints': 0,
        'currentTrip': 'Nincs túra',
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
        'name': (data['stationName'] ?? 'Ismeretlen állomás').toString(),
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
        'name': (data['eventName'] ?? 'Ismeretlen esemény').toString(),
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
    });
  }

  Future<Map<String, dynamic>?> _findTargetByCode(String code) async {
    final normalized = code.trim();

    final qrStationQuery = await _firestore
        .collection('stations')
        .where('qrCode', isEqualTo: normalized)
        .limit(1)
        .get();
    if (qrStationQuery.docs.isNotEmpty) {
      final doc = qrStationQuery.docs.first;
      final data = doc.data();
      return {
        'kind': 'station',
        'id': doc.id,
        'name': (data['name'] ?? 'Ismeretlen állomás').toString(),
        'points': _safeInt(data['points'], fallback: 10),
      };
    }

    final stationDoc = await _firestore.collection('stations').doc(normalized).get();
    if (stationDoc.exists) {
      final data = stationDoc.data() ?? {};
      return {
        'kind': 'station',
        'id': stationDoc.id,
        'name': (data['name'] ?? 'Ismeretlen állomás').toString(),
        'points': _safeInt(data['points'], fallback: 10),
      };
    }

    final eventQuery = await _firestore
        .collection('events')
        .where('qrCode', isEqualTo: normalized)
        .limit(1)
        .get();
    if (eventQuery.docs.isNotEmpty) {
      final doc = eventQuery.docs.first;
      final data = doc.data();
      return {
        'kind': 'event',
        'id': doc.id,
        'name': (data['name'] ?? 'Ismeretlen esemény').toString(),
        'points': _safeInt(data['points'], fallback: 20),
      };
    }

    return null;
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing || capture.barcodes.isEmpty) return;

    final rawValue = capture.barcodes.first.rawValue?.trim();
    if (rawValue == null || rawValue.isEmpty) return;

    final now = DateTime.now();
    final sameAsLast = _lastCode == rawValue;
    if (sameAsLast && now.difference(_lastScanAt) < _scanCooldown) {
      return;
    }

    _lastCode = rawValue;
    _lastScanAt = now;
    _processScan(rawValue);
  }

  Future<void> _processScan(String code) async {
    final user = _auth.currentUser;
    if (user == null) {
      _showSnack('Nincs bejelentkezett felhasználó.');
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final target = await _findTargetByCode(code);
      if (target == null) {
        _showSnack('Ismeretlen QR-kód.');
        return;
      }

      final id = target['id'] as String;
      final kind = target['kind'] as String;
      final name = target['name'] as String;
      final points = target['points'] as int;
      final userProgressRef = _firestore.collection('user_progress').doc(user.uid);
      final batch = _firestore.batch();

      if (kind == 'station') {
        if (_completedStationIds.contains(id)) {
          _showSnack('Ez az állomás már be lett olvasva.');
          return;
        }
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
        if (_completedEventIds.contains(id)) {
          _showSnack('Ehhez az eseményhez már megszerezted a pecsétet.');
          return;
        }
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

      _showSuccess(name, points, kind);
      _showSnack(kind == 'event'
          ? 'Esemény pecsét megszerezve: $name (+$points pont)'
          : 'Sikeres beolvasás: $name (+$points pont)');
    } catch (e) {
      _showSnack('Hiba a beolvasás mentésekor: $e');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Ismeretlen időpont';
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

  void _showSuccess(String name, int points, String kind) {
    _successTimer?.cancel();
    setState(() {
      _showSuccessOverlay = true;
      _successName = name;
      _successPoints = points;
      _successKind = kind;
    });

    _successTimer = Timer(const Duration(milliseconds: 1300), () {
      if (!mounted) return;
      setState(() => _showSuccessOverlay = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_totalPoints / 140).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('QR-kód beolvasás'),
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
                        FilledButton(onPressed: _initData, child: const Text('Újrapróbálás')),
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
                                  child: Text(
                                    _isProcessing
                                        ? 'Feldolgozás...'
                                        : 'Irányítsd az állomás vagy esemény QR-kódját a keretbe',
                                    style: const TextStyle(color: Colors.white),
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
                                  'Előrehaladás: ${(progress * 100).toStringAsFixed(0)}% (cél: 140 pont)',
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
                                    const Text('Beolvasási előzmények', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    Text('${_scanHistory.length} db'),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: _scanHistory.isEmpty
                                      ? const Center(child: Text('Még nincs beolvasott állomás vagy esemény.'))
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
                                                      isEvent ? 'esemény' : 'állomás',
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
                      opacity: _showSuccessOverlay ? 1 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: IgnorePointer(
                        ignoring: true,
                        child: Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 26),
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.78),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _successKind == 'event' ? Icons.celebration : Icons.check_circle,
                                  color: Colors.lightGreenAccent,
                                  size: 54,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Sikeres beolvasás!',
                                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _successName,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '+$_successPoints pont',
                                  style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 18),
                                ),
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
