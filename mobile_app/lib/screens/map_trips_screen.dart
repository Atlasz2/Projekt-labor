import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class MapTripsScreen extends StatelessWidget {
  const MapTripsScreen({super.key});

  String _safeString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _formatDistance(dynamic value) {
    if (value == null) return 'N/A';
    if (value is num) return '${value.toStringAsFixed(1)} km';
    return _safeString(value, fallback: 'N/A');
  }

  String _formatDuration(dynamic value) {
    if (value == null) return 'N/A';
    if (value is num) {
      final minutes = value.round();
      final hours = minutes ~/ 60;
      final rest = minutes % 60;
      if (hours == 0) return '$minutes perc';
      return '$hours ó $rest perc';
    }
    return _safeString(value, fallback: 'N/A');
  }

  Future<void> _showTripDetails(
    BuildContext context,
    Map<String, dynamic> trip,
    List<Map<String, dynamic>> stations,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip['name'] as String,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  trip['description'] as String,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetaChip(icon: Icons.route, label: _formatDistance(trip['distanceKm'] ?? trip['distance'])),
                    _MetaChip(icon: Icons.schedule, label: _formatDuration(trip['durationMinutes'] ?? trip['duration'])),
                    _MetaChip(icon: Icons.place, label: '${stations.length} állomás'),
                    _MetaChip(
                      icon: Icons.flag,
                      label: trip['isActive'] == true ? 'Aktív' : 'Inaktív',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Állomások',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (stations.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('Ehhez a túrához még nincsenek állomások rendelve.'),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: stations.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final station = stations[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: Colors.indigo.withValues(alpha: 0.12),
                            child: Text('${index + 1}'),
                          ),
                          title: Text(_safeString(station['name'], fallback: 'Ismeretlen állomás')),
                          subtitle: Text(
                            _safeString(station['description'], fallback: 'Nincs leírás'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text('${station['points'] ?? 0} pont'),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Térkép és túrák')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('trips').snapshots(),
        builder: (context, tripSnapshot) {
          if (tripSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (tripSnapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Hiba a túrák betöltésekor: ${tripSnapshot.error}'),
              ),
            );
          }

          final tripDocs = tripSnapshot.data?.docs ?? [];
          if (tripDocs.isEmpty) {
            return const Center(child: Text('Még nincs feltöltött túra.'));
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('stations').snapshots(),
            builder: (context, stationSnapshot) {
              final stationDocs = stationSnapshot.data?.docs ?? [];
              final stationsByTrip = <String, List<Map<String, dynamic>>>{};

              for (final stationDoc in stationDocs) {
                final stationData = stationDoc.data();
                final tripId = _safeString(stationData['tripId']);
                if (tripId.isEmpty) continue;
                stationsByTrip.putIfAbsent(tripId, () => []);
                stationsByTrip[tripId]!.add({
                  'id': stationDoc.id,
                  ...stationData,
                });
              }

              for (final entry in stationsByTrip.entries) {
                entry.value.sort((a, b) {
                  final orderA = a['order'] is num ? (a['order'] as num).toInt() : 9999;
                  final orderB = b['order'] is num ? (b['order'] as num).toInt() : 9999;
                  return orderA.compareTo(orderB);
                });
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: tripDocs.length,
                itemBuilder: (context, index) {
                  final doc = tripDocs[index];
                  final trip = doc.data();
                  final stations = stationsByTrip[doc.id] ?? const [];
                  final isActive = trip['isActive'] == true;
                  final totalTripPoints = stations.fold<int>(
                    0,
                    (total, item) => total + ((item['points'] is num) ? (item['points'] as num).toInt() : 0),
                  );

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 138,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF667EEA).withValues(alpha: 0.18),
                                  (isActive ? const Color(0xFF4CAF50) : const Color(0xFF94A3B8)).withValues(alpha: 0.16),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Center(
                              child: Icon(Icons.map_outlined, size: 56, color: Color(0xFF334155)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _safeString(trip['name'], fallback: 'Névtelen túra'),
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Chip(
                                label: Text(isActive ? 'Aktív' : 'Inaktív'),
                                backgroundColor: isActive ? Colors.green.shade100 : Colors.grey.shade200,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _safeString(trip['description'], fallback: 'Nincs leírás ehhez a túrához.'),
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _MetaChip(icon: Icons.route, label: _formatDistance(trip['distanceKm'] ?? trip['distance'])),
                              _MetaChip(icon: Icons.schedule, label: _formatDuration(trip['durationMinutes'] ?? trip['duration'])),
                              _MetaChip(icon: Icons.place, label: '${stations.length} állomás'),
                              _MetaChip(icon: Icons.star, label: '$totalTripPoints pont'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _showTripDetails(
                                context,
                                {
                                  'id': doc.id,
                                  ...trip,
                                },
                                stations,
                              ),
                              icon: const Icon(Icons.info_outline),
                              label: const Text('Túra részletei'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}
