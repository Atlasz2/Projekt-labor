import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../utils/image_normalizer.dart';
import '../widgets/offline_image.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../services/trip_route_service.dart';
import '../services/local_cache.dart';
import '../services/offline_image_service.dart';
import '../services/offline_tiles_service.dart';
import '../widgets/station_detail_sheet.dart';
import 'full_screen_map_screen.dart';
import 'trip_navigation_screen.dart';
import '../utils/project_filter.dart';
import '../services/offline_sync_service.dart';
import '../utils/station_trips.dart';

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

  String _stationName(Map<String, dynamic> station) {
    return station['name']?.toString() ?? 'Állomás';
  }

  /// Egy állomás sorrend-indexe a megadott túrán belül (null tripId esetén,
  /// amikor nincs kiválasztott túra, csak névre rendezünk – az egyes
  /// állomások eltérő túrákhoz tartozó sorrendje itt nem összevethető).
  List<Map<String, dynamic>> _tripStationsFor(String? tripId) {
    final items =
        (tripId == null ? _stations : stationsForTrip(_stations, tripId))
            .where((s) => _stationPoint(s) != null)
            .toList();

    if (tripId == null) {
      items.sort((a, b) => _stationName(a).compareTo(_stationName(b)));
    }
    return items;
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

  Future<void> _startOfflineTilesDownload() async {
    if (_downloadingTiles) return;
    final maxZoom = await _askTileQuality();
    if (maxZoom == null || !mounted) return;
    await _downloadOfflineTiles(maxZoom: maxZoom);
  }

  /// Lets the user trade detail for storage: space-saving caps at street level
  /// (z17), detailed goes to full HD (z19) — the top zoom dominates tile count.
  Future<int?> _askTileQuality() {
    return showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Offline térkép letöltése',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Mennyire legyen részletes a letöltött térkép? A részletesebb több helyet foglal.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.save_outlined,
                color: Color(0xFF2E7D32),
              ),
              title: const Text('Helytakarékos'),
              subtitle: const Text('Kisebb méret, utcaszintű részletesség'),
              onTap: () => Navigator.pop(sheetContext, 17),
            ),
            ListTile(
              leading: const Icon(
                Icons.high_quality_outlined,
                color: Color(0xFF1D4ED8),
              ),
              title: const Text('Részletes (HD)'),
              subtitle: const Text('Nagyobb méret, maximális részletesség'),
              onTap: () => Navigator.pop(sheetContext, 19),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadOfflineTiles({required int maxZoom}) async {
    if (_downloadingTiles) return;

    final selectedTripId = _selectedTripId;

    final tripStations = _tripStationsFor(_selectedTripId);
    final routePoints = _selectedTripId == null
        ? const <LatLng>[]
        : (_routeCache[_selectedTripId!] ?? const <LatLng>[]);
    final photoUrls = tripStations
        .expand(photoListFromDoc)
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
      maxZoom: maxZoom,
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

  Future<void> _clearOfflineTiles() async {
    if (_downloadingTiles) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Offline térkép törlése'),
        content: const Text(
          'Biztosan törlöd a letöltött offline térképcsempéket? Felszabadul a tárhely, '
          'de offline használathoz később újra le kell töltened.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Mégse'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Törlés'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _downloadStatus = 'Offline térkép törlése...');
    await OfflineTilesService.clearTiles();
    await LocalCache.clearOfflineTileTripIds();
    if (!mounted) return;
    setState(() {
      _offlineTileTripIds.clear();
      _downloadStatus = 'Offline térkép törölve.';
    });
  }

  /// A kiadás településéhez tartozó, aktív túrák. Hibatűrő: ha a szűrés
  /// mindent kidobna, inkább a teljes listát mutatjuk, semmint üres térképet.
  List<Map<String, dynamic>> _visibleTrips(List<Map<String, dynamic>> all) =>
      filterToActiveProject<Map<String, dynamic>>(
        all.where((t) => t['isActive'] != false).toList(),
        (t) => t,
      );

  List<Map<String, dynamic>> _visibleStations(List<Map<String, dynamic>> all) =>
      filterToActiveProject<Map<String, dynamic>>(all, (st) => st);

  /// A teljesített állomások – a [source] szerint szerverről vagy a Firestore
  /// helyi gyorsítótárából.
  Future<Set<String>> _completedStations(String uid, Source source) async {
    final options = GetOptions(source: source);
    final progressRef = _firestore.collection('user_progress').doc(uid);
    final progress = await progressRef.get(options);
    final fromDoc = Set<String>.from(
      (progress.data() ?? const {})['completedStations'] ?? const [],
    );
    if (fromDoc.isNotEmpty) return fromDoc;
    final completedSnap = await progressRef
        .collection('completed_stations')
        .get(options);
    return completedSnap.docs.map((doc) => doc.id).toSet();
  }

  /// Gyorsítótár-először betöltés: a készüléken tárolt túrák és állomások
  /// azonnal megjelennek, a friss adat a háttérben érkezik és csak akkor
  /// rajzolja újra a térképet, ha változott. Üres gyorsítótárnál (első
  /// indítás) a szerverre várunk.
  Future<void> _loadAll() async {
    setState(() {
      _error = null;
    });
    final uid = _auth.currentUser?.uid;

    final cachedTrips = _visibleTrips(LocalCache.getTrips());
    final cachedStations = _visibleStations(LocalCache.getStations());
    final showedCache = cachedTrips.isNotEmpty || cachedStations.isNotEmpty;

    if (showedCache) {
      var completed = <String>{};
      if (uid != null) {
        try {
          completed = await _completedStations(uid, Source.cache);
        } catch (_) {
          // Még nincs helyi példány – a háttérfrissítés pótolja.
        }
      }
      if (!mounted) return;
      _applyData(cachedTrips, cachedStations, completed);
      unawaited(_refreshSelectedTripMap());
    } else {
      setState(() => _loading = true);
    }

    try {
      final results = await Future.wait([
        _firestore.collection('trips').get(),
        _firestore.collection('stations').get(),
      ]).timeout(const Duration(seconds: 15));

      final allTrips = results[0].docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .toList();
      final allStations = results[1].docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .toList();
      if (allTrips.isNotEmpty) await LocalCache.saveTrips(allTrips);
      if (allStations.isNotEmpty) await LocalCache.saveStations(allStations);

      var completed = _completedIds;
      if (uid != null) {
        try {
          completed = await _completedStations(
            uid,
            Source.serverAndCache,
          ).timeout(const Duration(seconds: 10));
        } catch (_) {
          // A haladás nélkül is megjeleníthető a térkép.
        }
      }

      // A tárolt (egységesített) alakot használjuk, így a gyorsítótárból
      // mutatott adattal megbízhatóan összevethető.
      final trips = _visibleTrips(
        allTrips.isNotEmpty ? LocalCache.getTrips() : allTrips,
      );
      final stations = _visibleStations(
        allStations.isNotEmpty ? LocalCache.getStations() : allStations,
      );
      if (!mounted) return;
      final changed =
          !showedCache ||
          !_sameDocs(trips, _trips) ||
          !_sameDocs(stations, _stations) ||
          !setEquals(completed, _completedIds);
      if (!changed) return;
      _applyData(trips, stations, completed);
      await _refreshSelectedTripMap();
    } catch (e) {
      if (!mounted) return;
      // Ha már a gyorsítótárból megjelent a térkép, a sikertelen frissítés
      // nem hiba (offline / lassú hálózat).
      if (showedCache) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _applyData(
    List<Map<String, dynamic>> trips,
    List<Map<String, dynamic>> stations,
    Set<String> completed,
  ) {
    // A kiválasztott túra megmarad, ha a frissítés után is létezik.
    final keepSelection =
        _selectedTripId != null && trips.any((t) => t['id'] == _selectedTripId);
    // A megváltozott túráknál az útvonalat újra kell számolni.
    for (final trip in trips) {
      final id = trip['id'] as String;
      final old = _trips.where((t) => t['id'] == id).firstOrNull;
      if (old != null && jsonEncode(old) != jsonEncode(trip)) {
        _routeCache.remove(id);
        _routeMetrics.remove(id);
      }
    }
    setState(() {
      _trips = trips;
      _stations = stations;
      _completedIds = completed;
      _selectedTripId = keepSelection
          ? _selectedTripId
          : (trips.isNotEmpty ? trips.first['id'] as String : null);
      _loading = false;
    });
  }

  /// Két dokumentumlista tartalmilag azonos-e (azonosító és mezők szerint).
  static bool _sameDocs(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    if (a.length != b.length) return false;
    try {
      return jsonEncode(a) == jsonEncode(b);
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshSelectedTripMap() async {
    final tripId = _selectedTripId;
    final visibleStations = _tripStationsFor(tripId);
    final markers = _buildMarkers(visibleStations, tripId);

    if (tripId == null) {
      if (!mounted) return;
      setState(() {
        _markers = markers;
        _polylines = {};
        _routeStatus = null;
      });
      return;
    }

    // A memóriában tartott útvonal azonnal kirajzolható – kivéve a légvonalas
    // közelítést, amelyet hálózat mellett újra megpróbálunk valódira cserélni.
    final cachedRoute = _routeCache[tripId];
    if (cachedRoute != null &&
        _routeMetrics[tripId]?['status'] != TripRouteService.fallbackStatus) {
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

    final trip = _trips.firstWhere(
      (t) => t['id'] == tripId,
      orElse: () => const <String, dynamic>{},
    );
    final stationPoints = visibleStations
        .map(_stationPoint)
        .whereType<LatLng>()
        .toList();

    // Offline is elérhető útvonal (a túrában tárolt vagy az eszközön mentett)
    // esetén nincs töltés; egyébként jelezzük, hogy keresünk.
    if (TripRouteService.available(tripId, trip) == null) {
      if (!mounted) return;
      setState(() {
        _markers = markers;
        _polylines = {};
        _routeLoading = true;
        _routeStatus = 'Túraútvonal keresése...';
      });
    }

    final route = await TripRouteService.resolve(
      tripId: tripId,
      trip: trip,
      stationPoints: stationPoints,
      allowNetwork: OfflineSyncService().isOnline,
    );
    final routePoints = route.points;
    _routeCache[tripId] = routePoints;
    _routeMetrics[tripId] = route.metrics;
    final status = route.status;

    if (!mounted || _selectedTripId != tripId) return;
    setState(() {
      _markers = markers;
      _polylines = _buildPolylines(routePoints, visibleStations);
      _routeLoading = false;
      _routeStatus = status;
    });
    _fitRouteOrStations(routePoints, visibleStations);
  }

  Set<Marker> _buildMarkers(
    List<Map<String, dynamic>> visibleStations,
    String? tripId,
  ) {
    return Set<Marker>.from(
      visibleStations.map((s) {
        final done = _completedIds.contains(s['id'] as String);
        final point = _stationPoint(s)!;
        final orderText = tripId == null
            ? '?'
            : '${stationOrderIndexForTrip(s, tripId) + 1}.';
        return Marker(
          markerId: MarkerId(s['id'] as String),
          position: point,
          onTap: () => showStationDetailSheet(
            context,
            station: s,
            isCompleted: _completedIds.contains(s['id'] as String? ?? ''),
          ),
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

  void _startNavigation() {
    final tripId = _selectedTripId;
    if (tripId == null) return;
    final tripStations = _tripStationsFor(tripId);
    if (tripStations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ehhez a túrához nincs állomás.')),
      );
      return;
    }
    final trip = _trips.firstWhere(
      (t) => t['id'] == tripId,
      orElse: () => const <String, dynamic>{},
    );
    final routePoints = _routeCache[tripId] ?? const <LatLng>[];

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TripNavigationScreen(
          tripName: trip['name']?.toString() ?? 'Túra',
          stations: tripStations,
          routePoints: routePoints,
          completedIds: Set<String>.from(_completedIds),
        ),
      ),
    );
  }

  void _openFullScreenMap() {
    final tripStations = _tripStationsFor(_selectedTripId);
    final routePoints = _selectedTripId == null
        ? const <LatLng>[]
        : (_routeCache[_selectedTripId!] ?? const <LatLng>[]);
    final fitPoints = routePoints.isNotEmpty
        ? routePoints
        : tripStations.map(_stationPoint).whereType<LatLng>().toList();
    final center = fitPoints.isNotEmpty ? fitPoints.first : _defaultCenter;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullScreenMapScreen(
          markers: _markers,
          polylines: _polylines,
          initialPosition: center,
          fitPoints: fitPoints,
        ),
      ),
    );
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
                    decoration: BoxDecoration(
                      color: grey,
                      borderRadius: BorderRadius.circular(20),
                    ),
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
                  decoration: BoxDecoration(
                    color: grey,
                    borderRadius: BorderRadius.circular(10),
                  ),
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
                decoration: BoxDecoration(
                  color: grey,
                  borderRadius: BorderRadius.circular(10),
                ),
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
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _startNavigation,
                      icon: const Icon(Icons.navigation),
                      label: const Text('Túra indítása – navigáció'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
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
                          : _startOfflineTilesDownload,
                      icon: Icon(
                        tripHasOfflineTiles
                            ? Icons.check_circle
                            : Icons.download_for_offline_outlined,
                        color: tripHasOfflineTiles ? Colors.green : null,
                      ),
                      label: Text(
                        _downloadingTiles ? 'Letöltés...' : 'Offline térkép',
                      ),
                    ),
                  ),
                  if (_offlineTileTripIds.isNotEmpty && !_downloadingTiles)
                    TextButton.icon(
                      onPressed: _clearOfflineTiles,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Offline térkép törlése'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFC62828),
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
                child: Stack(
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: OfflineSyncService().onlineNotifier,
                      builder: (context, online, _) => GoogleMap(
                        tileOverlays: OfflineTilesService.overlaysFor(
                          online: online,
                        ),
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
                        // Claim the gesture immediately so pan/zoom feel native
                        // instead of fighting the surrounding scroll views.
                        gestureRecognizers:
                            <Factory<OneSequenceGestureRecognizer>>{
                              Factory<OneSequenceGestureRecognizer>(
                                EagerGestureRecognizer.new,
                              ),
                            },
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
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        elevation: 3,
                        child: IconButton(
                          icon: const Icon(Icons.fullscreen),
                          tooltip: 'Teljes képernyős térkép',
                          onPressed: _openFullScreenMap,
                        ),
                      ),
                    ),
                  ],
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
                      final photos = photoListFromDoc(station);
                      final done = _completedIds.contains(
                        station['id'] as String? ?? '',
                      );
                      return SizedBox(
                        width: 248,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => showStationDetailSheet(
                            context,
                            station: station,
                            isCompleted: _completedIds.contains(
                              station['id'] as String? ?? '',
                            ),
                          ),
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
