import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/offline_image.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../services/local_cache.dart';
import '../services/offline_image_service.dart';
import '../services/offline_tiles_service.dart';

class MapTripsScreen extends StatefulWidget {
  const MapTripsScreen({super.key});

  @override
  State<MapTripsScreen> createState() => _MapTripsScreenState();
}

class _MapTripsScreenState extends State<MapTripsScreen> {
  static const LatLng _defaultCenter = LatLng(47.06, 17.715);

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _loading = true;
  bool _routeLoading = false;
  bool _downloadingTiles = false;
  final Set<String> _offlineTileTripIds = <String>{};
  String? _error;
  String? _routeStatus;
  String? _downloadStatus;

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

  List<String> _stationPhotos(Map<String, dynamic> station) {
    final photos = station['photos'];
    if (photos is List && photos.isNotEmpty) {
      return photos
          .map((entry) {
            if (entry is String) return entry;
            if (entry is Map) return entry['url']?.toString() ?? '';
            return '';
          })
          .where((url) => url.isNotEmpty)
          .cast<String>()
          .toList(growable: false);
    }

    final photoUrls = station['photoUrls'];
    if (photoUrls is List && photoUrls.isNotEmpty) {
      return photoUrls
          .map((entry) => entry?.toString() ?? '')
          .where((url) => url.isNotEmpty)
          .cast<String>()
          .toList(growable: false);
    }

    final imageUrl = station['imageUrl']?.toString();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return [imageUrl];
    }

