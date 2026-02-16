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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  MobileScannerController? _scannerController;
  bool _isProcessing = false;
  bool _isScanned = false;
  List<Map<String, dynamic>> _completedStations = [];

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController();
    _loadCompletedStations();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _loadCompletedStations() async {
    final user = _auth.currentUser;
    if (user == null) {
      print('⚠️ Nincs bejelentkezett felhasználó');
      return;
    }

    try {
      print('📸 Felhasználó állomásainak betöltése: ${user.uid}');
      final snapshot = await _firestore
          .collection('user_progress')
          .doc(user.uid)
          .collection('completed_stations')
          .orderBy('completedAt', descending: true)
          .get();

      if (mounted) {
        setState(() {
          _completedStations = snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              'name': data['stationName'] ?? 'Ismeretlen állomás',
              'points': data['points'] ?? 10,
              'date': _formatDate(data['completedAt']),
            };
          }).toList();
        });
        print('✅ ${_completedStations.length} állomás betöltve');
      }
    } catch (e) {
      print('❌ Hiba az állomások betöltése közben: $e');
    }
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      if (timestamp is Timestamp) {
        final date = timestamp.toDate();
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      }
      return timestamp.toString();
    } catch (e) {
      return 'N/A';
    }
  }

  Future<void> _handleQRCode(String qrCode) async {
    if (_isProcessing) return;
    
    setState(() {
      _isProcessing = true;
    });

    try {
      print('📸 QR kód beolvasva: $qrCode');

      final user = _auth.currentUser;
      if (user == null) {
        _showError('Kérlek jelentkezz be!');
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      // Ellenőrizd, hogy létezik-e ez az állomás
      final stationQuery = await _firestore
          .collection('stations')
          .where('qrCode', isEqualTo: qrCode)
          .limit(1)
          .get();

      if (stationQuery.docs.isEmpty) {
        // Próbáld ID alapján
        final stationDoc = await _firestore
            .collection('stations')
            .doc(qrCode)
            .get();

        if (!stationDoc.exists) {
          _showError('Érvénytelen QR kód!');
          setState(() {
            _isProcessing = false;
          });
          return;
        }
      }

      final station = stationQuery.docs.isNotEmpty
          ? stationQuery.docs.first
          : await _firestore.collection('stations').doc(qrCode).get();

      final stationData = station.data()!;
      final stationId = station.id;
      final stationName = stationData['name'] ?? 'Ismeretlen';
      final points = stationData['points'] ?? 10;

      // Ellenőrizd, hogy már beolvasta-e
      final progressDoc = await _firestore
          .collection('user_progress')
          .doc(user.uid)
          .collection('completed_stations')
          .doc(stationId)
          .get();

      if (progressDoc.exists) {
        _showError('Ezt az állomást már beolvastad!');
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      // Mentsd el az új állomást
      await _firestore
          .collection('user_progress')
          .doc(user.uid)
          .collection('completed_stations')
          .doc(stationId)
          .set({
        'stationId': stationId,
        'stationName': stationName,
        'points': points,
        'completedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Állomás mentve: $stationName (+$points pont)');

      // Frissítsd a felhasználó összpontszámát
      await _firestore.collection('user_progress').doc(user.uid).set({
        'userId': user.uid,
        'email': user.email,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Töltsd újra az állomásokat
      await _loadCompletedStations();

      // Sikeres beolvasás visszajelzés
      if (mounted) {
        _showSuccess('$stationName beolvasva! +$points pont');
        setState(() {
          _isScanned = false; // Vissza a kamera nézethez
        });
      }
    } catch (e) {
      print('❌ Hiba: $e');
      _showError('Hiba történt a beolvasás közben');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  int get totalPoints => _completedStations.length * 10;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Kód Beolvasó'),
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 20),
                    const SizedBox(width: 4),
                    Text(
                      '$totalPoints pont',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Kamera nézet
          Expanded(
            flex: 2,
            child: Stack(
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty && !_isProcessing) {
                      final String? code = barcodes.first.rawValue;
                      if (code != null && code.isNotEmpty) {
                        _handleQRCode(code);
                      }
                    }
                  },
                ),
                // Overlay
                Center(
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                // Utasítás
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _isProcessing
                          ? 'Feldolgozás...'
                          : 'Helyezd a QR kódot a keretbe',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Beolvasott állomások lista
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.grey[100],
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Beolvasott állomások',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_completedStations.length} db',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _completedStations.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.qr_code_scanner, size: 64, color: Colors.grey),
                                SizedBox(height: 16),
                                Text(
                                  'Még nincs beolvasott állomás',
                                  style: TextStyle(fontSize: 16, color: Colors.grey),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Olvasd be az első QR kódot!',
                                  style: TextStyle(fontSize: 14, color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _completedStations.length,
                            itemBuilder: (context, index) {
                              final station = _completedStations[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.green,
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    station['name'] as String,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(station['date'] as String),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.star, color: Colors.amber, size: 20),
                                      const SizedBox(width: 4),
                                      Text(
                                        '+${station['points']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
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
          ),
        ],
      ),
    );
  }
}
