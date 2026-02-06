import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  String _selectedCategory = 'Összes';
  final _categories = ['Összes', 'Kulturális', 'Sportok', 'Étkezés', 'Egyéb'];

  void _showEventDetails(BuildContext context, Map<String, dynamic> event) {
    final date = event['date'] as Timestamp?;
    final dateStr = date != null
        ? date.toDate().toString().split('.')[0]
        : 'Dátum nincs';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(event['title'] ?? 'Esemény'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                event['description'] ?? 'Leírás nincs',
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 16),
              _InfoRow('📅', dateStr),
              _InfoRow('📍', event['location'] ?? 'Helyszín nincs'),
              _InfoRow('🏷️', event['category'] ?? '-'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Bezárás'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // KATEGÓRIA SZŰRÉS
        SizedBox(
          height: 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final cat = _categories[index];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(cat),
                  selected: _selectedCategory == cat,
                  onSelected: (_) => setState(() => _selectedCategory = cat),
                ),
              );
            },
          ),
        ),
        // PROGRAMOK LISTÁJA
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('programs')
                .where('isActive', isEqualTo: true)
                .orderBy('date', descending: false)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text('Hiba: ${snapshot.error}'),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text('Nincs elérhető program.'));
              }

              var programs = snapshot.data!.docs;

              // SZŰRÉS
              if (_selectedCategory != 'Összes') {
                programs = programs
                    .where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return (data['category'] ?? '') == _selectedCategory;
                    })
                    .toList();
              }

              if (programs.isEmpty) {
                return Center(
                  child: Text('Nincs program a "$_selectedCategory" kategóriában.'),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: programs.length,
                itemBuilder: (context, index) {
                  final program =
                      programs[index].data() as Map<String, dynamic>;
                  final title = program['title'] ?? 'Program';
                  final date = program['date'] as Timestamp?;
                  final dateStr = date != null
                      ? date.toDate().toString().split('.')[0]
                      : '-';
                  final imageUrl = program['imageUrl'] as String?;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () => _showEventDetails(context, program),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (imageUrl != null)
                            ClipRRect(
                              borderRadius:
                                  const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                              child: Image.network(
                                imageUrl,
                                height: 150,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  height: 150,
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.broken_image),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                _InfoRow('📅', dateStr),
                                _InfoRow(
                                  '🏷️',
                                  program['category'] ?? '-',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String icon;
  final String value;

  const _InfoRow(this.icon, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(icon),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
