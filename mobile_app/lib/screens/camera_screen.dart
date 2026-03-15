import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final MobileScannerController _scannerController = MobileScannerController();

  final List<Map<String, dynamic>> _scannedLocations = [];
  final Set<String> _seenCodes = <String>{};

  bool _isProcessing = false;
  String? _lastCode;
  DateTime _lastScanAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _scanCooldown = Duration(milliseconds: 1500);

  final Map<String, Map<String, dynamic>> _stationMap = {
    'nagyvazsony_kastely': {'name': 'Nagyvázsony Kastély', 'points': 15},
    'var_etterem': {'name': 'Vár Étterem', 'points': 10},
    'kinizsi_var': {'name': 'Kinizsi-vár', 'points': 20},
  };

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  int get _totalScannedPoints =>
      _scannedLocations.fold<int>(0, (sum, item) => sum + (item['points'] as int));

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    if (capture.barcodes.isEmpty) return;

    final rawValue = capture.barcodes.first.rawValue?.trim();
    if (rawValue == null || rawValue.isEmpty) return;

    final now = DateTime.now();
    final sameAsLast = _lastCode == rawValue;
    if (sameAsLast && now.difference(_lastScanAt) < _scanCooldown) {
      return;
    }

    _lastCode = rawValue;
    _lastScanAt = now;

    _processCode(rawValue);
  }

  Future<void> _processCode(String code) async {
    setState(() => _isProcessing = true);

    try {
      final normalized = code.toLowerCase();
      if (_seenCodes.contains(normalized)) {
        _showSnack('Ez a QR-kód már be lett olvasva.');
        return;
      }

      final stationData = _stationMap[normalized] ?? {
        'name': code,
        'points': 10,
      };

      _seenCodes.add(normalized);
      final date = DateTime.now();
      final formattedDate =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      setState(() {
        _scannedLocations.insert(0, {
          'name': stationData['name'],
          'points': stationData['points'],
          'date': formattedDate,
          'code': code,
        });
      });

      _showSnack('Sikeres beolvasás: ${stationData['name']} (+${stationData['points']} pont)');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_totalScannedPoints / 140).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('QR-kód Beolvasás'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 20),
                    const SizedBox(width: 4),
                    Text('$_totalScannedPoints pont'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
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
                      borderRadius: BorderRadius.circular(20),
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
                          : 'Irányítsd a QR-kódot a keretbe',
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
                    'Előrehaladás: ${(progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Beolvasási előzmények',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text('${_scannedLocations.length} db'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _scannedLocations.isEmpty
                        ? const Center(child: Text('Még nincs beolvasott QR-kód.'))
                        : ListView.builder(
                            itemCount: _scannedLocations.length,
                            itemBuilder: (context, index) {
                              final item = _scannedLocations[index];
                              return Card(
                                child: ListTile(
                                  leading: const Icon(Icons.qr_code_2),
                                  title: Text(item['name'] as String),
                                  subtitle: Text(item['date'] as String),
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
