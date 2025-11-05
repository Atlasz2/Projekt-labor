import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:geolocator/geolocator.dart';
// ...existing code...
import 'models/point_of_interest.dart';
import 'services/api_service.dart';

import 'config/firebase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseConfig.initializeApp();
  runApp(const TuraApp());
}

class TuraApp extends StatelessWidget {
  const TuraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Túra',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Position? _currentPosition;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  List<PointOfInterest> _stations = [];
  int? _currentTripId;
  final ApiService api = ApiService('http://localhost:5000'); // Itt állítsd be a backend címet

  // Nagyvázsony (HU) – térkép középpont
  static const LatLng nagyvazsony = LatLng(46.9890, 17.6990);

  @override
  void initState() {
    super.initState();
    _loadStations();
    _getCurrentLocation();
  }

  Future<void> _loadStations() async {
    try {
      // Trip lekérése
      final trips = await api.getTrips();
      if (trips.isNotEmpty) {
        _currentTripId = trips.first.id;
        // Állomások lekérése
        final stations = await api.getPointsOfInterest(_currentTripId!);
        setState(() {
          _stations = stations;
          _updateMarkers();
          final pathPoints = stations.map((s) => LatLng(s.latitude, s.longitude)).toList();
          _updatePath(pathPoints);
        });
      }
    } catch (e) {
      debugPrint('Hiba az állomások betöltésekor: $e');
    }
  }

  void _updatePath(List<LatLng> pathPoints) {
    setState(() {
      _polylines.clear();
      if (pathPoints.isNotEmpty) {
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('trip_path'),
            points: pathPoints,
            color: Colors.blue,
            width: 5,
          ),
        );
      }
    });
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Helymeghatározás szolgáltatás nincs bekapcsolva
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Helymeghatározás kikapcsolva'),
            content: const Text('Kérlek, kapcsold be a helymeghatározást a telefon beállításaiban.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // Felhasználó elutasította az engedélyt
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Helymeghatározás letiltva'),
              content: const Text('Az alkalmazás megfelelő működéséhez szükség van a helymeghatározás engedélyezésére.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        // A felhasználó véglegesen letiltotta az engedélyt
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Helymeghatározás letiltva'),
            content: const Text('A helymeghatározás véglegesen le van tiltva. Kérlek, engedélyezd a telefon beállításaiban.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      // Ha minden engedély rendben van, lekérjük a pozíciót
      if (permission == LocationPermission.whileInUse || 
          permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        setState(() {
          _currentPosition = position;
          _updateMarkers();
        });
      }
    } catch (e) {
      debugPrint('Hiba a helymeghatározáskor: $e');
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Hiba történt'),
          content: Text('Nem sikerült lekérni a helyzetet: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _updateMarkers() {
    _markers.clear();
    
    // Állomások markerjeinek hozzáadása
    for (var station in _stations) {
      _markers.add(
        Marker(
          markerId: MarkerId(station.id.toString()),
          position: LatLng(station.latitude, station.longitude),
          infoWindow: InfoWindow(
            title: station.description ?? '',
            snippet: station.crybcodeIdentifier ?? '',
          ),
        ),
      );
    }

    // Aktuális pozíció markerjének hozzáadása
    if (_currentPosition != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Jelenlegi pozíció'),
        ),
      );
    }
  }

  Future<void> _scanQRCode() async {
    try {
      Navigator.push(
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
                    // QR kód ellenőrzése és fun fact megjelenítése
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
      (s) => s.crybcodeIdentifier == code,
      orElse: () => throw Exception('Ismeretlen QR kód'),
    );

    Navigator.pop(context); // Scanner bezárása
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(station.description ?? ''),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(station.description ?? ''),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Bezárás'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // FELSŐ NAVBAR
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 1,
        // bal oldal – kamera ikon most csak üzenetet mutat
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
            backgroundColor:
                Theme.of(context).colorScheme.primary.withAlpha(20),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  builder: (_) => NotesScreen(
                    currentPosition: _currentPosition,
                  ),
                ),
              );
            },
          ),
        ],
      ),

          // KÖZÉP: Google Térkép + overlay elemek
      body: Stack(
        children: [
          // A TÉRKÉP – Nagyvázsony középre állítva
          AbsorbPointer(
            absorbing: false,
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: nagyvazsony,
                zoom: 14.0,
                tilt: 0,
                bearing: 0,
              ),
              mapType: MapType.terrain,
              myLocationButtonEnabled: true,
              myLocationEnabled: true,
              zoomControlsEnabled: true,
              zoomGesturesEnabled: true,
              liteModeEnabled: false,
              indoorViewEnabled: true,
              trafficEnabled: false,
              buildingsEnabled: true,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            compassEnabled: true,
            mapToolbarEnabled: false,
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (GoogleMapController controller) async {
              // A térkép létrejött
              await Future.delayed(const Duration(milliseconds: 100));
              setState(() {});
            },
          )),
          // FELÜLET a térkép fölött – „Útvonal indítása" demo
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: SafeArea(
              bottom: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Útvonal indítása (demo)'),
                  ),
                ],
              ),
            ),
          ),

          // ALSÓ „FOOTER” – koordináták
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
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
    );
  }
}

// ————————————————————————————————————————————————
// JEGYZETEK képernyő – változatlan
class NotesScreen extends StatefulWidget {
  final Position? currentPosition;

  const NotesScreen({
    super.key,
    required this.currentPosition,
  });

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final List<_Note> _notes = [];

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
              maxLines: 3,
              decoration: InputDecoration(
                hintText:
                    'Írj jegyzetet (pl. helyzet, terep, koordináták, stb.)',
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
