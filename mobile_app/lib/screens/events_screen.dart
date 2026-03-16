import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
    if (v is Map && v.containsKey('seconds')) return fallback;
    return v.toString().trim().isEmpty ? fallback : v.toString().trim();
  }

  Map<String, String> _parseDate(dynamic raw) {
    final s = _safeString(raw);
    if (s.isEmpty) return {'day': '?', 'month': '?', 'full': 'Ismeretlen dátum'};
    try {
      final parts = s.split('-');
      if (parts.length >= 3) {
        final months = [
          '', 'jan', 'febr', 'márc', 'ápr', 'máj', 'jún',
          'júl', 'aug', 'szept', 'okt', 'nov', 'dec'
        ];
        final m = int.tryParse(parts[1]) ?? 0;
        return {
          'day': parts[2].padLeft(2, '0'),
          'month': m > 0 && m <= 12 ? months[m] : parts[1],
          'full': s,
        };
      }
    } catch (_) {}
    return {'day': '?', 'month': '?', 'full': s};
  }

  void _showDetails(BuildContext context, Map<String, dynamic> event, Color accent) {
    final dateInfo = _parseDate(event['date']);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (ctx, scroll) {
            final imageUrl = _safeString(event['imageUrl']);
            return SingleChildScrollView(
              controller: scroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (imageUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20)),
                      child: Image.network(
                        imageUrl,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, st) => _imagePlaceholder(accent, 180),
                      ),
                    )
                  else
                    _imagePlaceholder(accent, 140),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _safeString(event['title'], fallback: 'Esemény'),
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _infoRow(Icons.calendar_today_outlined, accent,
                            dateInfo['full']!),
                        const SizedBox(height: 8),
                        if (_safeString(event['location']).isNotEmpty)
                          _infoRow(Icons.location_on_outlined, accent,
                              _safeString(event['location'])),
                        const SizedBox(height: 16),
                        if (_safeString(event['description']).isNotEmpty) ...[
                          const Text('Leírás',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 6),
                          Text(
                            _safeString(event['description']),
                            style: TextStyle(
                                color: Colors.grey.shade700, height: 1.5),
                          ),
                        ],
                        const SizedBox(height: 24),
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

  Widget _infoRow(IconData icon, Color color, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text, style: TextStyle(color: Colors.grey.shade700))),
      ],
    );
  }

  Widget _imagePlaceholder(Color color, double height) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(Icons.event, size: 64, color: Colors.white54),
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
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text('Hiba: ${snapshot.error}'),
                ],
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          final events = docs.asMap().entries.map((entry) {
            final data = entry.value.data() as Map<String, dynamic>;
            return {
              'id': entry.value.id,
              'index': entry.key,
              'title': _safeString(data['name'], fallback: 'Esemény'),
              'description': _safeString(data['description']),
              'date': data['date'],
              'location': _safeString(data['location']),
              'imageUrl': _safeString(data['imageUrl']),
              'category': _safeString(data['category']),
            };
          }).toList();

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 140,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: const Text('Rendezvények',
                      style: TextStyle(color: Colors.white)),
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
                          const Icon(Icons.celebration,
                              size: 44, color: Colors.white54),
                          const SizedBox(height: 6),
                          Text(
                            '${events.length} esemény',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (events.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.event_busy,
                            size: 72, color: Colors.black26),
                        SizedBox(height: 16),
                        Text('Jelenleg nincsenek rendezvények.',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final event = events[i];
                        final accent =
                            _accentColors[i % _accentColors.length];
                        final dateInfo = _parseDate(event['date']);
                        final imageUrl = event['imageUrl'] as String;
                        return _EventCard(
                          event: event,
                          accent: accent,
                          dateInfo: dateInfo,
                          imageUrl: imageUrl,
                          onTap: () => _showDetails(context, event, accent),
                        );
                      },
                      childCount: events.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final Color accent;
  final Map<String, String> dateInfo;
  final String imageUrl;
  final VoidCallback onTap;

  const _EventCard({
    required this.event,
    required this.accent,
    required this.dateInfo,
    required this.imageUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = event['title'] as String;
    final location = event['location'] as String;
    final description = event['description'] as String;
    final category = event['category'] as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl.isNotEmpty)
              Stack(
                children: [
                  Image.network(
                    imageUrl,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, st) => _headerGradient(),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _dateBadge(),
                  ),
                  if (category.isNotEmpty)
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: _categoryChip(category),
                    ),
                ],
              )
            else
              Stack(
                children: [
                  _headerGradient(),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _dateBadge(),
                  ),
                  if (category.isNotEmpty)
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: _categoryChip(category),
                    ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 14, color: accent),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            location,
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: TextStyle(
                          color: Colors.grey.shade700, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: onTap,
                      icon: Icon(Icons.info_outline, size: 16, color: accent),
                      label: Text('Részletek',
                          style: TextStyle(color: accent, fontSize: 13)),
                      style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact),
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

  Widget _headerGradient() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent, accent.withValues(alpha:0.6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.celebration, size: 48, color: Colors.white54),
      ),
    );
  }

  Widget _dateBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha:0.15), blurRadius: 6),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            dateInfo['day']!,
            style: TextStyle(
                color: accent,
                fontWeight: FontWeight.bold,
                fontSize: 18,
                height: 1),
          ),
          Text(
            dateInfo['month']!,
            style: TextStyle(
                color: Colors.grey.shade600, fontSize: 11, height: 1),
          ),
        ],
      ),
    );
  }

  Widget _categoryChip(String cat) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(cat,
          style: const TextStyle(color: Colors.white, fontSize: 11)),
    );
  }
}