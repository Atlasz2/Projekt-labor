import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late MobileScannerController controller;
  bool _isScanned = false;
  bool _isProcessing = false;
  String _scannedName = '';
  int _scannedPoints = 0;
  String? _userId;

  List<Map<String, dynamic>> _scannedLocations = [];

  @override
  void initState() {
    super.initState();
    controller = MobileScannerController();
    _signInAnonymously();
  }

  Future<void> _signInAnonymously() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        _userId = currentUser.uid;
        await _loadScannedLocations();
        return;
      }

      final userCredential = await FirebaseAuth.instance.signInAnonymously();
      _userId = userCredential.user?.uid;
      await _loadScannedLocations();
    } catch (e) {
      print('Error signing in: $e');
    }
  }

  Future<void> _loadScannedLocations() async {
    if (_userId == null) {
      return;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('scanned_qr_codes')
          .where('userId', isEqualTo: _userId)
          .orderBy('timestamp', descending: true)
          .get();

      setState(() {
        _scannedLocations = snapshot.docs.map((doc) {
          return {
            'name': doc['name'] ?? 'Unknown',
            'points': doc['points'] ?? 0,
            'date': (doc['timestamp'] as dynamic)?.toDate().toString().split(' ')[0] ?? 'Unknown',
          };
        }).toList();
      });
    } catch (e) {
      print('Error loading scanned locations: $e');
    }
  }

  Future<void> _handleQRCode(String qrValue) async {
    if (_isProcessing || _isScanned) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('stations')
          .where('qrCode', isEqualTo: qrValue)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ismeretlen QR-kód!'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final doc = snapshot.docs.first;
      final data = doc.data();
      final name = data['name'] ?? 'Ismeretlen állomás';
      final pointsRaw = data['points'];
      final points = pointsRaw is num ? pointsRaw.toInt() : 10;

      if (_userId == null) {
        await _signInAnonymously();
        if (_userId == null) {
          return;
        }
      }

      final duplicateSnapshot = await FirebaseFirestore.instance
          .collection('scanned_qr_codes')
          .where('userId', isEqualTo: _userId)
          .where('stationId', isEqualTo: doc.id)
          .limit(1)
          .get();

      if (duplicateSnapshot.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ezt az allomast mar beolvastad.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      setState(() {
        _isScanned = true;
        _scannedName = name;
        _scannedPoints = points;
      });

      await controller.stop();

      try {
        await FirebaseFirestore.instance.collection('scanned_qr_codes').add({
          'userId': _userId,
          'qrCode': qrValue,
          'stationId': doc.id,
          'name': name,
          'points': points,
          'timestamp': FieldValue.serverTimestamp(),
        });

        // Update user points
        if (_userId != null) {
          final userDocRef = FirebaseFirestore.instance
              .collection('users')
              .doc(_userId);
          await userDocRef.set({
            'userId': _userId,
            'points': FieldValue.increment(points),
            'visitedStations': FieldValue.increment(1),
            'lastScanAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        await _loadScannedLocations();
      } catch (e) {
        print('Error saving to Firestore: $e');
      }
    } catch (e) {
      print('Error looking up station: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  int getTotalPoints() {
    return _scannedLocations.fold<int>(0, (sum, item) => sum + (item['points'] as int));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalScanned = getTotalPoints();

    return Scaffold(
      appBar: AppBar(
        title: const Text('QR-kód Beolvasás'),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 20),
                    const SizedBox(width: 4),
                    Text('$totalScanned pont'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isScanned ? _buildScannedState(totalScanned) : _buildScanningState(),
    );
  }

  Widget _buildScanningState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blue, width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
            margin: const EdgeInsets.all(20),
            child: MobileScanner(
              controller: controller,
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  if (barcode.rawValue != null) {
                    _handleQRCode(barcode.rawValue!);
                    break;
                  }
                }
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text(
                'QR-kód beolvasásához irányítsd\na kamera felé',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              const Text(
                '140 pont összegyűjtésétől speciális jutalmazott',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              if (_scannedLocations.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () => _showScannedHistory(context),
                  icon: const Icon(Icons.history),
                  label: const Text('Beolvasási előzmények'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[600],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScannedState(int totalScanned) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(50),
            ),
            child: const Center(
              child: Icon(Icons.check_circle, size: 80, color: Color(0xFF4CAF50)),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Fénykép beolvasva!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            _scannedName,
            style: TextStyle(fontSize: 18, color: Colors.grey[700]),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_circle, color: Colors.amber, size: 24),
                const SizedBox(width: 8),
                Text('$_scannedPoints pont', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.amber)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Összesen: $totalScanned pont',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Előrehaladás: $totalScanned / 140 pont (${((totalScanned / 140) * 100).toStringAsFixed(0)}%)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: (totalScanned / 140).clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      totalScanned >= 140 ? Colors.green : Colors.blue,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isScanned = false;
                  });
                  controller.start();
                },
                child: const Text('Újra beolvasni'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => _showScannedHistory(context),
                child: const Text('Előzmények'),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _showScannedHistory(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Beolvasási előzmények', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _scannedLocations.length,
                itemBuilder: (context, index) {
                  final location = _scannedLocations[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  location['name'] as String,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  location['date'] as String,
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.star, size: 16, color: Colors.amber),
                                const SizedBox(width: 4),
                                Text('${location['points']}'),
                              ],
                            ),
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
    );
  }
}








