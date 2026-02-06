import 'package:flutter/material.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  bool _isScanned = false;
  int _currentPoints = 0;
  int _totalPoints = 0;

  final List<Map<String, dynamic>> _scannedLocations = [
    {
      'name': 'Nagyvázsony Kastély',
      'points': 15,
      'date': '2026-02-06',
    },
    {
      'name': 'Vár Étterem',
      'points': 10,
      'date': '2026-02-05',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final totalScanned = _scannedLocations.fold<int>(0, (sum, item) => sum + (item['points'] as int));

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
      body: _isScanned
          ? _buildScannedState(totalScanned)
          : _buildScanningState(),
    );
  }

  Widget _buildScanningState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // QR Code Scanner Preview
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blue, width: 3),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.3),
                  blurRadius: 15,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    Icons.qr_code_2,
                    size: 120,
                    color: Colors.blue.withOpacity(0.6),
                  ),
                ),
                // Animated scanning lines
                Positioned(
                  top: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.blue.withOpacity(0),
                          Colors.blue,
                          Colors.blue.withOpacity(0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 40),
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
        const SizedBox(height: 40),
        ElevatedButton.icon(
          onPressed: () => setState(() => _isScanned = true),
          icon: const Icon(Icons.camera_alt),
          label: const Text('Szimuláció: Beolvasás'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
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
    );
  }

  Widget _buildScannedState(int totalScanned) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          // Success Icon
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
            'Nagyvázsony Kastély',
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
                const Text('15 pont', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.amber)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Összesen: $totalScanned pont',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 40),
          // Progress Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Előrehaladás: ${((totalScanned / 140) * 100).toStringAsFixed(0)}%',
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
                onPressed: () => setState(() => _isScanned = false),
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
