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

  bool _isLoading = true;
  bool _isProcessing = false;
  String? _error;
  int _totalPoints = 0;

  String? _lastCode;
  DateTime _lastScanAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _scanCooldown = Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
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
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final userData = userDoc.data() ?? {};

    await _firestore.collection('user_progress').doc(user.uid).set({
      'name': userData['displayName'] ?? userData['name'] ?? 'Felhasználó',
      'email': user.email ?? userData['email'] ?? '',
      'completedStations': userData['visitedStations'] ?? <String>[],
      'totalPoints': userData['points'] ?? 0,
      'currentTrip': 'Nincs túra',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _loadProgress(String userId) async {
    final progressDoc = await _firestore.collection('user_progress').doc(userId).get();
    final progressData = progressDoc.data() ?? {};

    final completed = (progressData['completedStations'] as List?)
            ?.map((item) => item.toString())
            .toSet() ??
        <String>{};

    final historySnapshot = await _firestore
        .collection('user_progress')
        .doc(userId)
        .collection('completed_stations')
        .get();

    final history = historySnapshot.docs.map((doc) {
      final data = doc.data();
      final scannedAt = data['scannedAt'];
      DateTime? date;
      if (scannedAt is Timestamp) {
        date = scannedAt.toDate();
      }

      return {
        'stationId': doc.id,
        'name': (data['stationName'] ?? 'Ismeretlen állomás').toString(),
        'points': (data['points'] ?? 0) is int ? data['points'] as int : int.tryParse('${data['points']}') ?? 0,
        'date': date,
      };
    }).toList();

    history.sort((a, b) {
      final ad = a['date'] as DateTime?;
      final bd = b['date'] as DateTime?;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });

    final totalPoints = (progressData['totalPoints'] ?? 0) is int
        ? progressData['totalPoints'] as int
        : int.tryParse('${progressData['totalPoints']}') ?? 0;

    setState(() {
      _completedStationIds
        ..clear()
        ..addAll(completed);
      _scanHistory
        ..clear()
        ..addAll(history);
      _totalPoints = totalPoints;
    });
  }

  Future<Map<String, dynamic>?> _findStationByCode(String code) async {
    final normalized = code.trim();

    final qrQuery = await _firestore
        .collection('stations')
        .where('qrCode', isEqualTo: normalized)
        .limit(1)
        .get();

    if (qrQuery.docs.isNotEmpty) {
      final doc = qrQuery.docs.first;
      final data = doc.data();
      return {
        'id': doc.id,
        'name': (data['name'] ?? 'Ismeretlen állomás').toString(),
        'points': (data['points'] ?? 10) is int ? data['points'] as int : int.tryParse('${data['points']}') ?? 10,
      };
    }

    final directDoc = await _firestore.collection('stations').doc(normalized).get();
    if (directDoc.exists) {
      final data = directDoc.data() ?? {};
      return {
        'id': directDoc.id,
        'name': (data['name'] ?? 'Ismeretlen állomás').toString(),
        'points': (data['points'] ?? 10) is int ? data['points'] as int : int.tryParse('${data['points']}') ?? 10,
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
      final station = await _findStationByCode(code);
      if (station == null) {
        _showSnack('Ismeretlen QR-kód.');
        return;
      }

      final stationId = station['id'] as String;
      final stationName = station['name'] as String;
      final points = station['points'] as int;

      if (_completedStationIds.contains(stationId)) {
        _showSnack('Ez az állomás már be lett olvasva.');
        return;
      }

      final userProgressRef = _firestore.collection('user_progress').doc(user.uid);
      final completedStationRef = userProgressRef.collection('completed_stations').doc(stationId);

      final batch = _firestore.batch();
      batch.set(userProgressRef, {
        'completedStations': FieldValue.arrayUnion([stationId]),
        'totalPoints': FieldValue.increment(points),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.set(completedStationRef, {
        'stationId': stationId,
        'stationName': stationName,
        'points': points,
        'scannedCode': code,
        'scannedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      setState(() {
        _completedStationIds.add(stationId);
        _totalPoints += points;
        _scanHistory.insert(0, {
          'stationId': stationId,
          'name': stationName,
          'points': points,
          'date': DateTime.now(),
        });
      });

      _showSnack('Sikeres beolvasás: $stationName (+$points pont)');
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
              : Column(
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
                                _isProcessing ? 'Feldolgozás...' : 'Irányítsd a QR-kódot a keretbe',
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
                                  ? const Center(child: Text('Még nincs beolvasott állomás.'))
                                  : ListView.builder(
                                      itemCount: _scanHistory.length,
                                      itemBuilder: (context, index) {
                                        final item = _scanHistory[index];
                                        return Card(
                                          child: ListTile(
                                            leading: const Icon(Icons.qr_code_2),
                                            title: Text(item['name'] as String),
                                            subtitle: Text(_formatDate(item['date'] as DateTime?)),
                                            trailing: Text('+${item['points']} pont'),
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
    );
  }
}
