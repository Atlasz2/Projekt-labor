import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/offline_image.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const List<Color> _accentColors = [
    Color(0xFF667EEA),
    Color(0xFF764BA2),
    Color(0xFFFF6B6B),
    Color(0xFF48CAE4),
    Color(0xFF52B788),
    Color(0xFFE07A5F),
  ];

  String _safeString(dynamic v, {String fallback = ''}) {
    if (v == null) return fallback;
    if (v is String) return v.isEmpty ? fallback : v;
    return v.toString().trim().isEmpty ? fallback : v.toString().trim();
  }

  List<String> _photoUrls(Map<String, dynamic> data) {
    final photos = data['photos'];
    if (photos is List && photos.isNotEmpty) {
      return photos
          .map((entry) {
            if (entry is String) return entry;
            if (entry is Map && entry['url'] != null) {
              return entry['url'].toString();
            }
            return '';
          })
          .where((url) => url.isNotEmpty)
          .cast<String>()
          .toList();
    }
    final photoUrls = data['photoUrls'];
    if (photoUrls is List && photoUrls.isNotEmpty) {
      return photoUrls.map((entry) => entry.toString()).toList();
    }
    final single = _safeString(data['imageUrl']);
    return single.isEmpty ? <String>[] : <String>[single];
  }

  DateTime _sortDateKey(dynamic raw) {
    final s = _safeString(raw);
    if (s.isEmpty) return DateTime(9999);
    return DateTime.tryParse(s) ?? DateTime(9999);
  }

  void _openImageViewer(BuildContext context, List<String> photos, int initialIndex) {
    if (photos.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            PageView.builder(
              controller: PageController(initialPage: initialIndex),
              itemCount: photos.length,
              itemBuilder: (_, index) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: OfflineImage.network(
                    photos[index],
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 18,
              right: 18,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gallery(BuildContext context, List<String> photos, {double height = 180}) {
    if (photos.isEmpty) {
      return Container(
        height: height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
          ),
        ),
        child: const Center(
          child: Icon(Icons.event, size: 64, color: Colors.white38),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: PageView.builder(
        itemCount: photos.length,
        itemBuilder: (_, index) => GestureDetector(
          onTap: () => _openImageViewer(context, photos, index),
          child: Stack(
            fit: StackFit.expand,
            children: [
              OfflineImage.network(
                photos[index],
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: const Color(0xFFE5E7EB),
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context, Map<String, dynamic> event, Color accent) {
    final photos = _photoUrls(event);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.94,
          expand: false,
          builder: (ctx, scroll) {
            return SingleChildScrollView(
              controller: scroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _gallery(context, photos, height: 220),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _safeString(event['title'], fallback: 'Esemeny'),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.calendar_today_outlined, size: 18, color: accent),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_safeString(event['date'], fallback: 'Ismeretlen datum'))),
                          ],
                        ),
                        if (_safeString(event['location']).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined, size: 18, color: accent),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_safeString(event['location']))),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          _safeString(event['description'], fallback: 'Nincs tovabbi leiras.'),
                          style: TextStyle(color: Colors.grey.shade700, height: 1.55),
                        ),
                        const SizedBox(height: 12),
                        Text('${photos.length} foto kapcsolodik ehhez a rendezvenyhez.', style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('events').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Hiba: ${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];
          final events = docs.asMap().entries.map((entry) {
            final data = entry.value.data() as Map<String, dynamic>;
            return {
              'id': entry.value.id,
              'index': entry.key,
              'title': _safeString(data['name'], fallback: 'Esemeny'),
              'description': _safeString(data['description']),
              'date': data['date'],
              'location': _safeString(data['location']),
              'photos': data['photos'],
              'photoUrls': data['photoUrls'],
              'imageUrl': _safeString(data['imageUrl']),
            };
          }).toList();

          events.sort((a, b) => _sortDateKey(a['date']).compareTo(_sortDateKey(b['date'])));

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 140,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: const Text('Rendezvenyek', style: TextStyle(color: Colors.white)),
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.celebration, size: 44, color: Colors.white54),
                          const SizedBox(height: 6),
                          Text('${events.length} esemeny', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (events.isEmpty)
                const SliverFillRemaining(child: Center(child: Text('Jelenleg nincsenek rendezvenyek.')))
              else
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList.builder(
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      final accent = _accentColors[index % _accentColors.length];
                      final photos = _photoUrls(event);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _showDetails(context, event, accent),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _gallery(context, photos, height: 190),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_safeString(event['title'], fallback: 'Esemeny'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(Icons.calendar_today_outlined, size: 16, color: accent),
                                          const SizedBox(width: 8),
                                          Text(_safeString(event['date'], fallback: 'Ismeretlen datum')),
                                        ],
                                      ),
                                      if (_safeString(event['location']).isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Icon(Icons.location_on_outlined, size: 16, color: accent),
                                            const SizedBox(width: 8),
                                            Expanded(child: Text(_safeString(event['location']))),
                                          ],
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      Text(
                                        _safeString(event['description'], fallback: 'Erintsd meg a reszletekhez.'),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: Colors.grey.shade700, height: 1.45),
                                      ),
                                      const SizedBox(height: 10),
                                      Text('${photos.length} foto', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

