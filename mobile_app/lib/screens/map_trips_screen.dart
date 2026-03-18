import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapTripsScreen extends StatefulWidget {
  const MapTripsScreen({super.key});

  @override
  State<MapTripsScreen> createState() => _MapTripsScreenState();
}

class _MapTripsScreenState extends State<MapTripsScreen> with SingleTickerProviderStateMixin {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  late TabController _tabs;
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _trips = [];
  List<Map<String, dynamic>> _stations = [];
  Set<String> _completedIds = {};
  String? _selectedTripId;

  GoogleMapController? _mapController;
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = _auth.currentUser?.uid;
      final results = await Future.wait([
        _firestore.collection('trips').get(),
        _firestore.collection('stations').get(),
        if (uid != null) _firestore.collection('user_progress').doc(uid).get(),
      ]);

      final tripsSnap = results[0] as QuerySnapshot;
      final stationsSnap = results[1] as QuerySnapshot;
      final trips = tripsSnap.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data() as Map}).toList();
      final stations = stationsSnap.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data() as Map}).toList();

      Set<String> completed = {};
      if (uid != null && results.length > 2) {
        final progress = results[2] as DocumentSnapshot;
        if (progress.exists) {
          completed = Set<String>.from((progress.data() as Map)['completedStations'] ?? []);
        }
      }

      if (!mounted) return;
      setState(() {
        _trips = trips;
        _stations = stations;
        _completedIds = completed;
        _selectedTripId = trips.isNotEmpty ? trips.first['id'] as String : null;
        _loading = false;
        _buildMarkers();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _buildMarkers() {
    final visibleStations = _selectedTripId == null
        ? _stations
        : _stations.where((s) => s['tripId'] == _selectedTripId).toList();

    _markers = Set<Marker>.from(
      visibleStations.where((s) => s['latitude'] != null && s['longitude'] != null).map((s) {
        final done = _completedIds.contains(s['id'] as String);
        return Marker(
          markerId: MarkerId(s['id'] as String),
          position: LatLng((s['latitude'] as num).toDouble(), (s['longitude'] as num).toDouble()),
          infoWindow: InfoWindow(title: s['name']?.toString(), snippet: done ? '✅ Teljesítve' : '${s['points'] ?? 10} pont'),
          icon: done
              ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)
              : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Térkép és Túrák'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(icon: Icon(Icons.map), text: 'Térkép'), Tab(icon: Icon(Icons.list), text: 'Túrák')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : TabBarView(
                  controller: _tabs,
                  children: [_buildMapTab(), _buildListTab()],
                ),
    );
  }

  Widget _buildMapTab() {
    final firstStation = _stations.firstWhere(
      (s) => s['tripId'] == _selectedTripId && s['latitude'] != null,
      orElse: () => <String, dynamic>{},
    );
    final center = firstStation.isNotEmpty
        ? LatLng((firstStation['latitude'] as num).toDouble(), (firstStation['longitude'] as num).toDouble())
        : const LatLng(47.06, 17.715);

    return Column(
      children: [
        if (_trips.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: _trips.map((trip) {
                final selected = trip['id'] == _selectedTripId;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(trip['name']?.toString() ?? 'Túra'),
                    selected: selected,
                    onSelected: (_) => setState(() {
                      _selectedTripId = trip['id'] as String;
                      _buildMarkers();
                    }),
                  ),
                );
              }).toList(),
            ),
          ),
        Expanded(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 13),
            markers: _markers,
            onMapCreated: (c) => _mapController = c,
            myLocationButtonEnabled: true,
            myLocationEnabled: true,
          ),
        ),
      ],
    );
  }

  Widget _buildListTab() {
    if (_trips.isEmpty) {
      return const Center(child: Text('Még nincsenek túrák', style: TextStyle(color: Colors.grey)));
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _trips.length,
        itemBuilder: (_, i) {
          final trip = _trips[i];
          final tripStations = _stations.where((s) => s['tripId'] == trip['id']).toList();
          final doneCount = tripStations.where((s) => _completedIds.contains(s['id'] as String)).length;
          final totalPts = tripStations.fold<int>(0, (acc, s) => acc + ((s['points'] as num?)?.toInt() ?? 0));
          final progress = tripStations.isEmpty ? 0.0 : doneCount / tripStations.length;

          return Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                setState(() {
                  _selectedTripId = trip['id'] as String;
                  _buildMarkers();
                  _tabs.animateTo(0);
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF667EEA).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.route, color: Color(0xFF667EEA)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(trip['name']?.toString() ?? 'Túra', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              if (trip['description'] != null)
                                Text(trip['description'].toString(), style: const TextStyle(color: Colors.grey, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        if (progress == 1.0)
                          const Icon(Icons.emoji_events, color: Colors.amber),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _chip(Icons.place, '${tripStations.length} állomás'),
                        const SizedBox(width: 8),
                        _chip(Icons.star, '$totalPts pont'),
                        const Spacer(),
                        Text('$doneCount/${tripStations.length}', style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: progress == 1.0 ? Colors.green : const Color(0xFF667EEA),
                        )),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(progress == 1.0 ? Colors.green : const Color(0xFF667EEA)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ]),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('Nem sikerült betölteni', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _loadAll, child: const Text('Újra próbálás')),
        ],
      ),
    );
  }
}
