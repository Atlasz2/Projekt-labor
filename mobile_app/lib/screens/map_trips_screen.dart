import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapTripsScreen extends StatefulWidget {
  const MapTripsScreen({super.key});

  @override
  State<MapTripsScreen> createState() => _MapTripsScreenState();
}

class _MapTripsScreenState extends State<MapTripsScreen> {
  final Completer<GoogleMapController> _controllerCompleter = Completer<GoogleMapController>();

  static const LatLng _nagyvazsony = LatLng(47.0587, 17.7139);

  List<Map<String, dynamic>> _trips = [];
  List<Map<String, dynamic>> _stations = [];
  String? _selectedTripId;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _safeString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  double? _safeDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  int _safeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  List<String> _safeStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return const [];
  }

  Future<void> _loadData() async {
    try {
      final tripSnap = await FirebaseFirestore.instance.collection('trips').get();
      final stationSnap = await FirebaseFirestore.instance.collection('stations').get();

      final trips = tripSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      final stations = stationSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();

      setState(() {
        _trips = trips;
        _stations = stations;
        _isLoading = false;
      });

      final firstActive = trips.cast<Map<String, dynamic>?>().firstWhere(
            (t) => t?['isActive'] == true,
            orElse: () => trips.isNotEmpty ? trips.first : <String, dynamic>{},
          );
      if (firstActive != null && firstActive.isNotEmpty) {
        _selectTrip(firstActive['id'] as String, animate: false);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Hiba az adatok betöltésekor: $e';
      });
    }
  }

  List<Map<String, dynamic>> _getTripStations(Map<String, dynamic> trip) {
    final tripId = trip['id']?.toString();
    final stationIds = _safeStringList(trip['stationIds']);

    final byTripField = _stations.where((station) => station['tripId'] == tripId).toList();
    if (byTripField.isNotEmpty) {
      byTripField.sort((a, b) => _safeInt(a['orderIndex']).compareTo(_safeInt(b['orderIndex'])));
      return byTripField;
    }

    if (stationIds.isNotEmpty) {
      final indexed = <Map<String, dynamic>>[];
      for (final stationId in stationIds) {
        final match = _stations.cast<Map<String, dynamic>?>().firstWhere(
              (station) => station?['id'] == stationId,
              orElse: () => null,
            );
        if (match != null) indexed.add(match);
      }
      return indexed;
    }

    return const [];
  }

  List<LatLng> _getTripPath(Map<String, dynamic> trip, List<Map<String, dynamic>> tripStations) {
    final rawPolyline = trip['polyline'];
    if (rawPolyline is List && rawPolyline.isNotEmpty) {
      final points = <LatLng>[];
      for (final item in rawPolyline) {
        if (item is Map) {
          final lat = _safeDouble(item['latitude'] ?? item['lat']);
          final lng = _safeDouble(item['longitude'] ?? item['lng']);
          if (lat != null && lng != null) {
            points.add(LatLng(lat, lng));
          }
        }
      }
      if (points.isNotEmpty) return points;
    }

    return tripStations.map((s) {
      final lat = _safeDouble(s['latitude']);
      final lng = _safeDouble(s['longitude']);
      if (lat == null || lng == null) return null;
      return LatLng(lat, lng);
    }).whereType<LatLng>().toList();
  }

  Future<void> _selectTrip(String tripId, {bool animate = true}) async {
    final trip = _trips.cast<Map<String, dynamic>?>().firstWhere(
          (t) => t?['id'] == tripId,
          orElse: () => null,
        );
    if (trip == null) return;

    final tripStations = _getTripStations(trip);
    final routePoints = _getTripPath(trip, tripStations);

    final markers = <Marker>{};
    for (var i = 0; i < tripStations.length; i++) {
      final station = tripStations[i];
      final lat = _safeDouble(station['latitude']);
      final lng = _safeDouble(station['longitude']);
      if (lat == null || lng == null) continue;

      markers.add(
        Marker(
          markerId: MarkerId(station['id'].toString()),
          position: LatLng(lat, lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            i == 0 ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(
            title: _safeString(station['name'], fallback: 'Állomás'),
            snippet: '${_safeInt(station['points'])} pont',
          ),
        ),
      );
    }

    final polylines = <Polyline>{};
    if (routePoints.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          color: const Color(0xFF667EEA),
          width: 5,
          points: routePoints,
        ),
      );
    }

    setState(() {
      _selectedTripId = tripId;
      _markers = markers;
      _polylines = polylines;
    });

    if (!animate || !_controllerCompleter.isCompleted || routePoints.isEmpty) return;
    final ctrl = await _controllerCompleter.future;
    if (routePoints.length == 1) {
      await ctrl.animateCamera(CameraUpdate.newLatLngZoom(routePoints.first, 15));
      return;
    }

    final minLat = routePoints.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    final maxLat = routePoints.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    final minLng = routePoints.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    final maxLng = routePoints.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);

    try {
      await ctrl.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - 0.003, minLng - 0.003),
            northeast: LatLng(maxLat + 0.003, maxLng + 0.003),
          ),
          72,
        ),
      );
    } catch (_) {
      await ctrl.animateCamera(CameraUpdate.newLatLngZoom(routePoints.first, 14));
    }
  }

  Future<void> _goToMyLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Helymeghatározás engedélyezése szükséges.')),
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!_controllerCompleter.isCompleted) return;
      final ctrl = await _controllerCompleter.future;
      await ctrl.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nem sikerült a helymeghatározás: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildMapView(),
      floatingActionButton: FloatingActionButton.small(
        onPressed: _goToMyLocation,
        tooltip: 'Saját helyzet',
        child: const Icon(Icons.my_location),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _loadData();
              },
              child: const Text('Újra'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapView() {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: const CameraPosition(target: _nagyvazsony, zoom: 13),
          markers: _markers,
          polylines: _polylines,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          onMapCreated: (ctrl) async {
            if (!_controllerCompleter.isCompleted) {
              _controllerCompleter.complete(ctrl);
            }
            final selectedId = _selectedTripId;
            if (selectedId != null) {
              await _selectTrip(selectedId, animate: true);
            }
          },
        ),
        _buildTripPanel(),
      ],
    );
  }

  Widget _buildTripPanel() {
    return DraggableScrollableSheet(
      initialChildSize: 0.30,
      minChildSize: 0.12,
      maxChildSize: 0.66,
      snap: true,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.route, color: Color(0xFF667EEA)),
                    const SizedBox(width: 8),
                    const Text(
                      'Túraútvonalak',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text('${_trips.length} túra', style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _trips.isEmpty
                    ? const Center(child: Text('Nincsenek elérhető túrák.'))
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        itemCount: _trips.length,
                        itemBuilder: (_, i) => _buildTripCard(_trips[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTripCard(Map<String, dynamic> trip) {
    final id = trip['id'].toString();
    final isSelected = id == _selectedTripId;
    final tripStations = _getTripStations(trip);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isSelected ? const BorderSide(color: Color(0xFF667EEA), width: 2) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _selectTrip(id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF667EEA) : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.hiking,
                  color: isSelected ? Colors.white : Colors.grey.shade600,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _safeString(trip['name'], fallback: 'Névtelen túra'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _safeString(trip['description']),
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _miniChip(Icons.place_outlined, '${tripStations.length} állomás'),
                        if (_safeString(trip['distance']).isNotEmpty || trip['distance'] is num)
                          _miniChip(Icons.straighten, '${trip['distance']} km'),
                        if (_safeString(trip['duration']).isNotEmpty)
                          _miniChip(Icons.timer_outlined, trip['duration'].toString()),
                      ],
                    ),
                  ],
                ),
              ),
              if (isSelected) const Icon(Icons.check_circle, color: Color(0xFF667EEA)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey.shade500),
        const SizedBox(width: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
      ],
    );
  }
}

