import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// Google Maps (Android/iOS/Web)
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

// Desktop térkép: OpenStreetMap a flutter_map-pal
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as ll;

import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:geolocator/geolocator.dart';

import 'models/station.dart';
import 'services/map_service.dart';
import 'services/directions_service.dart';
import 'config/firebase_config.dart';

// -----------------------------------------------------------------------------
// ÁLLANDÓK
// -----------------------------------------------------------------------------
const gmap.LatLng nagyvazsony = gmap.LatLng(46.9890, 17.6990);

// IDE írd a SAJÁT kulcsodat (Google Directions API)
const String kGoogleDirectionsApiKey = 'AIzaSyCRuETGR8p_vlsBrm6JLK1RNHeGQtMV8o4';

// -----------------------------------------------------------------------------
// APP INDÍTÁS
// -----------------------------------------------------------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseConfig.initializeApp();
  runApp(const TuraApp());
}

// -----------------------------------------------------------------------------
// ALKALMAZÁS
// -----------------------------------------------------------------------------
class TuraApp extends StatelessWidget {
  const TuraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Túra',
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    );
  }
}

// -----------------------------------------------------------------------------
// FŐ KÉPERNYŐ
// -----------------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Position? _currentPosition;

  // Google Maps rétegek
  final Set<gmap.Marker> _markers = {};
  final Set<gmap.Polyline> _polylines = {};
  // Google overlay OFF minden platformon (desktopon gondot okoz)
  final Set<gmap.TileOverlay> _tileOverlays = const {};

  // Túraösvény láthatóság desktopon (flutter_map)
  bool _hikingVisible = true;

  final MapService _mapService = MapService();
  final DirectionsService _directions = DirectionsService(kGoogleDirectionsApiKey);

  int? _currentTripId;
  List<Station> _stations = [];
  StreamSubscription<Position>? _posSub;

  // Kijelölt pontok (Google LatLng)
  final List<gmap.LatLng> _selectedPoints = [];

  // Alternatívák + kiválasztás
  List<RouteChoice> _routeChoices = [];
  int? _activeRouteIndex;
  DrivingOverview? _driving;

  // UI – felső és alsó kezelősor összehúzás
  bool _controlsCollapsed = false;
  bool _bottomCollapsed = false;
  bool _isDark = false;

  // checkpointok
  final List<gmap.LatLng> _flagPoints = [];

  // térkép kontrollerek
  final fm.MapController _fmController = fm.MapController(); // desktop
  gmap.GoogleMapController? _gController;                    // mobil/web

  // ---------------------------------------------------------------------------
  // INIT/DISPOSE
  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _loadStations();
    _startPositionStream();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // ADATBETÖLTÉS
  // ---------------------------------------------------------------------------
  Future<void> _loadStations() async {
    try {
      if (_currentTripId == null) {
        final trips = await _mapService.getTrips();
        if (trips.isNotEmpty) _currentTripId = trips.first.id;
      }
      if (_currentTripId != null) {
        final stations = await _mapService.getStationsForTrip(_currentTripId!);
        final pathPoints = await _mapService.getTripPath(_currentTripId!); // List<gmap.LatLng>
        setState(() {
          _stations = stations;
          _updateMarkers();
          _updatePath(pathPoints);
        });
      }
    } catch (e) {
      debugPrint('Hiba az állomások betöltésekor: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // HELYMEGHATÁROZÁS
  // ---------------------------------------------------------------------------
  Future<void> _startPositionStream() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      final settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );
      _posSub?.cancel();
      _posSub = Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
        setState(() {
          _currentPosition = pos;
          _updateMarkers();
        });
      });
    } catch (e) {
      debugPrint('Hely stream hiba: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // TÉRKÉP RÉTEGEK (GOOGLE)
// ---------------------------------------------------------------------------
  void _updatePath(List<gmap.LatLng> pathPoints) {
    setState(() {
      _polylines.removeWhere((p) => p.polylineId.value.startsWith('trip_path'));
      if (pathPoints.isNotEmpty) {
        _polylines.add(
          gmap.Polyline(
            polylineId: const gmap.PolylineId('trip_path'),
            points: pathPoints,
            color: Colors.blue,
            width: 5,
          ),
        );
      }
    });
  }

  void _updateMarkers() {
    _markers
      ..removeWhere((m) =>
          m.markerId.value == 'current_location' || m.markerId.value.startsWith('station_'));

    // Állomások
    for (final station in _stations) {
      _markers.add(
        gmap.Marker(
          markerId: gmap.MarkerId('station_${station.id}'),
          position: station.location,
          infoWindow: gmap.InfoWindow(title: station.name, snippet: station.description),
        ),
      );
    }

    // Aktuális pozíció
    if (_currentPosition != null) {
      _markers.add(
        gmap.Marker(
          markerId: const gmap.MarkerId('current_location'),
          position: gmap.LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          icon: gmap.BitmapDescriptor.defaultMarkerWithHue(gmap.BitmapDescriptor.hueAzure),
          infoWindow: const gmap.InfoWindow(title: 'Jelenlegi pozíció'),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // SZÁMOZOTT ZÖLD KIJELÖLŐ IKON (GOOGLE MAPS) – kisebb méret
  // ---------------------------------------------------------------------------
  Future<gmap.BitmapDescriptor> _numberedMarkerIcon(int n) async {
    const int size = 56; // kisebb ikon
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final center = ui.Offset(size / 2, size / 2);

    // Fehér keret
    canvas.drawCircle(center, size * 0.46, ui.Paint()..color = Colors.white);
    // Zöld kör
    canvas.drawCircle(center, size * 0.42, ui.Paint()..color = const Color(0xFF2E7D32));

    // Szám
    final tp = TextPainter(
      text: TextSpan(
        text: n.toString(),
        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, ui.Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));

    final image = await recorder.endRecording().toImage(size, size);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return gmap.BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  // ---------------------------------------------------------------------------
  // QR SZKENNER
  // ---------------------------------------------------------------------------
  Future<void> _scanQRCode() async {
    final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    if (isDesktop) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A QR szkenner csak Android/iOS/Web alatt érhető el.')),
      );
      return;
    }

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('QR kód beolvasása')),
            body: MobileScanner(
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  final String? code = barcode.rawValue;
                  if (code != null) {
                    _checkQRCode(code);
                  }
                }
              },
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Hiba a QR kód beolvasásakor: $e');
    }
  }

  void _checkQRCode(String code) {
    final station = _stations.firstWhere(
      (s) => s.qrCode == code,
      orElse: () => throw Exception('Ismeretlen QR kód'),
    );

    Navigator.pop(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(station.name),
        content: Text(station.description),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Bezárás')),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ÚTVONAL-GENERÁLÁS (alternatívák + autós elérhetőség)
// ---------------------------------------------------------------------------
  Future<void> _buildRoutes() async {
    try {
      if (_selectedPoints.length < 2) return;

      final origin = _selectedPoints.first;
      final destination = _selectedPoints.last;
      final waypoints = _selectedPoints.length > 2
          ? _selectedPoints.sublist(1, _selectedPoints.length - 1)
          : const <gmap.LatLng>[];

      // 1) Gyalogos alternatívák
      final choices = await _directions.getWalkingAlternatives(
        origin: origin,
        destination: destination,
        waypoints: waypoints,
      );

      // 2) Autós elérhetőség + kb. idő/táv
      final driving = await _directions.getDrivingOverview(
        origin: origin,
        destination: destination,
        waypoints: waypoints,
      );

      setState(() {
        _routeChoices = choices;
        _driving = driving;

        _activeRouteIndex = null; // még nincs választás
        _controlsCollapsed = false;

        // Rajz: összes alternatíva halványan
        _polylines.removeWhere((p) => p.polylineId.value.startsWith('route_'));
        for (int i = 0; i < _routeChoices.length; i++) {
          final id = gmap.PolylineId('route_$i');
          _polylines.add(gmap.Polyline(
            polylineId: id,
            points: _routeChoices[i].points,
            width: 4,
            color: Colors.blueGrey.shade400,
          ));
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Útvonal-hiba: $e')));
    }
  }

  void _selectRoute(int index) {
    setState(() {
      _activeRouteIndex = index;
      _polylines.removeWhere((p) => p.polylineId.value.startsWith('route_'));
      for (int i = 0; i < _routeChoices.length; i++) {
        final id = gmap.PolylineId('route_$i');
        _polylines.add(gmap.Polyline(
          polylineId: id,
          points: _routeChoices[i].points,
          width: i == index ? 7 : 4,
          color: i == index ? Colors.blue : Colors.blueGrey.shade400,
        ));
      }
      _controlsCollapsed = true; // smooth felcsúsztatás
    });
  }

  void _clearActiveRoute() {
    setState(() {
      _activeRouteIndex = null;
      _routeChoices.clear();
      _driving = null;
      _polylines.removeWhere((p) => p.polylineId.value.startsWith('route_'));
      _controlsCollapsed = false;
    });
  }

  void _clearSelections() {
    setState(() {
      _selectedPoints.clear();
      _routeChoices.clear();
      _activeRouteIndex = null;
      _driving = null;
      _polylines.removeWhere((p) => p.polylineId.value.startsWith('route_'));
      _markers.removeWhere((m) => m.markerId.value.startsWith('sel_'));
      _controlsCollapsed = false;
    });
  }

  // „Mentés” → előre kitöltött jegyzet
  void _saveRouteToNotes() {
    if (_activeRouteIndex == null || _routeChoices.isEmpty) return;
    final r = _routeChoices[_activeRouteIndex!];

    final buffer = StringBuffer();
    buffer.writeln('Mentett útvonal');
    buffer.writeln('- Pontok száma: ${_selectedPoints.length}');
    buffer.writeln('- Gyalog: ${_fmtMin(r.walkDurationSec)} • ${_fmtKm(r.walkDistanceMeters)}');
    if (_driving != null) {
      buffer.writeln(
          '- Autó: ${_driving!.available ? "elérhető" : "nem elérhető"}'
          '${_driving!.available ? " • kb ${_fmtMin(_driving!.durationSec!)} • ${_fmtKm(_driving!.distanceMeters!)}" : ""}');
    }
    buffer.writeln('');
    for (int i = 0; i < _selectedPoints.length; i++) {
      final p = _selectedPoints[i];
      buffer.writeln('[${i + 1}] ${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}');
      buffer.writeln('    Megjegyzés: ');
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotesScreen(
          currentPosition: _currentPosition,
          prefill: buffer.toString(),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Alsó menü funkciók
  // ---------------------------------------------------------------------------
  void _addCheckpoint() {
    final gmap.LatLng? p = _currentPosition != null
        ? gmap.LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : (_selectedPoints.isNotEmpty ? _selectedPoints.last : null);
    if (p == null) return;
    setState(() => _flagPoints.add(p));
    // Google marker
    _markers.add(
      gmap.Marker(
        markerId: gmap.MarkerId('flag_${_flagPoints.length - 1}'),
        position: p,
        icon: gmap.BitmapDescriptor.defaultMarkerWithHue(gmap.BitmapDescriptor.hueOrange),
        infoWindow: const gmap.InfoWindow(title: 'Checkpoint'),
      ),
    );
  }

  Future<void> _goToMe() async {
    if (_currentPosition == null) return;
    final target = gmap.LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

    // Desktop
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      _fmController.move(ll.LatLng(target.latitude, target.longitude), 15.0);
      return;
    }

    // Mobil/Web – Google
    if (_gController != null) {
      await _gController!.animateCamera(
        gmap.CameraUpdate.newCameraPosition(
          gmap.CameraPosition(target: target, zoom: 15),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Helper formázók
  // ---------------------------------------------------------------------------
  String _fmtKm(int meters) =>
      (meters / 1000).toStringAsFixed(meters >= 9950 ? 0 : 1) + ' km';
  String _fmtMin(int seconds) => '${(seconds / 60).round()} p';

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

    Widget map;
    if (isDesktop) {
      // -------------------- DESKTOP → OpenStreetMap (flutter_map) --------------------
      ll.LatLng toLl(gmap.LatLng p) => ll.LatLng(p.latitude, p.longitude);

      // A Google Polyline-ok átfordítása flutter_map polylinerekké
      final List<fm.Polyline> fmPolylines = _polylines.map((pl) {
        return fm.Polyline(
          points: pl.points.map(toLl).toList(),
          strokeWidth: pl.width.toDouble(),
          color: pl.color,
        );
      }).toList();

      // Markerek OSM-hez
      final List<fm.Marker> fmMarkers = [];

      for (final s in _stations) {
        fmMarkers.add(
          fm.Marker(
            point: toLl(s.location),
            width: 40,
            height: 40,
            child: const Icon(Icons.place, color: Colors.red),
          ),
        );
      }
      if (_currentPosition != null) {
        fmMarkers.add(
          fm.Marker(
            point: ll.LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            width: 40,
            height: 40,
            child: const Icon(Icons.my_location, color: Colors.blue),
          ),
        );
      }
      // kijelölt pontok – kisebb, számozott buborék
      for (var i = 0; i < _selectedPoints.length; i++) {
        fmMarkers.add(
          fm.Marker(
            point: toLl(_selectedPoints[i]),
            width: 28,
            height: 28,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF2E7D32),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        );
      }
      // checkpointok
      for (var i = 0; i < _flagPoints.length; i++) {
        fmMarkers.add(
          fm.Marker(
            point: toLl(_flagPoints[i]),
            width: 32,
            height: 32,
            child: const Icon(Icons.flag, color: Colors.orange, size: 28),
          ),
        );
      }

      map = fm.FlutterMap(
        mapController: _fmController,
        options: fm.MapOptions(
          initialCenter: ll.LatLng(nagyvazsony.latitude, nagyvazsony.longitude),
          initialZoom: 14,
          onTap: (tapPos, p) async {
            final idx = _selectedPoints.length + 1;
            setState(() {
              _selectedPoints.add(gmap.LatLng(p.latitude, p.longitude));
            });
          },
        ),
        children: [
          fm.TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
          ),
          // Waymarked Trails hiking (desktop)
          fm.TileLayer(
            urlTemplate: 'https://tile.waymarkedtrails.org/hiking/{z}/{x}/{y}.png',
          ),
          fm.PolylineLayer(polylines: fmPolylines),
          fm.MarkerLayer(markers: fmMarkers),
        ],
      );
    } else {
      // -------------------- MOBIL / WEB → Google Maps --------------------
      map = gmap.GoogleMap(
        initialCameraPosition: const gmap.CameraPosition(
          target: nagyvazsony,
          zoom: 14.0,
        ),
        mapType: gmap.MapType.terrain,
        myLocationButtonEnabled: true,
        myLocationEnabled: true,
        zoomControlsEnabled: true,
        markers: _markers,
        polylines: _polylines,
        tileOverlays: _tileOverlays, // overlay nélkül
        onMapCreated: (c) => _gController = c,
        onTap: (gmap.LatLng p) async {
          final idx = _selectedPoints.length + 1;
          setState(() {
            _selectedPoints.add(p);
          });
          final icon = await _numberedMarkerIcon(idx);
          setState(() {
            _markers.add(gmap.Marker(
              markerId: gmap.MarkerId('sel_$idx'),
              position: p,
              icon: icon,
              infoWindow: gmap.InfoWindow(title: 'Kijelölt pont $idx'),
            ));
          });
        },
      );
    }

    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: _isDark ? Brightness.dark : Brightness.light,
        ),
        useMaterial3: true,
      ),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 1,
          leading: IconButton(
            tooltip: 'Kamera / QR',
            icon: const Icon(Icons.photo_camera_outlined),
            onPressed: _scanQRCode,
          ),
          centerTitle: true,
          title: TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              backgroundColor: Theme.of(context).colorScheme.primary.withAlpha(20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              'Térkép',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 18,
              ),
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Jegyzetek',
              icon: const Icon(Icons.note_alt_outlined),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NotesScreen(currentPosition: _currentPosition),
                  ),
                );
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(child: map),

            // FELÜLSŐ fogantyú
            Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Center(
                  child: GestureDetector(
                    onTap: () => setState(() => _controlsCollapsed = !_controlsCollapsed),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Icon(
                        _controlsCollapsed ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                        size: 20,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Felső gombok – smooth fel/le
            Positioned(
              top: 56, // ne lógjon a fogantyúra
              left: 16,
              right: 16,
              child: SafeArea(
                bottom: false,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  offset: _controlsCollapsed ? const Offset(0, -1.0) : Offset.zero,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: _controlsCollapsed ? 0 : 1,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: _selectedPoints.length < 2 ? null : _buildRoutes,
                          icon: const Icon(Icons.alt_route),
                          label: const Text('Útvonal létrehozása'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _selectedPoints.isEmpty ? null : _clearSelections,
                          icon: const Icon(Icons.clear),
                          label: const Text('Kijelölések törlése'),
                        ),
                        const SizedBox(width: 12),
                        if (_routeChoices.isNotEmpty && _activeRouteIndex != null)
                          FilledButton.tonalIcon(
                            onPressed: _clearActiveRoute,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Útvonal törlése'),
                          ),
                        const SizedBox(width: 12),
                        if (_routeChoices.isNotEmpty && _activeRouteIndex != null)
                          FilledButton.icon(
                            onPressed: _saveRouteToNotes,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Mentés'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Alternatívák – vízszintes kártyalista (overflow-védelemmel)
            if (_routeChoices.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                top: 112,
                child: SafeArea(
                  bottom: false,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    offset: _controlsCollapsed ? const Offset(0, -1.0) : Offset.zero,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: _controlsCollapsed ? 0 : 1,
                      child: SizedBox(
                        height: 120, // magasabb doboz
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemCount: _routeChoices.length,
                          itemBuilder: (context, i) {
                            final c = _routeChoices[i];
                            final selected = _activeRouteIndex == i;
                            final dr = _driving;

                            final walkLine =
                                'Gyalog: ${_fmtMin(c.walkDurationSec)} • ${_fmtKm(c.walkDistanceMeters)}';

                            String carLine = 'Autó: nem elérhető';
                            if (dr != null && dr.available) {
                              carLine =
                                  'Autó: kb ${_fmtMin(dr.durationSec!)} • ${_fmtKm(dr.distanceMeters!)}';
                            }

                            return InkWell(
                              onTap: () => _selectRoute(i),
                              borderRadius: BorderRadius.circular(14),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary.withOpacity(.15)
                                      : Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: selected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).dividerColor,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                        blurRadius: 4, offset: Offset(0, 2), color: Colors.black12)
                                  ],
                                ),
                                width: 240,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Út ${i + 1}${c.summary.isNotEmpty ? ' • ${c.summary}' : ''}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: selected
                                            ? Theme.of(context).colorScheme.primary
                                            : Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(walkLine, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text(carLine, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Alsó fogantyú + MENÜ (4 gomb)
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: () => setState(() => _bottomCollapsed = !_bottomCollapsed),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Icon(
                            _bottomCollapsed
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 20,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedSlide(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      offset: _bottomCollapsed ? const Offset(0, 1.0) : Offset.zero,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 220),
                        opacity: _bottomCollapsed ? 0 : 1,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            border: Border.all(color: Theme.of(context).dividerColor),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(blurRadius: 8, color: Colors.black12)
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // 1) sötét mód
                              IconButton(
                                tooltip: _isDark ? 'Világos mód' : 'Sötét mód',
                                icon: const Icon(Icons.brightness_6),
                                onPressed: () => setState(() => _isDark = !_isDark),
                              ),
                              // 2) túra-réteg ki/be — CSAK DESKTOPON látványos
                              IconButton(
                                tooltip: _hikingVisible
                                    ? 'Túraútvonalak elrejtése'
                                    : 'Túraútvonalak mutatása',
                                icon: Icon(
                                  _hikingVisible ? Icons.terrain : Icons.terrain_outlined,
                                ),
                                onPressed: () => setState(() => _hikingVisible = !_hikingVisible),
                              ),
                              // 3) checkpoint
                              IconButton(
                                tooltip: 'Checkpoint hozzáadása',
                                icon: const Icon(Icons.flag),
                                onPressed: _addCheckpoint,
                              ),
                              // 4) ugrás a helyzetemre
                              IconButton(
                                tooltip: 'Ugrás a helyzetemre',
                                icon: const Icon(Icons.my_location),
                                onPressed: _goToMe,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Alsó koordinátasáv
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(77),
                  boxShadow: const [BoxShadow(blurRadius: 8, offset: Offset(0, -2))],
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.my_location, size: 18, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        _currentPosition != null
                            ? 'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}  •  Lng: ${_currentPosition!.longitude.toStringAsFixed(6)}'
                            : 'Helymeghatározás...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// JEGYZETEK
// -----------------------------------------------------------------------------
class NotesScreen extends StatefulWidget {
  final Position? currentPosition;
  final String? prefill; // előre kitöltött szöveg (Mentésből)

  const NotesScreen({
    super.key,
    required this.currentPosition,
    this.prefill,
  });

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final List<_Note> _notes = [];

  @override
  void initState() {
    super.initState();
    if (widget.prefill != null && widget.prefill!.isNotEmpty) {
      _ctrl.text = widget.prefill!;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _addNote() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _notes.insert(
        0,
        _Note(
          text: text,
          lat: widget.currentPosition?.latitude ?? 0,
          lng: widget.currentPosition?.longitude ?? 0,
          createdAt: DateTime.now(),
        ),
      );
      _ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jegyzetek')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _ctrl,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: 'Írj jegyzetet (útvonal, megállók, megjegyzések)…',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: _addNote,
                  icon: const Icon(Icons.send),
                ),
              ),
            ),
          ),
          if (_notes.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'Még nincs jegyzet.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemCount: _notes.length,
                itemBuilder: (context, i) {
                  final n = _notes[i];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.note_alt_outlined),
                      title: Text(n.text),
                      subtitle: Text(
                        '${n.createdAt.toLocal()}'
                        '\nLat: ${n.lat.toStringAsFixed(6)} • Lng: ${n.lng.toStringAsFixed(6)}',
                      ),
                      isThreeLine: true,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNote,
        icon: const Icon(Icons.add),
        label: const Text('Hozzáadás'),
      ),
    );
  }
}

class _Note {
  final String text;
  final double lat;
  final double lng;
  final DateTime createdAt;

  _Note({
    required this.text,
    required this.lat,
    required this.lng,
    required this.createdAt,
  });
}
