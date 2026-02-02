import 'package:flutter/material.dart';
import '../models/station.dart';
import '../services/firestore_service.dart';

class StationDetailScreen extends StatefulWidget {
  final Station station;

  const StationDetailScreen({
    Key? key,
    required this.station,
  }) : super(key: key);

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  late Stream<List<PointContent>> _contentsStream;

  @override
  void initState() {
    super.initState();
    _contentsStream =
        _firestoreService.watchContentsByStationId(widget.station.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Állomás részletei'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Kép
            if (widget.station.imageUrl.isNotEmpty)
              Image.network(
                widget.station.imageUrl,
                height: 250,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 250,
                    color: Colors.grey[300],
                    child: const Icon(Icons.image_not_supported),
                  );
                },
              ),
            // Tartalom
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cím
                  Text(
                    widget.station.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  // Leírás
                  Text(
                    widget.station.description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  // QR kód
                  if (widget.station.qrCodeIdentifier.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.qr_code, color: Colors.orange[800]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'QR kód: \',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.orange[800],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  // Tartalmak
                  Text(
                    'Tartalmak',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder(
                    stream: _contentsStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }

                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return Center(
                          child: Text(
                            'Nincsenek elérhető tartalmak',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        );
                      }

                      final contents = snapshot.data!;
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: contents.length,
                        itemBuilder: (context, index) {
                          final content = contents[index];
                          return ContentCard(content: content);
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  // QR kód beolvasás gomb
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushNamed(context, '/qr_scanner');
                      },
                      child: const Text('QR kód beolvasása'),
                    ),
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

import 'package:flutter/material.dart';
import '../models/point_content.dart';

class ContentCard extends StatelessWidget {
  final PointContent content;

  const ContentCard({
    Key? key,
    required this.content,
  }) : super(key: key);

  String _getTypeLabel(String type) {
    switch (type) {
      case 'text':
        return 'Szöveg';
      case 'image':
        return 'Kép';
      case 'video':
        return 'Videó';
      case 'audio':
        return 'Hang';
      case 'web':
        return 'Web';
      default:
        return type;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'text':
        return Icons.description;
      case 'image':
        return Icons.image;
      case 'video':
        return Icons.videocam;
      case 'audio':
        return Icons.audio_file;
      case 'web':
        return Icons.language;
      default:
        return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_getTypeIcon(content.type)),
                const SizedBox(width: 8),
                Text(
                  _getTypeLabel(content.type),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              content.title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              content.content,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (content.requiresQR)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'QR-kód szükséges az eléréséhez',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
