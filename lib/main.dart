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

// OpenRouteService (ORS) kulcs – túra útvonalakhoz (foot-hiking profil)
const String kOpenRouteServiceApiKey = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6Ijk5NzFiNWZkZGMxYjQwYmJhZjQ2MWVmYjkyZmY4YTEwIiwiaCI6Im11cm11cjY0In0=';

// Google Directions API kulcs (autós elérhetőséghez)
const String kGoogleDirectionsApiKey = 'IDE_A_GOOGLE_API_KULCSOD';

// Új: Google Maps dark style JSON (egyszerűsített)
const String _googleDarkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#242f3e"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#242f3e"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#746855"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#38414e"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2f3948"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#17263c"}]}
]
''';

// -----------------------------------------------------------------------------
// APP INDÍTÁS
// -----------------------------------------------------------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseConfig.initializeApp();
  runApp(const MyApp());
}

// -----------------------------------------------------------------------------
// ALKALMAZÁS
// -----------------------------------------------------------------------------
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ValueNotifier<bool> themeNotifier = ValueNotifier<bool>(false);

  @override
  void dispose() {
    themeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: themeNotifier,
      builder: (context, isDark, _) {
        return MaterialApp(
          title: 'Projekt',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.green, brightness: Brightness.light),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.green, brightness: Brightness.dark),
            useMaterial3: true,
          ),
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          home: SplashScreen(themeNotifier: themeNotifier),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// SPLASH SCREEN
// -----------------------------------------------------------------------------
class SplashScreen extends StatefulWidget {
  final ValueNotifier<bool> themeNotifier;
  const SplashScreen({super.key, required this.themeNotifier});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final Animation<Offset> _logoOffset;
  late final Animation<double> _logoOpacity;

  late final AnimationController _textController;
  late final Animation<Offset> _textOffset;
  late final Animation<double> _textOpacity;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _logoOffset = Tween<Offset>(begin: const Offset(0, 0.8), end: Offset.zero).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutCubic),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOut),
    );

    _textController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _textOffset = Tween<Offset>(begin: const Offset(0, 1.0), end: Offset.zero).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic),
    );
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );

    // Entrance: logo first, then text shortly after
    _logoController.forward();
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) _textController.forward();
    });

    // After loading, wait 2.5s then reverse: text first, then logo
    Future.delayed(const Duration(milliseconds: 2500 + 700), () {
      // ensure entrance finished (700ms), then wait 2.5s total from app start
      if (!mounted) return;
      _textController.reverse();
      Future.delayed(const Duration(milliseconds: 160), () {
        if (mounted) _logoController.reverse();
      });
    });

    // After animations finished, navigate to HomePage (placeholder)
    _logoController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => HomeScreen(themeNotifier: widget.themeNotifier)),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Háttérkép
          Positioned.fill(
            child: Image.asset(
              'assets/var.jpg',
              fit: BoxFit.cover,
            ),
          ),
          // Blur réteg
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
              child: Container(
                color: Colors.black.withOpacity(0.15), // enyhe sötét átfedés a kontraszt érdekében
              ),
            ),
          ),
          // Középre igazított logo + szöveg csúsztatással + elhalványítással
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    SlideTransition(
                      position: _logoOffset,
                      child: FadeTransition(
                        opacity: _logoOpacity,
                        child: Image.asset(
                          'assets/logo.png',
                          width: 140,
                          height: 140,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Szöveg
                    SlideTransition(
                      position: _textOffset,
                      child: FadeTransition(
                        opacity: _textOpacity,
                        child: Text(
                          'Túrázz Nagyvázsonyban',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.95),
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.35),
                                offset: const Offset(0, 2),
                                blurRadius: 4,
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
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Főoldal')),
      body: const Center(child: Text('Itt a fő alkalmazás.')),
    );
  }
}

// -----------------------------------------------------------------------------
// FŐ KÉPERNYŐ
// -----------------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  final ValueNotifier<bool> themeNotifier;
  HomeScreen({super.key, required this.themeNotifier});

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
 final DirectionsService _directions = DirectionsService(googleApiKey: kGoogleDirectionsApiKey,orsApiKey: kOpenRouteServiceApiKey,);

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

  // checkpointok
  // checkpointok (törölve a duplikált deklaráció; részletes tárolás alatta található)

  // térkép kontrollerek
  final fm.MapController _fmController = fm.MapController(); // desktop
  gmap.GoogleMapController? _gController;                    // mobil/web

  // zászló színek (hue-ok a Google Maps marker-hez) + emberi nevek
	final List<double> _flagHuePool = [
	  gmap.BitmapDescriptor.hueAzure,
	  gmap.BitmapDescriptor.hueOrange,
	  gmap.BitmapDescriptor.hueGreen,
	  gmap.BitmapDescriptor.hueYellow,
	  gmap.BitmapDescriptor.hueViolet,
	];
	final List<String> _flagColorNames = ['azure', 'orange', 'green', 'yellow', 'violet'];
	int _nextFlagHueIndex = 0;

	// tárolt zászló koordináták és hozzájuk rendelt hue-index
	final List<gmap.LatLng> _flagPoints = [];
	final List<double> _flagAssignedHues = [];
	final List<String> _flagAssignedNames = [];

  // Listen a theme changes to update Google map style
  void _onThemeChanged() => _applyMapStyle(widget.themeNotifier.value);

  Future<void> _applyMapStyle(bool isDark) async {
    if (_gController != null) {
      try {
        await _gController!.setMapStyle(isDark ? _googleDarkMapStyle : null);
      } catch (e) {
        debugPrint('Map style apply error: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // INIT/DISPOSE
  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _loadStations();
    _startPositionStream();
    widget.themeNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    widget.themeNotifier.removeListener(_onThemeChanged);
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

  // Új: checkpoint hozzáadása + jegyzet megnyitása előre kitöltve
	Future<void> _addCheckpointAndOpenNotes() async {
	  final gmap.LatLng? p = _currentPosition != null
	      ? gmap.LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
	      : (_selectedPoints.isNotEmpty ? _selectedPoints.last : null);
	  if (p == null) return;

	  // kiválasztott hue + név
	  final hue = _flagHuePool[_nextFlagHueIndex];
	  final name = _flagColorNames[_nextFlagHueIndex];
	  _nextFlagHueIndex = (_nextFlagHueIndex + 1) % _flagHuePool.length;

	  setState(() {
	    _flagPoints.add(p);
	    _flagAssignedHues.add(hue);
	    _flagAssignedNames.add(name);
	    // Google marker hozzáadása a térképhez (egyedi id)
	    final idx = _flagPoints.length - 1;
	    _markers.add(
	      gmap.Marker(
	        markerId: gmap.MarkerId('flag_$idx'),
	        position: p,
	        icon: gmap.BitmapDescriptor.defaultMarkerWithHue(hue),
	        infoWindow: gmap.InfoWindow(title: 'Checkpoint #${idx + 1}', snippet: name),
	      ),
	    );
	  });

    

	  // előre kitöltött jegyzet: koordináta, szín, idő
	  final now = DateTime.now();
	  final prefill = StringBuffer();
	  prefill.writeln('Checkpoint');
	  prefill.writeln('- Szín: $name');
	  prefill.writeln('- Lat: ${p.latitude.toStringAsFixed(6)}');
	  prefill.writeln('- Lng: ${p.longitude.toStringAsFixed(6)}');
	  prefill.writeln('- Idő: ${now.toLocal()}');
	  prefill.writeln('');
	  prefill.writeln('Megjegyzés:');

	  // Nyisd meg a jegyzetek képernyőt a zászló adataival
	  await Navigator.push(
	    context,
	    MaterialPageRoute(
	      builder: (_) => NotesScreen(
	        currentPosition: _currentPosition,
	        prefill: prefill.toString(),
	        flagLat: p.latitude,
	        flagLng: p.longitude,
	        flagColorName: name,
	      ),
	    ),
	  );
	}

  Future<void> _goToMe() async {
    if (_currentPosition == null) return;
    final target = gmap.LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );

    // Desktop (Windows / Linux / macOS) → flutter_map
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    if (isDesktop) {
      _fmController.move(
        ll.LatLng(target.latitude, target.longitude),
        15.0,
      );
      return;
    }

    // Mobil / Web → Google Maps
    if (_gController != null) {
      await _gController!.animateCamera(
        gmap.CameraUpdate.newCameraPosition(
          gmap.CameraPosition(
            target: target,
            zoom: 15,
          ),
        ),
      );
    }
  }

  

	// Új: törli az összes zászlót a térképről (jegyzeteket NEM törli)
	void _clearFlagsFromMap() {
	  setState(() {
	    // eltávolítjuk az összes 'flag_' marker-t
	    _markers.removeWhere((m) => m.markerId.value.startsWith('flag_'));
	    _flagPoints.clear();
	    _flagAssignedHues.clear();
	    _flagAssignedNames.clear();
	    // _nextFlagHueIndex marad, új zászlók folytatódnak a színsorral
	  });
	  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zászlók eltávolítva a térképről. (A jegyzetek megmaradnak.)')));
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

    // A teljes képernyő újrarajzolódik, amikor a themeNotifier változik
    return ValueListenableBuilder<bool>(
      valueListenable: widget.themeNotifier,
      builder: (context, isDark, _) {
        // Mapot itt építjük újra, hogy tile URL vagy Google stílus változzon
        Widget map;
        if (isDesktop) {
          // DESKTOP → OpenStreetMap (flutter_map) – sötét csempékkel dark módban
          ll.LatLng toLl(gmap.LatLng p) => ll.LatLng(p.latitude, p.longitude);

          final List<fm.Polyline> fmPolylines = _polylines.map((pl) {
            return fm.Polyline(
              points: pl.points.map(toLl).toList(),
              strokeWidth: pl.width.toDouble(),
              color: pl.color,
            );
          }).toList();

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

          final tileUrl = isDark
              ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png'
              : 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';

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
                urlTemplate: tileUrl,
                subdomains: const ['a', 'b', 'c'],
              ),
              // Waymarked Trails hiking (desktop)
                            // Waymarked Trails hiking (desktop) – csak ha világos mód és be van kapcsolva
              if (!isDark && _hikingVisible)
                fm.TileLayer(
                  urlTemplate: 'https://tile.waymarkedtrails.org/hiking/{z}/{x}/{y}.png',
                ),
              fm.PolylineLayer(polylines: fmPolylines),
              fm.MarkerLayer(markers: fmMarkers),
            ],
          );
        } else {
          // MOBIL / WEB → Google Maps
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
            tileOverlays: _tileOverlays,
            onMapCreated: (c) {
              _gController = c;
              // alkalmazzuk a megfelelő map style az aktuális témához
              _applyMapStyle(isDark);
            },
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

        return Scaffold(
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
                          // sötétebb, jól látható ikon
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.85),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Felső gombok + Alternatívák – 2x2 gombrács, alatta kompakt útvonal-lista
              Positioned(
                top: 56,
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 2x2 gombrács (két sor, két oszlop)
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  style: ButtonStyle(
                                    minimumSize: MaterialStateProperty.all(const Size(0, 48)),
                                    padding: MaterialStateProperty.all(const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                                    // mindig zöld megjelenés; ikon/szöveg mindig fehér
                                    backgroundColor: MaterialStateProperty.all(const Color(0xFF2E7D32)),
                                    foregroundColor: MaterialStateProperty.all(Colors.white),
                                    elevation: MaterialStateProperty.all(0),
                                    shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                  ),
                                  onPressed: _selectedPoints.length < 2 ? null : _buildRoutes,
                                  icon: const Icon(Icons.alt_route, size: 18),
                                  label: const Text('Útvonal\nlétrehozása', textAlign: TextAlign.center),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  style: ButtonStyle(
                                    minimumSize: MaterialStateProperty.all(const Size(0, 48)),
                                    padding: MaterialStateProperty.all(const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                                    backgroundColor: MaterialStateProperty.all(Color(0xFF2E7D32).withOpacity(0.08)),
                                    elevation: MaterialStateProperty.all(0),
                                    foregroundColor: MaterialStateProperty.all(Theme.of(context).colorScheme.onSurface),
                                    side: MaterialStateProperty.all(BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.9))),
                                    shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                  ),
                                  onPressed: _selectedPoints.isEmpty ? null : _clearSelections,
                                  icon: const Icon(Icons.clear, size: 18),
                                  label: const Text('Kijelölések\ntörlése', textAlign: TextAlign.center),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  style: ButtonStyle(
                                    minimumSize: MaterialStateProperty.all(const Size(0, 44)),
                                    padding: MaterialStateProperty.all(const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                                    backgroundColor: MaterialStateProperty.all(Color(0xFF2E7D32).withOpacity(0.08)),
                                    elevation: MaterialStateProperty.all(0),
                                    foregroundColor: MaterialStateProperty.all(Theme.of(context).colorScheme.onSurface),
                                    side: MaterialStateProperty.all(BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.9))),
                                    shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                  ),
                                  onPressed: _routeChoices.isNotEmpty && _activeRouteIndex != null ? _clearActiveRoute : null,
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  label: const Text('Útvonal\ntörlése', textAlign: TextAlign.center),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  style: ButtonStyle(
                                    minimumSize: MaterialStateProperty.all(const Size(0, 44)),
                                    padding: MaterialStateProperty.all(const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                                    backgroundColor: MaterialStateProperty.all(Color(0xFF2E7D32).withOpacity(0.08)),
                                    elevation: MaterialStateProperty.all(0),
                                    foregroundColor: MaterialStateProperty.all(Theme.of(context).colorScheme.onSurface),
                                    side: MaterialStateProperty.all(BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.9))),
                                    shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                  ),
                                  onPressed: _routeChoices.isNotEmpty && _activeRouteIndex != null ? _saveRouteToNotes : null,
                                  icon: const Icon(Icons.save_outlined, size: 18),
                                  label: const Text('Mentés', textAlign: TextAlign.center),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // Alternatívák – kompakt, rövid kártyák (mindig a gombok alatt; nem takarják a térképet)
                          if (_routeChoices.isNotEmpty)
                            SizedBox(
                              height: 86, // még kisebb, hogy ne takarja a térképet
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 0),
                                scrollDirection: Axis.horizontal,
                                separatorBuilder: (_, __) => const SizedBox(width: 10),
                                itemCount: _routeChoices.length,
                                itemBuilder: (context, i) {
                                  final c = _routeChoices[i];
                                  final selected = _activeRouteIndex == i;
                                  final walkLine = 'Gyalog: ${_fmtMin(c.walkDurationSec)} • ${_fmtKm(c.walkDistanceMeters)}';
                                  return InkWell(
                                    onTap: () {
                                      _selectRoute(i);
                                      // ha szeretnéd, hogy a gombok eltűnjenek a választáskor:
                                      // setState(() => _controlsCollapsed = true);
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 160),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? Theme.of(context).colorScheme.primary.withOpacity(.12)
                                            : Theme.of(context).colorScheme.surface,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor),
                                        boxShadow: const [BoxShadow(blurRadius: 2, offset: Offset(0, 1), color: Colors.black12)],
                                      ),
                                      width: 170,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Út ${i + 1}${c.summary.isNotEmpty ? ' • ${c.summary}' : ''}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13.5,
                                              color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(walkLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Alsó fogantyú + MENÜ (4 gomb) + koordinátasáv
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  top: false,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    decoration: BoxDecoration(
                      color: _bottomCollapsed ? Colors.transparent : Theme.of(context).colorScheme.surface,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                      boxShadow: _bottomCollapsed ? null : const [BoxShadow(blurRadius: 8, color: Colors.black12)],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Fogantyú – mindig látható (kívül az animált gombrészen)
                        Center(
                          child: GestureDetector(
                            onTap: () => setState(() => _bottomCollapsed = !_bottomCollapsed),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: Icon(
                                _bottomCollapsed ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                size: 20,
                                // ha össze van húzva (gombok rejtve), legyen erősebb a nyíl
                                color: _bottomCollapsed
                                    ? Theme.of(context).colorScheme.onSurface.withOpacity(0.95)
                                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.65),
                              ),
                            ),
                          ),
                        ),

                        // Gombok – ez a rész (és a háttér) eltűnik, amikor _bottomCollapsed == true
                        AnimatedSlide(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeInOut,
                          offset: _bottomCollapsed ? const Offset(0, 1.0) : Offset.zero,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 220),
                            opacity: _bottomCollapsed ? 0 : 1,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Center(
                                      child: IconButton(
                                        tooltip: isDark ? 'Világos mód' : 'Sötét mód',
                                        icon: Icon(Icons.brightness_6, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                                        onPressed: () => widget.themeNotifier.value = !widget.themeNotifier.value,
                                      ),
                                    ),
                                  ),
                                  Container(width: 1, height: 24, color: Theme.of(context).colorScheme.outline),
                                  Expanded(
                                    child: Center(
                                      child: IconButton(
                                        tooltip: _hikingVisible ? 'Túraútvonalak elrejtése' : 'Túraútvonalak mutatása',
                                        icon: Icon(_hikingVisible ? Icons.terrain : Icons.terrain_outlined, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                                        onPressed: () => setState(() => _hikingVisible = !_hikingVisible),
                                      ),
                                    ),
                                  ),
                                  Container(width: 1, height: 24, color: Theme.of(context).colorScheme.outline),
                                  Expanded(
                                    child: Center(
                                      child: GestureDetector(
                                        onLongPress: _clearFlagsFromMap,
                                        child: IconButton(
                                          tooltip: 'Checkpoint hozzáadása (hosszú: eltávolít minden zászlót)',
                                          icon: Icon(Icons.flag, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                                          onPressed: _addCheckpointAndOpenNotes,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Container(width: 1, height: 24, color: Theme.of(context).colorScheme.outline),
                                  Expanded(
                                    child: Center(
                                      child: IconButton(
                                        tooltip: 'Ugrás a helyzetemre',
                                        icon: Icon(Icons.my_location, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                                        onPressed: _goToMe,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // elválasztó vonal – csak ha nem össze van húzva
                        if (!_bottomCollapsed)
                          Container(height: 1, color: Theme.of(context).colorScheme.outline, margin: const EdgeInsets.symmetric(horizontal: 8)),

                        // Koordinátasáv – mindig látható (saját, kicsit sötétebb háttér)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
                            borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.my_location, size: 18, color: Theme.of(context).colorScheme.onSurface),
                              const SizedBox(width: 8),
                              Text(
                                _currentPosition != null
                                    ? 'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}  •  Lng: ${_currentPosition!.longitude.toStringAsFixed(6)}'
                                    : 'Helymeghatározás...',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Jegyzetek
// -----------------------------------------------------------------------------
class NotesScreen extends StatefulWidget {
  final Position? currentPosition;
  final String? prefill;
  final double? flagLat;
  final double? flagLng;
  final String? flagColorName;

  const NotesScreen({
    super.key,
    required this.currentPosition,
    this.prefill,
    this.flagLat,
    this.flagLng,
    this.flagColorName,
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

    // Ha zászló adatai érkeztek, használjuk azokat; különben currentPosition-t
    final lat = widget.flagLat ?? widget.currentPosition?.latitude ?? 0.0;
    final lng = widget.flagLng ?? widget.currentPosition?.longitude ?? 0.0;
    final colorName = widget.flagColorName ?? '';

    setState(() {
      _notes.insert(
        0,
        _Note(
          text: text,
          lat: lat,
          lng: lng,
          color: colorName,
          createdAt: DateTime.now(),
        ),
      );
      _ctrl.clear();
    });

    // visszalépés után a HomeScreen megőrzi a jegyzeteket csak lokálisan ebben a képernyőben.
    // (ha szeretnéd, ide küldhetünk Firestore-ba is mentést - külön kérés alapján)
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
                        '\nLat: ${n.lat.toStringAsFixed(6)} • Lng: ${n.lng.toStringAsFixed(6)}'
                        '${n.color.isNotEmpty ? '\nSzín: ${n.color}' : ''}',
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
  final String color;
  final DateTime createdAt;

  _Note({
    required this.text,
    required this.lat,
    required this.lng,
    required this.color,
    required this.createdAt,
  });
}
