import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _selectedCategory = 'Összes';
  
  final List<String> categories = ['Összes', 'Túra', 'Koncert', 'Workshop', 'Fesztivál'];
  
  final List<Map<String, dynamic>> _dummyEvents = [
    {
      'title': 'Tavaszi Várvédelem Fesztivál',
      'date': '2026-03-15',
      'category': 'Fesztivál',
      'description': 'A történelmi várvédelem reenactment-je színes programokkal.'
    },
    {
      'title': 'Történeti Túra - Keleti naplemente',
      'date': '2026-02-22',
      'category': 'Túra',
      'description': 'Vezetett túra a kastély történetéről naplementes kilátásokkal.'
    },
    {
      'title': 'Jazz Koncert a Kastélyban',
      'date': '2026-03-01',
      'category': 'Koncert',
      'description': 'Élő jazz zenei előadás a kastély belső terén.'
    },
    {
      'title': 'Termékkészítés Workshop',
      'date': '2026-02-28',
      'category': 'Workshop',
      'description': 'Tanulj meg tradicionális magyar termékkészítést a helyi mesterek segítségével.'
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rendezvények'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Category Filter
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: categories.map((cat) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(cat),
                  selected: _selectedCategory == cat,
                  onSelected: (_) => setState(() => _selectedCategory = cat),
                ),
              )).toList(),
            ),
          ),
          // Events List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('programs').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Hiba: ${snapshot.error}'),
                      ],
                    ),
                  );
                }

                final allEvents = snapshot.data?.docs.isEmpty ?? true
                    ? _dummyEvents
                    : snapshot.data!.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

                final filteredEvents = _selectedCategory == 'Összes'
                    ? allEvents
                    : allEvents.where((e) => e['category'].toString() == _selectedCategory).toList();

                if (filteredEvents.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.event_busy, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        const Text('Nincsenek rendezvények ebben a kategóriában'),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filteredEvents.length,
                  itemBuilder: (context, index) {
                    final event = filteredEvents[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () => _showEventDetails(context, event),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      event['title'].toString(),
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _getCategoryIcon(event['category'].toString()),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatDate(event['date'].toString()),
                                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getCategoryColor(event['category'].toString()).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      event['category'].toString(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _getCategoryColor(event['category'].toString()),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  ElevatedButton(
                                    onPressed: () => _showEventDetails(context, event),
                                    child: const Text('Részletek'),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: () {},
                                    child: const Text('Érdekel'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showEventDetails(BuildContext context, Map<String, dynamic> event) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(event['title'].toString()),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                height: 150,
                decoration: BoxDecoration(
                  color: _getCategoryColor(event['category'].toString()).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: _getCategoryIcon(event['category'].toString(), size: 80),
                ),
              ),
              const SizedBox(height: 16),
              _detailRow('Dátum:', _formatDate(event['date'].toString())),
              _detailRow('Kategória:', event['category'].toString()),
              const SizedBox(height: 12),
              const Text('Leírás:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(event['description']?.toString() ?? 'Nincs leírás elérhető.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Bezárás')),
          ElevatedButton(onPressed: () {}, child: const Text('Érdekel')),
        ],
      ),
    );
  }

  String _formatDate(String date) {
    try {
      final parsed = DateTime.parse(date);
      return '${parsed.year}. ${parsed.month.toString().padLeft(2, '0')}. ${parsed.day.toString().padLeft(2, '0')}.';
    } catch (e) {
      return date;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Túra':
        return Colors.green;
      case 'Koncert':
        return Colors.purple;
      case 'Workshop':
        return Colors.orange;
      case 'Fesztivál':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget _getCategoryIcon(String category, {double size = 24}) {
    IconData icon;
    switch (category) {
      case 'Túra':
        icon = Icons.hiking;
        break;
      case 'Koncert':
        icon = Icons.music_note;
        break;
      case 'Workshop':
        icon = Icons.school;
        break;
      case 'Fesztivál':
        icon = Icons.celebration;
        break;
      default:
        icon = Icons.event;
    }
    return Icon(icon, size: size, color: _getCategoryColor(category));
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
