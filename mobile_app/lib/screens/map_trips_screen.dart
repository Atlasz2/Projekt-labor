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
  final Completer<GoogleMapController> _controllerCompleter =
      Completer<GoogleMapController>();

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

  Future<void> _loadData() async {
    try {
      final tripSnap =
          await FirebaseFirestore.instance.collection('trips').get();
      final stationSnap =
          await FirebaseFirestore.instance.collection('stations').get();

      final trips = tripSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      final stations =
          stationSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();

      setState(() {
        _trips = trips;
        _stations = stations;
        _isLoading = false;
      });

      final firstActive = trips.firstWhere(
        (t) => t['isActive'] == true,
        orElse: () => trips.isNotEmpty ? trips.first : <String, dynamic>{},
      );
      if (firstActive.isNotEmpty) {
        _selectTrip(firstActive['id'] as String);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Hiba az adatok betöltésekor: $e';
      });
    }
  }

  void _selectTrip(String tripId) {
    setState(() => _selectedTripId = tripId);
    _buildMapOverlays(tripId);
  }

  Future<void> _buildMapOverlays(String tripId) async {
    final tripStations = _stations.where((s) => s['tripId'] == tripId).toList()
      ..sort((a, b) {
        final oa = a['order'] is num ? (a['order'] as num).toInt() : 9999;
        final ob = b['order'] is num ? (b['order'] as num).toInt() : 9999;
        return oa.compareTo(ob);
      });

    final markers = <Marker>{};
    final points = <LatLng>[];

    for (var i = 0; i < tripStations.length; i++) {
      final s = tripStations[i];
      final lat = s['latitude'];
      final lng = s['longitude'];
      if (lat == null || lng == null) continue;

      final pos = LatLng((lat as num).toDouble(), (lng as num).toDouble());
      points.add(pos);

      markers.add(Marker(
        markerId: MarkerId(s['id'] as String),
        position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          i == 0 ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueAzure,
        ),
        infoWindow: InfoWindow(
          title: s['name']?.toString() ?? 'Állomás ${i + 1}',
          snippet: '${s['points'] ?? 0} pont',
        ),
      ));
    }

    final polylines = <Polyline>{};
    if (points.length >= 2) {
      polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        color: const Color(0xFF667EEA),
        width: 4,
        points: points,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      ));
    }

    setState(() {
      _markers = markers;
      _polylines = polylines;
    });

    if (points.isNotEmpty) {
      final ctrl = await _controllerCompleter.future;
      if (points.length == 1) {
        ctrl.animateCamera(CameraUpdate.newLatLngZoom(points.first, 15));
      } else {
        final minLat =
            points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
        final maxLat =
            points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
        final minLng =
            points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
        final maxLng =
            points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
        ctrl.animateCamera(CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - 0.003, minLng - 0.003),
            northeast: LatLng(maxLat + 0.003, maxLng + 0.003),
          ),
          64,
        ));
      }
    }
  }

  Future<void> _goToMyLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
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
      final ctrl = await _controllerCompleter.future;
      ctrl.animateCamera(
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

  String _safeString(dynamic v, {String fallback = ''}) {
    if (v == null) return fallback;
    final s = v.toString().trim();
    return s.isEmpty ? fallback : s;
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
          initialCameraPosition:
              const CameraPosition(target: _nagyvazsony, zoom: 13),
          markers: _markers,
          polylines: _polylines,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          onMapCreated: (ctrl) {
            if (!_controllerCompleter.isCompleted) {
              _controllerCompleter.complete(ctrl);
            }
          },
        ),
        _buildTripPanel(),
      ],
    );
  }

  Widget _buildTripPanel() {
    return DraggableScrollableSheet(
      initialChildSize: 0.28,
      minChildSize: 0.12,
      maxChildSize: 0.65,
      snap: true,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
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
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text(
                      '${_trips.length} túra',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (_trips.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nincsenek elérhető túrák.',
                      style: TextStyle(color: Colors.grey)),
                )
              else
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
    final id = trip['id'] as String;
    final isSelected = id == _selectedTripId;
    final name = _safeString(trip['name'], fallback: 'Névtelen túra');
    final desc = _safeString(trip['description'], fallback: '');
    final stationCount =
        _stations.where((s) => s['tripId'] == id).length;
    final distance = trip['distance'];
    final duration = trip['duration'];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isSelected
            ? const BorderSide(color: Color(0xFF667EEA), width: 2)
            : BorderSide.none,
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
                  color: isSelected
                      ? const Color(0xFF667EEA)
                      : Colors.grey.shade200,
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
                      name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (desc.isNotEmpty)
                      Text(
                        desc,
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: [
                        _chip(Icons.place_outlined, '$stationCount állomás'),
                        if (distance != null)
                          _chip(Icons.straighten,
                              '${(distance as num).toStringAsFixed(1)} km'),
                        if (duration != null)
                          _chip(Icons.timer_outlined,
                              _fmtDuration(duration)),
                      ],
                    ),
                  ],
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check_circle,
                    color: Color(0xFF667EEA), size: 20),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey.shade500),
        const SizedBox(width: 2),
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }

  String _fmtDuration(dynamic value) {
    if (value is num) {
      final mins = value.round();
      final h = mins ~/ 60;
      final m = mins % 60;
      return h == 0 ? '$mins perc' : '$h ó $m perc';
    }
    return value.toString();
  }
}