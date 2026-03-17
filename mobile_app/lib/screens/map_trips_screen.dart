import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';

class MapTripsScreen extends StatefulWidget {
  const MapTripsScreen({super.key});

  @override
  State<MapTripsScreen> createState() => _MapTripsScreenState();
}

class _MapTripsScreenState extends State<MapTripsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();

  bool _isLoading = true;
  String? _error;

  List<Map<String, dynamic>> _trips = [];
  List<Map<String, dynamic>> _stations = [];
  String? _selectedTripId;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  static const LatLng _center = LatLng(47.0587, 17.7139);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  List<String> _toStringList(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return const [];
  }

  List<LatLng> _parsePolyline(dynamic raw) {
    if (raw is! List) return const [];
    final out = <LatLng>[];
    for (final item in raw) {
      if (item is List && item.length >= 2) {
        final lat = _toDouble(item[0]);
        final lng = _toDouble(item[1]);
        if (lat != null && lng != null) out.add(LatLng(lat, lng));
      } else if (item is Map) {
        final lat = _toDouble(item['lat'] ?? item['latitude']);
        final lng = _toDouble(item['lng'] ?? item['longitude']);
        if (lat != null && lng != null) out.add(LatLng(lat, lng));
      }
    }
    return out;
  }

  Future<void> _loadData() async {
    try {
      final tripSnap = await _firestore.collection('trips').get();
      final stationSnap = await _firestore.collection('stations').get();

      final trips = tripSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      final stations = stationSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();

      setState(() {
        _trips = trips;
        _stations = stations;
        _isLoading = false;
      });

      if (trips.isNotEmpty) {
        _selectTrip(trips.first['id'].toString(), animate: false);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Hiba a térképadatok betöltésekor: $e';
      });
    }
  }

  List<Map<String, dynamic>> _tripStations(Map<String, dynamic> trip) {
    final tripId = trip['id']?.toString() ?? '';
    final stationIds = _toStringList(trip['stationIds']);

    if (stationIds.isNotEmpty) {
      final byId = <Map<String, dynamic>>[];
      for (final id in stationIds) {
        final found = _stations.cast<Map<String, dynamic>?>().firstWhere(
              (s) => s?['id']?.toString() == id,
              orElse: () => null,
            );
        if (found != null) byId.add(found);
      }
      if (byId.isNotEmpty) return byId;
    }

    final byTripField = _stations.where((s) => s['tripId']?.toString() == tripId).toList();
    byTripField.sort((a, b) => (a['orderIndex'] ?? 0).toString().compareTo((b['orderIndex'] ?? 0).toString()));
    return byTripField;
  }

  List<LatLng> _routePoints(Map<String, dynamic> trip, List<Map<String, dynamic>> stations) {
    final poly = _parsePolyline(trip['polyline']);
    if (poly.length >= 2) return poly;

    final byStations = stations
        .map((s) {
          final lat = _toDouble(s['latitude'] ?? s['lat']);
          final lng = _toDouble(s['longitude'] ?? s['lng']);
          if (lat == null || lng == null) return null;
          return LatLng(lat, lng);
        })
        .whereType<LatLng>()
        .toList();

    return byStations;
  }

  Future<void> _selectTrip(String id, {bool animate = true}) async {
    final trip = _trips.cast<Map<String, dynamic>?>().firstWhere(
          (t) => t?['id']?.toString() == id,
          orElse: () => null,
        );
    if (trip == null) return;

    final stations = _tripStations(trip);
    final points = _routePoints(trip, stations);

    final markers = <Marker>{};
    for (final s in stations) {
      final lat = _toDouble(s['latitude'] ?? s['lat']);
      final lng = _toDouble(s['longitude'] ?? s['lng']);
      if (lat == null || lng == null) continue;
      markers.add(
        Marker(
          markerId: MarkerId(s['id'].toString()),
          position: LatLng(lat, lng),
          infoWindow: InfoWindow(
            title: (s['name'] ?? 'Állomás').toString(),
            snippet: '${(s['points'] ?? 0)} pont',
          ),
        ),
      );
    }

    final polylines = <Polyline>{};
    if (points.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('trip-route'),
          points: points,
          width: 6,
          color: const Color(0xFF4F46E5),
        ),
      );
    }

    setState(() {
      _selectedTripId = id;
      _markers = markers;
      _polylines = polylines;
    });

    if (!animate || points.isEmpty || !_controller.isCompleted) return;
    final c = await _controller.future;
    if (points.length == 1) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(points.first, 15));
      return;
    }

    final minLat = points.map((e) => e.latitude).reduce((a, b) => a < b ? a : b);
    final maxLat = points.map((e) => e.latitude).reduce((a, b) => a > b ? a : b);
    final minLng = points.map((e) => e.longitude).reduce((a, b) => a < b ? a : b);
    final maxLng = points.map((e) => e.longitude).reduce((a, b) => a > b ? a : b);

    try {
      await c.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - 0.003, minLng - 0.003),
            northeast: LatLng(maxLat + 0.003, maxLng + 0.003),
          ),
          64,
        ),
      );
    } catch (_) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(points.first, 14));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(body: Center(child: Text(_error!)));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Térkép és túrák')),
      body: Column(
        children: [
          SizedBox(
            height: 320,
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(target: _center, zoom: 13),
              myLocationButtonEnabled: true,
              myLocationEnabled: true,
              markers: _markers,
              polylines: _polylines,
              onMapCreated: (c) {
                if (!_controller.isCompleted) _controller.complete(c);
              },
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _trips.length,
              itemBuilder: (context, i) {
                final t = _trips[i];
                final selected = _selectedTripId == t['id'];
                return Card(
                  color: selected ? const Color(0xFFEFF2FF) : Colors.white,
                  child: ListTile(
                    title: Text((t['name'] ?? 'Névtelen túra').toString()),
                    subtitle: Text('Állomások: ${_tripStations(t).length}'),
                    trailing: const Icon(Icons.route),
                    onTap: () => _selectTrip(t['id'].toString()),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