    return const [];
  }

  void _openImageViewer(
    BuildContext context,
    List<String> photos,
    int initialIndex,
  ) {
    if (photos.isEmpty) return;
    var currentIndex = initialIndex;
    final pageController = PageController(initialPage: initialIndex);

    final dialogFuture = showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              PageView.builder(
                controller: pageController,
                itemCount: photos.length,
                onPageChanged: (index) =>
                    setDialogState(() => currentIndex = index),
                itemBuilder: (_, index) => InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: OfflineImage.network(
                      photos[index],
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 16,
                left: 16,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${currentIndex + 1}/${photos.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    dialogFuture.whenComplete(pageController.dispose);
  }

  void _showStationSheet(Map<String, dynamic> station) {
    final photos = _stationPhotos(station);
    final isCompleted = _completedIds.contains(station['id'] as String? ?? '');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        maxChildSize: 0.9,
        minChildSize: 0.42,
        builder: (context, controller) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8F4EC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1C2AE),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _stationName(station),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isCompleted
                              ? 'Teljesítve • ${station['points'] ?? 10} pont'
                              : '${station['points'] ?? 10} pont szerezhető',
                          style: TextStyle(
                            color: isCompleted
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFF8B5E34),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (photos.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('${photos.length} fotó'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (photos.isNotEmpty)
                SizedBox(
                  height: 210,
                  child: PageView.builder(
                    controller: PageController(viewportFraction: 0.9),
                    itemCount: photos.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () => _openImageViewer(context, photos, index),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              OfflineImage.network(
                                photos[index],
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  color: const Color(0xFFEADFCC),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.broken_image_outlined,
                                    size: 34,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 12,
                                right: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.56),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${index + 1}/${photos.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEADFCC),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: const Text('Ehhez az állomáshoz még nincs fotó.'),
                ),
              if ((station['description']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text(
                  'Leírás',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  station['description'].toString(),
                  style: const TextStyle(height: 1.45),
                ),
              ],
              if (isCompleted &&
                  (station['funFact']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('✨', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Feloldott fun fact',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              station['funFact'].toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _tripStationsFor(String? tripId) {
    final items =
        (tripId == null
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
    if (meters <= 0) return 'Nincs adat';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatDuration(double seconds) {
    if (seconds <= 0) return 'Nincs adat';
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

  Future<Map<String, dynamic>> _fetchHikingRoute(List<LatLng> waypoints) async {
    if (waypoints.length < 2) {
      return {
        'points': <LatLng>[],
        'distanceLabel': 'Nincs adat',
        'durationLabel': 'Nincs adat',
      };
    }

    final locations = waypoints
        .map(
          (p) =>
              '{"lon": ${p.longitude}, "lat": ${p.latitude}, "type": "break"}',
        )
        .join(',');
    final body =
        '{"locations": [$locations], "costing": "pedestrian", "costing_options": {"pedestrian": {"use_tracks": 1.0, "use_hills": 0.6, "walking_speed": 3.5, "transit_start_end_max_distance": 0}}, "directions_type": "none"}';

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
        final response = await request.close().timeout(
          const Duration(seconds: 12),
        );
        if (response.statusCode == 200) {
          final responseBody = await response
              .transform(utf8.decoder)
              .join()
              .timeout(const Duration(seconds: 10));
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
                final lengthKm = (summary?['length'] as num? ?? 0).toDouble();
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
    final coords = waypoints
        .map((pt) => '${pt.longitude},${pt.latitude}')
        .join(';');
    final osrmUri = Uri.parse(
      'https://router.project-osrm.org/route/v1/foot/$coords?overview=full&geometries=geojson&steps=false&continue_straight=false',
    );
    final osrmClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await osrmClient.getUrl(osrmUri);
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode == 200) {
        final responseBody = await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 8));
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
      'distanceLabel': 'Nincs adat',
      'durationLabel': 'Nincs adat',
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
    _initOfflineTileState();
    _loadAll();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initOfflineTileState() async {
    final tripIds = LocalCache.getOfflineTileTripIds();
    if (!mounted) return;
    setState(() {
      _offlineTileTripIds
        ..clear()
        ..addAll(tripIds);
    });
  }

  Future<void> _downloadOfflineTiles() async {
    if (_downloadingTiles) return;

    final selectedTripId = _selectedTripId;

    final tripStations = _tripStationsFor(_selectedTripId);
    final routePoints = _selectedTripId == null
        ? const <LatLng>[]
        : (_routeCache[_selectedTripId!] ?? const <LatLng>[]);
    final photoUrls = tripStations
        .expand(_stationPhotos)
        .toSet()
        .toList(growable: false);

    final focusPoints = routePoints.isNotEmpty
        ? routePoints
              .map((p) => ll.LatLng(p.latitude, p.longitude))
              .toList(growable: false)
        : tripStations
              .map(_stationPoint)
              .whereType<LatLng>()
              .map((p) => ll.LatLng(p.latitude, p.longitude))
              .toList(growable: false);

    setState(() {
      _downloadingTiles = true;
      _downloadStatus = 'Offline csempék letöltése...';
    });

    final downloaded = await OfflineTilesService.downloadNagyvazsonyTiles(
      focusPoints: focusPoints,
      minZoom: 13,
      maxZoom: 19,
      onProgress: (done, total) async {
        if (!mounted) return;
        setState(() {
          _downloadStatus = 'Térkép: $done / $total';
        });
      },
    );

    var downloadedImages = 0;
    if (photoUrls.isNotEmpty) {
      downloadedImages = await OfflineImageService.cacheImages(
        photoUrls,
        onProgress: (done, total) async {
          if (!mounted) return;
          setState(() {
            _downloadStatus = 'Képek: $done / $total';
          });
        },
      );
    }

    if ((downloaded > 0 || downloadedImages > 0) && selectedTripId != null) {
      await LocalCache.markTripOfflineTilesDownloaded(selectedTripId);
    }

    if (!mounted) return;
    setState(() {
      _downloadingTiles = false;
      if ((downloaded > 0 || downloadedImages > 0) && selectedTripId != null) {
        _offlineTileTripIds.add(selectedTripId);
      }
      _downloadStatus =
          'Offline kész: $downloaded térképcsempe, $downloadedImages kép';
    });
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = _auth.currentUser?.uid;
      List<Map<String, dynamic>> trips = [];
      List<Map<String, dynamic>> stations = [];
      Set<String> completed = {};

      try {
        final results = await Future.wait([
          _firestore.collection('trips').get(),
          _firestore.collection('stations').get(),
          if (uid != null)
            _firestore.collection('user_progress').doc(uid).get(),
        ]).timeout(const Duration(seconds: 15));

        final tripsSnap = results[0] as QuerySnapshot;
        final stationsSnap = results[1] as QuerySnapshot;
        trips = tripsSnap.docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data() as Map})
            .where((t) => t['isActive'] != false)
            .toList();
        stations = stationsSnap.docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data() as Map})
            .toList();

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

        if (trips.isNotEmpty) await LocalCache.saveTrips(trips);
        if (stations.isNotEmpty) await LocalCache.saveStations(stations);
      } catch (_) {
        final cachedTrips = LocalCache.getTrips();
        final cachedStations = LocalCache.getStations();
        if (cachedTrips.isEmpty && cachedStations.isEmpty) rethrow;
        trips = cachedTrips;
        stations = cachedStations;
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

    final persistedRoute = LocalCache.getRoute(tripId);
    if (persistedRoute != null) {
      final persistedPoints = _decodeStoredRoute(persistedRoute['points']);
      final persistedMetrics = persistedRoute['metrics'];
      if (persistedPoints.length >= 2) {
        _routeCache[tripId] = persistedPoints;
        if (persistedMetrics is Map) {
          _routeMetrics[tripId] = persistedMetrics.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          );
        }
        if (!mounted) return;
        setState(() {
          _markers = markers;
          _polylines = _buildPolylines(persistedPoints, visibleStations);
          _routeLoading = false;
          _routeStatus = _routeMetrics[tripId]?['status'] ?? 'Offline útvonal';
        });
        _fitRouteOrStations(persistedPoints, visibleStations);
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _markers = markers;
      _polylines = {};
      _routeLoading = true;
      _routeStatus = 'Túraútvonal keresése...';
    });

    final stationPoints = visibleStations
        .map(_stationPoint)
        .whereType<LatLng>()
        .toList();

    List<LatLng> routePoints = const [];
    String status = 'Turistaútvonal';
    String distanceLabel = 'Nincs adat';
    String durationLabel = 'Nincs adat';
    bool isValhallaRoute = false;

    // Elsodlegesen Valhalla-t hasznalunk, hogy turistautak/foldutak legyenek preferalva.
    if (stationPoints.length >= 2) {
      try {
        final routeData = await _fetchHikingRoute(stationPoints);
        final fetchedPoints = (routeData['points'] as List<dynamic>)
            .whereType<LatLng>()
            .toList();
        final fallback = routeData['fallback'] == true;
        final osrm = routeData['osrm'] == true;

        if (fetchedPoints.length >= 2) {
          routePoints = fetchedPoints;
          distanceLabel = routeData['distanceLabel']?.toString() ?? 'N/A';
          durationLabel = routeData['durationLabel']?.toString() ?? 'N/A';
          isValhallaRoute = !fallback && !osrm;
          status = fallback
              ? 'Közelítő összekötés állomások között'
              : osrm
              ? 'Gyalogos útvonal'
              : 'OpenStreetMap turistaút';
        }
      } catch (_) {
        // timeout vagy halozati hiba
      }
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

    if (routePoints.length >= 2 &&
        status != 'Közelítő összekötés állomások között' &&
        isValhallaRoute) {
      await LocalCache.saveRoute(
        tripId,
        routePoints
            .map((p) => ll.LatLng(p.latitude, p.longitude))
            .toList(growable: false),
        _routeMetrics[tripId]!,
      );
    }

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
          onTap: () => _showStationSheet(s),
          infoWindow: InfoWindow(
            title: '$orderText ${s['name'] ?? 'Állomás'}',
            snippet: done ? '✅ Teljesítve' : '${s['points'] ?? 10} pont',
          ),
          icon: done
              ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)
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
      final lastCompletedPoint = _stationPoint(
        visibleStations[completedCount - 1],
      );
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


  Widget _buildMapSkeleton(BuildContext context) {
    final grey = Colors.grey.shade200;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Trip selector chips row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(
                4,
(i) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    width: 90,
                    height: 36,
                    decoration: BoxDecoration(color: grey, borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Map placeholder
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(color: grey),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Metrics row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: List.generate(
              3,
              (i) => Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  height: 48,
                  decoration: BoxDecoration(color: grey, borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Station list skeletons
        Expanded(
          flex: 3,
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: 4,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                height: 52,
                decoration: BoxDecoration(color: grey, borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Térkép és Túrák')),
      body: _loading
          ? _buildMapSkeleton(context)
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
    final metrics = _selectedTripId == null
        ? null
        : _routeMetrics[_selectedTripId!];
    final selectedTripId = _selectedTripId;
    final tripHasOfflineTiles = selectedTripId != null
        ? _offlineTileTripIds.contains(selectedTripId)
        : false;

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
                  _infoChip(
                    Icons.route,
                    _routeStatus ?? 'Állomások összekötése',
                  ),
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
                  SizedBox(
                    width: 230,
                    child: OutlinedButton.icon(
                      onPressed: _downloadingTiles
                          ? null
                          : _downloadOfflineTiles,
                      icon: Icon(
                        tripHasOfflineTiles
                            ? Icons.check_circle
                            : Icons.download_for_offline_outlined,
                        color: tripHasOfflineTiles ? Colors.green : null,
                      ),
                      label: Text(
                        _downloadingTiles
                            ? 'HD letöltés...'
                            : 'Offline térkép HD',
                      ),
                    ),
                  ),
                  if (_downloadStatus != null)
                    Text(
                      _downloadStatus!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: center,
                    zoom: 13,
                  ),
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
                ),
              ),
              if (tripStations.isNotEmpty)
                SizedBox(
                  height: 152,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    scrollDirection: Axis.horizontal,
                    itemCount: tripStations.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final station = tripStations[index];
                      final photos = _stationPhotos(station);
                      final done = _completedIds.contains(
                        station['id'] as String? ?? '',
                      );
                      return SizedBox(
                        width: 248,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => _showStationSheet(station),
                          child: Ink(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.horizontal(
                                    left: Radius.circular(18),
                                  ),
                                  child: SizedBox(
                                    width: 88,
                                    height: double.infinity,
                                    child: photos.isNotEmpty
                                        ? OfflineImage.network(
                                            photos.first,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) =>
                                                Container(
                                                  color: const Color(
                                                    0xFFEADFCC,
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: const Icon(
                                                    Icons
                                                        .photo_library_outlined,
                                                  ),
                                                ),
                                          )
                                        : Container(
                                            color: const Color(0xFFEADFCC),
                                            alignment: Alignment.center,
                                            child: const Icon(
                                              Icons.photo_library_outlined,
                                            ),
                                          ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          _stationName(station),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          done
                                              ? 'Teljesítve'
                                              : '${station['points'] ?? 10} pont',
                                          style: TextStyle(
                                            color: done
                                                ? const Color(0xFF2E7D32)
                                                : const Color(0xFF8B5E34),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${photos.length} fotó',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
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
          const Text(
            'Nem sikerült betölteni a térképet',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _loadAll, child: const Text('Újrapróbálás')),
        ],
      ),
    );
  }
}
