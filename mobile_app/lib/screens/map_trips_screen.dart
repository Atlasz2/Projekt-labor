import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MapTripsScreen extends StatelessWidget {
  const MapTripsScreen({super.key});

  final List<Map<String, dynamic>> _dummyTrips = const [
    {'name': 'Nagyvázsony Kastély Túra', 'distance': '5.2 km', 'difficulty': '⭐⭐☆', 'duration': '2h', 'rating': 4.8, 'color': 0xFF667EEA},
    {'name': 'Vínás völgy Túra', 'distance': '8.5 km', 'difficulty': '⭐⭐⭐', 'duration': '3h 30min', 'rating': 4.5, 'color': 0xFF4CAF50},
    {'name': 'Történeti Nagyvázsony', 'distance': '3.2 km', 'difficulty': '⭐☆☆', 'duration': '1h 30min', 'rating': 4.9, 'color': 0xFFFF9800},
  ];

  Future<List<Map<String, dynamic>>> _loadTrips() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('trips').get();
      if (snapshot.docs.isEmpty) {
        return _dummyTrips;
      }
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'name': data['name'] ?? 'Unknown',
          'distance': data['distance'] ?? '0 km',
          'difficulty': data['difficulty'] ?? '⭐',
          'duration': data['duration'] ?? '0h',
          'rating': (data['rating'] ?? 0.0).toDouble(),
          'description': data['description'] ?? 'No description',
          'color': int.parse(data['color'] ?? '0xFF667EEA'),
        };
      }).toList();
    } catch (e) {
      print('Error loading trips: $e');
      return _dummyTrips;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Térkép & Túrák')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadTrips(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Hiba: ${snapshot.error}'));
          }
          final trips = snapshot.data ?? _dummyTrips;
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: trips.length,
            itemBuilder: (context, index) {
              final trip = trips[index];
              final color = Color(trip['color'] as int);
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 160,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Icon(Icons.map, size: 60, color: color),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(trip['name'] as String, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${trip['distance']} • ${trip['duration']}'),
                          Row(children: [Icon(Icons.star, size: 16, color: Colors.amberAccent), const SizedBox(width: 4), Text('${trip['rating']}')]),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Nehézség: ${trip['difficulty']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(trip['name'] as String),
                                content: Text(trip['description'] as String),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Bezárás')),
                                ],
                              ),
                            );
                          },
                          child: const Text('Túra részletei'),
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
    );
  }
}
