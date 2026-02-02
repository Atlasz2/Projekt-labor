import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/firestore_service.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({Key? key}) : super(key: key);

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  late MobileScannerController controller;
  final FirestoreService _firestoreService = FirestoreService();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    controller = MobileScannerController();
  }

  void _handleDetection(BarcodeCapture barcodes) async {
    if (_isProcessing) return;

    final barcode = barcodes.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    setState(() => _isProcessing = true);

    final qrData = barcode!.rawValue!;

    try {
      // Felvételezzük, hogy a QR kód az állomás azonosítójával rendelkezik
      final station = await _firestoreService.getStationByQRCode(qrData);

      if (station != null) {
        // QR-kód sikeres beolvasása
        await _firestoreService.recordQRScan(qrData);

        if (mounted) {
          Navigator.pop(context, station);
          _showSuccessDialog(station.name);
        }
      } else {
        // Ismeretlen QR-kód
        if (mounted) {
          _showErrorDialog('Ismeretlen QR-kód');
          setState(() => _isProcessing = false);
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Hiba: \');
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showSuccessDialog(String stationName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Siker!'),
        content: Text('Az "\" állomást sikeresen feloldotta!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hiba'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR-kód beolvasása'),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: _handleDetection,
            errorBuilder: (context, error, child) {
              return Center(
                child: Text(
                  'Kamera hiba: \',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            },
          ),
          // QR finder overlay
          Positioned.fill(
            child: CustomPaint(
              painter: QRFinderPainter(),
            ),
          ),
          // Információ panel
          Positioned(
            bottom: 32,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'QR-kódot a kamerába vezess',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Az alkalmazás automatikusan felismeri a kódot',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[300],
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          // Vissza gomb
          Positioned(
            top: 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: () => Navigator.pop(context),
              backgroundColor: Colors.white,
              child: const Icon(Icons.close, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}

class QRFinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // QR-kód keresési mező középpontban
    final qrSize = 250.0;
    final left = (width - qrSize) / 2;
    final top = (height - qrSize) / 2;

    // Félátlátszó háttér
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = Colors.black.withOpacity(0.5),
    );

    // Lyuk a kép közepén
    canvas.drawRect(
      Rect.fromLTWH(left, top, qrSize, qrSize),
      Paint()..color = Colors.transparent,
      // Mode: clear
    );

    // Jelölők a sarkokon
    const cornerLength = 30.0;
    const cornerWidth = 4.0;
    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = cornerWidth
      ..style = PaintingStyle.stroke;

    // Bal felső
    canvas.drawLine(
      Offset(left, top + cornerLength),
      Offset(left, top),
      paint,
    );
    canvas.drawLine(
      Offset(left, top),
      Offset(left + cornerLength, top),
      paint,
    );

    // Jobb felső
    canvas.drawLine(
      Offset(left + qrSize - cornerLength, top),
      Offset(left + qrSize, top),
      paint,
    );
    canvas.drawLine(
      Offset(left + qrSize, top),
      Offset(left + qrSize, top + cornerLength),
      paint,
    );

    // Bal alsó
    canvas.drawLine(
      Offset(left, top + qrSize - cornerLength),
      Offset(left, top + qrSize),
      paint,
    );
    canvas.drawLine(
      Offset(left, top + qrSize),
      Offset(left + cornerLength, top + qrSize),
      paint,
    );

    // Jobb alsó
    canvas.drawLine(
      Offset(left + qrSize, top + qrSize - cornerLength),
      Offset(left + qrSize, top + qrSize),
      paint,
    );
    canvas.drawLine(
      Offset(left + qrSize - cornerLength, top + qrSize),
      Offset(left + qrSize, top + qrSize),
      paint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
