import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapTripsScreen extends StatefulWidget {
  const MapTripsScreen({super.key});

  @override
  State<MapTripsScreen> createState() => _MapTripsScreenState();
}

class _MapTripsScreenState extends State<MapTripsScreen>
    {
  static const LatLng _defaultCenter = LatLng(47.06, 17.715);

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _loading = true;
  bool _routeLoading = false;
  String? _error;
  String? _routeStatus;

  List<Map<String, dynamic>> _trips = [];
  List<Map<String, dynamic>> _stations = [];
  Set<String> _completedIds = {};
  String? _selectedTripId;

  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  final Map<String, List<LatLng>> _routeCache = {};
  final Map<String, Map<String, String>> _routeMetrics = {};

  double? _stationLat(Map<String, dynamic> station) {
    final direct = station['latitude'];
    if (direct is num) return direct.toDouble();
    final location = station['location'];
    if (location is Map && location['latitude'] is num) {
      return (location['latitude'] as num).toDouble();
    }
    return null;
  }

  double? _stationLng(Map<String, dynamic> station) {
    final direct = station['longitude'];
    if (direct is num) return direct.toDouble();
    final location = station['location'];
    if (location is Map && location['longitude'] is num) {
      return (location['longitude'] as num).toDouble();
    }
    return null;
  }

  LatLng? _stationPoint(Map<String, dynamic> station) {
    final lat = _stationLat(station);
    final lng = _stationLng(station);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  int _stationOrder(Map<String, dynamic> station) {
    final value = station['orderIndex'];
    if (value is num) return value.toInt();
    return 1 << 20;
  }

  String _stationName(Map<String, dynamic> station) {
    return station['name']?.toString() ?? 'Állomás';
  }

  List<Map<String, dynamic>> _tripStationsFor(String? tripId) {
    final items = (tripId == null
            ? _stations
            : _stations.where((s) => s['tripId'] == tripId).toList())
        .where((s) => _stationPoint(s) != null)
        .toList();

    items.sort((a, b) {
      final orderCompare = _stationOrder(a).compareTo(_stationOrder(b));
      if (orderCompare != 0) return orderCompare;
      return _stationName(a).compareTo(_stationName(b));
    });
    return items;
  }

  String _formatDistance(double meters) {
    if (meters <= 0) return 'N/A';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatDuration(double seconds) {
    if (seconds <= 0) return 'N/A';
    final totalMinutes = (seconds / 60).round().clamp(1, 1 << 20);
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0) {
      return '$hours ó $minutes p';
    }
    return '$totalMinutes p';
  }

  List<LatLng> _decodeStoredRoute(dynamic value) {
    if (value is! List) return const [];
    final points = <LatLng>[];

    for (final item in value) {
      if (item is List && item.length >= 2) {
        final lat = item[0];
        final lng = item[1];
        if (lat is num && lng is num) {
          points.add(LatLng(lat.toDouble(), lng.toDouble()));
        }
        continue;
      }

      if (item is Map) {
        final lat = item['latitude'] ?? item['lat'];
        final lng = item['longitude'] ?? item['lng'] ?? item['lon'];
        if (lat is num && lng is num) {
          points.add(LatLng(lat.toDouble(), lng.toDouble()));
        }
      }
    }

    return points.length >= 2 ? points : const [];
  }

  List<LatLng> _extractTripRoute(Map<String, dynamic> trip) {
    final directCandidates = [
      trip['routeCoordinates'],
      trip['routePoints'],
      trip['path'],
      trip['waypoints'],
    ];

    for (final candidate in directCandidates) {
      final points = _decodeStoredRoute(candidate);
      if (points.length >= 2) return points;
    }

    final geometry = trip['geometry'];
    if (geometry is Map && geometry['coordinates'] is List) {
      final coords = geometry['coordinates'] as List;
      final points = <LatLng>[];
      for (final item in coords) {
        if (item is List && item.length >= 2) {
          final lng = item[0];
          final lat = item[1];
          if (lat is num && lng is num) {
            points.add(LatLng(lat.toDouble(), lng.toDouble()));
          }
        }
      }
      if (points.length >= 2) return points;
    }

    return const [];
  }

  Future<Map<String, dynamic>> _fetchHikingRoute(List<LatLng> waypoints) async {
    if (waypoints.length < 2) {
      return {
        'points': <LatLng>[],
        'distanceLabel': 'N/A',
        'durationLabel': 'N/A',
      };
    }

    final locations = waypoints
        .map((p) => '{"lon": ${p.longitude}, "lat": ${p.latitude}, "type": "break"}')
        .join(',');
    final body =
        '{"locations": [$locations], "costing": "pedestrian", "costing_options": {"pedestrian": {"use_tracks": 1.0, "walking_speed": 3.5}}, "directions_type": "none"}';

    // 1. Valhalla: OSM-alapu erdei/turaoszvenyek
    try {
      final valhallaClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 14);
      try {
        final request = await valhallaClient.postUrl(
          Uri.parse('https://valhalla1.openstreetmap.de/route'),
        );
        request.headers.contentType = ContentType('application', 'json');
        request.write(body);
        final response = await request.close();
        if (response.statusCode == 200) {
          final responseBody = await response.transform(utf8.decoder).join();
          final data = jsonDecode(responseBody);
          if (data is Map && data['trip'] is Map) {
            final trip = data['trip'] as Map;
            final legs = trip['legs'];
            if (legs is List && legs.isNotEmpty) {
              final points = <LatLng>[];
              for (final item in legs) {
                if (item is! Map) continue;
                final shape = item['shape'] as String?;
                if (shape == null || shape.isEmpty) continue;
                _appendRoutePoints(points, _decodePolyline6(shape));
              }
              final summary = trip['summary'] as Map?;
              if (points.length >= 2) {
                final lengthKm =
                    (summary?['length'] as num? ?? 0).toDouble();
                final timeSec = (summary?['time'] as num? ?? 0).toDouble();
                return {
                  'points': points,
                  'distanceLabel': _formatDistance(lengthKm * 1000),
                  'durationLabel': _formatDuration(timeSec),
                };
              }
            }
          }
        }
      } finally {
        valhallaClient.close(force: true);
      }
    } catch (_) {}

    // 2. Tartalek: OSRM foot (turazasi sebesseggel korrigalva)
    final coords =
        waypoints.map((pt) => '${pt.longitude},${pt.latitude}').join(';');
    final osrmUri = Uri.parse(
      'https://router.project-osrm.org/route/v1/foot/$coords?overview=full&geometries=geojson&steps=false&continue_straight=false',
    );
    final osrmClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await osrmClient.getUrl(osrmUri);
      final response = await request.close();
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final data = jsonDecode(responseBody);
        if (data is Map &&
            data['code'] == 'Ok' &&
            data['routes'] is List &&
            (data['routes'] as List).isNotEmpty) {
          final route = (data['routes'] as List).first as Map;
          final geometry = route['geometry'];
          final coordsRaw = geometry is Map ? geometry['coordinates'] : null;
          if (coordsRaw is List && coordsRaw.isNotEmpty) {
            final points = <LatLng>[];
            for (final item in coordsRaw) {
              if (item is List && item.length >= 2) {
                final lng = item[0];
                final lat = item[1];
                if (lat is num && lng is num) {
                  points.add(LatLng(lat.toDouble(), lng.toDouble()));
                }
              }
            }
            if (points.length >= 2) {
              final dist = ((route['distance'] as num?) ?? 0).toDouble();
              // OSRM foot ~5 km/h, turazas ~3.5 km/h -> 1.43x
              final duration =
                  ((route['duration'] as num?) ?? 0).toDouble() * 1.43;
              return {
                'points': points,
                'distanceLabel': _formatDistance(dist),
                'durationLabel': _formatDuration(duration),
                'osrm': true,
              };
            }
          }
        }
      }
    } catch (_) {
    } finally {
      osrmClient.close(force: true);
    }

    return {
      'points': waypoints,
      'distanceLabel': 'N/A',
      'durationLabel': 'N/A',
      'fallback': true,
    };
  }

  static List<LatLng> _decodePolyline6(String encoded) {
    const precision = 6;
    final factor = math.pow(10, precision).toInt();
    final list = <LatLng>[];
    int index = 0;
    final len = encoded.length;
    int lat = 0;
    int lng = 0;
    while (index < len) {
      int result = 0;
      int shift = 0;
      int b = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      result = 0;
      shift = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      list.add(LatLng(lat / factor, lng / factor));
    }
    return list.length >= 2 ? list : const <LatLng>[];
  }

  void _appendRoutePoints(List<LatLng> target, List<LatLng> segment) {
    if (segment.isEmpty) return;
    if (target.isEmpty) {
      target.addAll(segment);
      return;
    }

    final first = segment.first;
    final last = target.last;
    if (_pointsClose(last, first)) {
      target.addAll(segment.skip(1));
      return;
    }

    target.addAll(segment);
  }

  bool _pointsClose(LatLng a, LatLng b, [double tolerance = 0.00002]) {
    return (a.latitude - b.latitude).abs() <= tolerance &&
        (a.longitude - b.longitude).abs() <= tolerance;
  }

  int _completedPrefixCount(List<Map<String, dynamic>> visibleStations) {
    var count = 0;
    for (final station in visibleStations) {
      final id = station['id'] as String?;
      if (id == null || !_completedIds.contains(id)) break;
      count += 1;
    }
    return count;
  }

  int _nearestRouteIndex(List<LatLng> routePoints, LatLng target) {
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var index = 0; index < routePoints.length; index += 1) {
      final point = routePoints[index];
      final latDiff = point.latitude - target.latitude;
      final lngDiff = point.longitude - target.longitude;
      final distance = latDiff * latDiff + lngDiff * lngDiff;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = index;
      }
    }
    return bestIndex;
  }
  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = _auth.currentUser?.uid;
      final results = await Future.wait([
        _firestore.collection('trips').get(),
        _firestore.collection('stations').get(),
        if (uid != null) _firestore.collection('user_progress').doc(uid).get(),
      ]);

      final tripsSnap = results[0] as QuerySnapshot;
      final stationsSnap = results[1] as QuerySnapshot;
      final trips = tripsSnap.docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data() as Map})
          .where((t) => t['isActive'] != false)
          .toList();
      final stations = stationsSnap.docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data() as Map})
          .toList();

      Set<String> completed = {};
      if (uid != null && results.length > 2) {
        final progress = results[2] as DocumentSnapshot;
        if (progress.exists) {
          completed = Set<String>.from(
            (progress.data() as Map)['completedStations'] ?? [],
          );
        }

        if (completed.isEmpty) {
          final completedStationsSnap = await _firestore
              .collection('user_progress')
              .doc(uid)
              .collection('completed_stations')
              .get();
          completed = completedStationsSnap.docs.map((doc) => doc.id).toSet();
        }
      }

      if (!mounted) return;
      setState(() {
        _trips = trips;
        _stations = stations;
        _completedIds = completed;
        _selectedTripId = trips.isNotEmpty ? trips.first['id'] as String : null;
        _loading = false;
      });
      await _refreshSelectedTripMap();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _refreshSelectedTripMap() async {
    final tripId = _selectedTripId;
    final visibleStations = _tripStationsFor(tripId);
    final markers = _buildMarkers(visibleStations);

    if (tripId == null) {
      if (!mounted) return;
      setState(() {
        _markers = markers;
        _polylines = {};
        _routeStatus = null;
      });
      return;
    }

    final cachedRoute = _routeCache[tripId];
    if (cachedRoute != null) {
      if (!mounted) return;
      setState(() {
        _markers = markers;
        _polylines = _buildPolylines(cachedRoute, visibleStations);
        _routeLoading = false;
        _routeStatus = _routeMetrics[tripId]?['status'];
      });
      _fitRouteOrStations(cachedRoute, visibleStations);
      return;
    }

    if (!mounted) return;
    setState(() {
      _markers = markers;
      _polylines = {};
      _routeLoading = true;
      _routeStatus = 'Túraútvonal keresése...';
    });

    final trip = _trips.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['id'] == tripId,
          orElse: () => null,
        );

    final stationPoints = visibleStations
        .map(_stationPoint)
        .whereType<LatLng>()
        .toList();

    List<LatLng> routePoints = const [];
    String status = 'Turistaútvonal';
    String distanceLabel = 'N/A';
    String durationLabel = 'N/A';

    if (trip != null) {
      routePoints = _extractTripRoute(trip);
      if (routePoints.length >= 2) {
        status = 'Tárolt túraútvonal';
      }
    }

    if (routePoints.length < 2 && stationPoints.length >= 2) {
      final routeData = await _fetchHikingRoute(stationPoints);
      routePoints = (routeData['points'] as List<dynamic>).whereType<LatLng>().toList();
      distanceLabel = routeData['distanceLabel']?.toString() ?? 'N/A';
      durationLabel = routeData['durationLabel']?.toString() ?? 'N/A';
      final fallback = routeData['fallback'] == true;
      final osrm = routeData['osrm'] == true;
      status = fallback
          ? 'Közelítő összekötés állomások között'
          : osrm
              ? 'Gyalogos útvonal'
              : 'OpenStreetMap turistaut';
    }

    if (routePoints.length < 2) {
      routePoints = stationPoints;
      status = stationPoints.length >= 2
          ? 'Közelítő összekötés állomások között'
          : 'Nincs elég állomás útvonalhoz';
    }

    _routeCache[tripId] = routePoints;
    _routeMetrics[tripId] = {
      'status': status,
      'distance': distanceLabel,
      'duration': durationLabel,
    };

    if (!mounted || _selectedTripId != tripId) return;
    setState(() {
      _markers = markers;
      _polylines = _buildPolylines(routePoints, visibleStations);
      _routeLoading = false;
      _routeStatus = status;
    });
    _fitRouteOrStations(routePoints, visibleStations);
  }

  Set<Marker> _buildMarkers(List<Map<String, dynamic>> visibleStations) {
    return Set<Marker>.from(
      visibleStations.map((s) {
        final done = _completedIds.contains(s['id'] as String);
        final point = _stationPoint(s)!;
        final order = _stationOrder(s);
        final orderText = order == (1 << 20) ? '?' : '${order + 1}.';
        return Marker(
          markerId: MarkerId(s['id'] as String),
          position: point,
          infoWindow: InfoWindow(
            title: '$orderText ${s['name'] ?? 'Állomás'}',
            snippet: done
                ? '✅ Teljesítve'
                : '${s['points'] ?? 10} pont',
          ),
          icon: done
              ? BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen,
                )
              : BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueViolet,
                ),
        );
      }),
    );
  }

  Set<Polyline> _buildPolylines(
    List<LatLng> routePoints,
    List<Map<String, dynamic>> visibleStations,
  ) {
    if (routePoints.length < 2) return {};

    final polylines = <Polyline>{};
    final completedCount = _completedPrefixCount(visibleStations);
    final completedColor = const Color(0xFF2E7D32);
    final remainingColor = const Color(0xFF8D6E63);

    if (completedCount > 0 && completedCount <= visibleStations.length) {
      final lastCompletedPoint = _stationPoint(visibleStations[completedCount - 1]);
      if (lastCompletedPoint != null) {
        final splitIndex = _nearestRouteIndex(routePoints, lastCompletedPoint);
        if (splitIndex >= 1) {
          polylines.add(
            Polyline(
              polylineId: const PolylineId('selected-trip-route-completed'),
              points: routePoints.sublist(0, splitIndex + 1),
              color: completedColor,
              width: 6,
              geodesic: false,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
            ),
          );
        }
        if (splitIndex < routePoints.length - 1) {
          polylines.add(
            Polyline(
              polylineId: const PolylineId('selected-trip-route-remaining'),
              points: routePoints.sublist(splitIndex == 0 ? 0 : splitIndex),
              color: remainingColor,
              width: 5,
              geodesic: false,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
            ),
          );
        }
        if (polylines.isNotEmpty) {
          return polylines;
        }
      }
    }

    return {
      Polyline(
        polylineId: const PolylineId('selected-trip-route-remaining'),
        points: routePoints,
        color: remainingColor,
        width: 5,
        geodesic: false,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    };
  }

  Future<void> _fitRouteOrStations(
    List<LatLng> routePoints,
    List<Map<String, dynamic>> stations,
  ) async {
    final controller = _mapController;
    if (controller == null) return;

    final points = routePoints.isNotEmpty
        ? routePoints
        : stations.map(_stationPoint).whereType<LatLng>().toList();
    if (points.isEmpty) return;

    if (points.length == 1) {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: points.first, zoom: 15),
        ),
      );
      return;
    }

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final point in points.skip(1)) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        56,
      ),
    );
  }

  Future<void> _selectTrip(String tripId) async {
    if (_selectedTripId == tripId) return;
    setState(() {
      _selectedTripId = tripId;
    });
    await _refreshSelectedTripMap();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Térkép és Túrák'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError()
          : _buildMapTab(),
    );
  }

  Widget _buildMapTab() {
    final tripStations = _tripStationsFor(_selectedTripId);
    final firstStationPoint = tripStations.isNotEmpty
        ? _stationPoint(tripStations.first)
        : null;
    final center = firstStationPoint ?? _defaultCenter;
    final metrics = _selectedTripId == null ? null : _routeMetrics[_selectedTripId!];

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
                    onSelected: (_) => _selectTrip(trip['id'] as String),
                  ),
                );
              }).toList(),
            ),
          ),
        if (_selectedTripId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _infoChip(Icons.route, _routeStatus ?? 'Állomások összekötése'),
                  if (metrics != null && metrics['distance'] != null)
                    _infoChip(Icons.straighten, metrics['distance']!),
                  if (metrics != null && metrics['duration'] != null)
                    _infoChip(Icons.schedule, metrics['duration']!),
                  if (_routeLoading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 13),
            markers: _markers,
            polylines: _polylines,
            zoomControlsEnabled: true,
            zoomGesturesEnabled: true,
            scrollGesturesEnabled: true,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            onMapCreated: (controller) {
              _mapController = controller;
              _fitRouteOrStations(
                _selectedTripId == null
                    ? const []
                    : (_routeCache[_selectedTripId!] ?? const []),
                tripStations,
              );
            },
            myLocationButtonEnabled: true,
            myLocationEnabled: true,
            mapToolbarEnabled: false,
            compassEnabled: true,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer(),
              ),
            },
          ),
        ),
      ],
    );
  }



  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF4EA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF2E7D32)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1B4332),
            ),
          ),
        ],
      ),
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
