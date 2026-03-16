import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class MapTripsScreen extends StatelessWidget {
  const MapTripsScreen({super.key});

  String _safeString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Térkép és túrák')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('trips').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Hiba a túrák betöltésekor: ${snapshot.error}'),
              ),
            );
          }

          final trips = snapshot.data?.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {
              'id': doc.id,
              'name': _safeString(data['name']),
              'description': _safeString(data['description']),
              'isActive': data['isActive'] == true,
            };
          }).toList() ?? [];

          if (trips.isEmpty) {
            return const Center(
              child: Text('Még nincs feltöltött túra.'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: trips.length,
            itemBuilder: (context, index) {
              final trip = trips[index];
              final isActive = trip['isActive'] as bool;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              trip['name'] as String,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(isActive ? 'Aktív' : 'Inaktív'),
                            backgroundColor:
                                isActive ? Colors.green.shade100 : Colors.grey.shade200,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        (trip['description'] as String).isEmpty
                            ? 'Nincs leírás megadva ehhez a túrához.'
                            : trip['description'] as String,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                showDialog<void>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(trip['name'] as String),
                                    content: Text(
                                      (trip['description'] as String).isEmpty
                                          ? 'Nincs további leírás.'
                                          : trip['description'] as String,
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Bezárás'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              icon: const Icon(Icons.info_outline),
                              label: const Text('Részletek'),
                            ),
                          ),
                        ],
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
