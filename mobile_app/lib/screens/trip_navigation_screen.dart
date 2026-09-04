import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/location_service.dart';
import '../widgets/station_detail_sheet.dart';
import 'camera_screen.dart';

/// Google Maps-szerű túranavigáció: élő GPS-pozíció, a kiválasztott túra
/// útvonala, és a következő állomáshoz vezető irány + távolság.
///
/// Az állomás "teljesítése" a helyszíni QR-beolvasással történik (pontot is
/// csak az ad). A "Következő" gomb emiatt szándékosan NEM egy szabad
/// lapozó: csak akkor engedélyezett, ha a felhasználó ténylegesen a
/// célállomás közelébe ért (GPS), vagy a QR-beolvasás már valóban
/// teljesítette azt — így a túra nem "gombnyomogatással" végigjátszható.
class TripNavigationScreen extends StatefulWidget {
  const TripNavigationScreen({
    super.key,
    required this.tripName,
    required this.stations,
    required this.routePoints,
    required this.completedIds,
  });

  final String tripName;

  /// A túra állomásai sorrendben — a hívó (térkép képernyő) már ehhez a
  /// túrához szűrve és a `tripOrder`-je szerint rendezve adja át (lásd
  /// `station_trips.dart`), ezért itt csak a sorrendet kell tartani.
  final List<Map<String, dynamic>> stations;

  /// Az állomásokat összekötő útvonal pontjai (a turistaút polyline-ja).
  final List<LatLng> routePoints;

  /// A már teljesített állomások azonosítói – ezeket "elértnek" tekintjük, így
  /// a navigáció az első még hátralévő állomásra indul.
  final Set<String> completedIds;

  @override
  State<TripNavigationScreen> createState() => _TripNavigationScreenState();
}

class _TripNavigationScreenState extends State<TripNavigationScreen> {
  /// Ilyen közelségtől (méter) tekintjük az állomást elértnek.
  static const double _arrivalThresholdMeters = 30;

  GoogleMapController? _controller;
  StreamSubscription<Position>? _positionSub;

  Position? _position;
  LocationReadyState _readyState = LocationReadyState.ready;
  bool _initializing = true;

  bool _followUser = true;
  bool _arrivalAnnounced = false;

  final Set<String> _reachedIds = <String>{};
  int _targetIndex = 0;
  bool _allDone = false;

  @override
  void initState() {
    super.initState();
    _reachedIds.addAll(widget.completedIds);
    final firstPending = _firstUnreachedIndex();
    if (firstPending == null) {
      _allDone = true;
      _targetIndex = 0;
    } else {
      _targetIndex = firstPending;
    }
    _startTracking();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

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

  String _stationName(Map<String, dynamic> station) =>
      station['name']?.toString() ?? 'Állomás';

  int? _firstUnreachedIndex() {
    for (var i = 0; i < widget.stations.length; i += 1) {
      final id = widget.stations[i]['id'] as String?;
      if (id == null || !_reachedIds.contains(id)) return i;
    }
    return null;
  }

  Map<String, dynamic>? get _targetStation {
    if (_allDone || _targetIndex >= widget.stations.length) return null;
    return widget.stations[_targetIndex];
  }

  Future<void> _startTracking() async {
    final state = await LocationService.ensureReady();
    if (!mounted) return;
    setState(() {
      _readyState = state;
      _initializing = false;
    });
    if (state != LocationReadyState.ready) return;

    _positionSub = LocationService.positionStream().listen(
      _onPosition,
      onError: (_) {},
    );
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    setState(() => _position = position);

    if (_followUser) {
      _controller?.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
      );
    }

    final target = _targetStation;
    if (target == null) return;
    final targetPoint = _stationPoint(target);
    if (targetPoint == null) return;

    final distance = LocationService.distanceMeters(
      position.latitude,
      position.longitude,
      targetPoint.latitude,
      targetPoint.longitude,
    );

    if (distance <= _arrivalThresholdMeters && !_arrivalAnnounced) {
      _arrivalAnnounced = true;
      HapticFeedback.mediumImpact();
      setState(() {});
    }
  }

  void _advanceTarget() {
    final target = _targetStation;
    if (target != null) {
      final id = target['id'] as String?;
      if (id != null) _reachedIds.add(id);
    }
    final next = _firstUnreachedIndex();
    setState(() {
      _arrivalAnnounced = false;
      if (next == null) {
        _allDone = true;
      } else {
        _targetIndex = next;
      }
    });
  }

  /// Megnyitja a QR-beolvasót, hogy a felhasználó ténylegesen teljesítse a
  /// célállomást (pontot is ez ad). Visszatéréskor a szerverről frissítjük a
  /// valós teljesítést, és csak akkor lépünk tovább, ha az ténylegesen
  /// megtörtént — így ez a képernyő nem kerülhető meg puszta kattintással.
  Future<void> _scanAtStation() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
    if (!mounted) return;
    await _refreshCompletionFromServer();
  }

  Future<void> _refreshCompletionFromServer() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('user_progress')
          .doc(uid)
          .get();
      final completed = Set<String>.from(
        (doc.data()?['completedStations'] as List?) ?? const [],
      );
      if (!mounted) return;
      setState(() {
        _reachedIds.addAll(completed);
        final next = _firstUnreachedIndex();
        _arrivalAnnounced = false;
        if (next == null) {
          _allDone = true;
        } else {
          _targetIndex = next;
        }
      });
    } catch (_) {
      // Nincs hálózat: a helyi állapot marad, legközelebb újrapróbáljuk.
    }
  }

  void _recenter() {
    final position = _position;
    setState(() => _followUser = true);
    if (position != null) {
      _controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 17,
          ),
        ),
      );
    }
  }

  double? _distanceToTarget() {
    final position = _position;
    final target = _targetStation;
    if (position == null || target == null) return null;
    final point = _stationPoint(target);
    if (point == null) return null;
    return LocationService.distanceMeters(
      position.latitude,
      position.longitude,
      point.latitude,
      point.longitude,
    );
  }

  /// Irány (radián, észak-felül térképhez) a felhasználótól a célállomásig.
  double? _bearingToTarget() {
    final position = _position;
    final target = _targetStation;
    if (position == null || target == null) return null;
    final point = _stationPoint(target);
    if (point == null) return null;
    final deg = LocationService.bearing(
      position.latitude,
      position.longitude,
      point.latitude,
      point.longitude,
    );
    return deg * math.pi / 180.0;
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    final rounded = (meters / 5).round() * 5;
    return '$rounded m';
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    for (var i = 0; i < widget.stations.length; i += 1) {
      final station = widget.stations[i];
      final point = _stationPoint(station);
      if (point == null) continue;
      final id = station['id'] as String? ?? 'st_$i';
      final isTarget = !_allDone && i == _targetIndex;
      final reached = _reachedIds.contains(id);
      final hue = isTarget
          ? BitmapDescriptor.hueOrange
          : reached
          ? BitmapDescriptor.hueGreen
          : BitmapDescriptor.hueViolet;
      markers.add(
        Marker(
          markerId: MarkerId(id),
          position: point,
          zIndexInt: isTarget ? 2 : 1,
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          infoWindow: InfoWindow(
            title: '${i + 1}. ${_stationName(station)}',
            snippet: isTarget
                ? 'Következő állomás'
                : reached
                ? 'Elérve'
                : 'Hátralévő',
          ),
          onTap: () => showStationDetailSheet(
            context,
            station: station,
            isCompleted: widget.completedIds.contains(id),
          ),
        ),
      );
    }
    return markers;
  }

  Set<Polyline> _buildPolylines() {
    if (widget.routePoints.length < 2) return {};
    return {
      Polyline(
        polylineId: const PolylineId('nav-route'),
        points: widget.routePoints,
        color: const Color(0xFF8D6E63),
        width: 6,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final stationPoints = widget.stations
        .map(_stationPoint)
        .whereType<LatLng>()
        .toList();
    final firstStation = stationPoints.isNotEmpty ? stationPoints.first : null;
    final initialTarget = _position != null
        ? LatLng(_position!.latitude, _position!.longitude)
        : (firstStation ?? const LatLng(47.06, 17.715));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tripName),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : _readyState != LocationReadyState.ready
          ? _buildPermissionMessage()
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: initialTarget,
                    zoom: 16,
                  ),
                  markers: _buildMarkers(),
                  polylines: _buildPolylines(),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: true,
                  onMapCreated: (controller) => _controller = controller,
                  onCameraMoveStarted: () {
                    // A felhasználó kézzel mozgatta a térképet → követés le.
                    if (_followUser) setState(() => _followUser = false);
                  },
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: _buildNavCard(),
                ),
                Positioned(
                  right: 12,
                  bottom: 118,
                  child: FloatingActionButton(
                    heroTag: 'recenter',
                    mini: true,
                    backgroundColor: _followUser
                        ? const Color(0xFF2E7D32)
                        : Colors.white,
                    foregroundColor: _followUser
                        ? Colors.white
                        : const Color(0xFF2E7D32),
                    onPressed: _recenter,
                    child: const Icon(Icons.my_location),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 16,
                  child: _buildBottomBar(),
                ),
              ],
            ),
    );
  }

  Widget _buildNavCard() {
    if (_allDone) {
      return _navShell(
        color: const Color(0xFF2E7D32),
        child: const Row(
          children: [
            Icon(Icons.emoji_events, color: Colors.white, size: 30),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Végigjártad a túrát! 🎉',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final target = _targetStation;
    if (target == null) return const SizedBox.shrink();
    final distance = _distanceToTarget();
    final bearing = _bearingToTarget();
    final arrived = _arrivalAnnounced;

    return _navShell(
      color: arrived ? const Color(0xFF2E7D32) : Colors.white,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: arrived
                  ? Colors.white.withValues(alpha: 0.2)
                  : const Color(0xFFEEF4EA),
              shape: BoxShape.circle,
            ),
            child: arrived
                ? const Icon(Icons.flag, color: Colors.white)
                : Transform.rotate(
                    angle: bearing ?? 0,
                    child: const Icon(
                      Icons.navigation,
                      color: Color(0xFF2E7D32),
                      size: 26,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  arrived ? 'Megérkeztél ide:' : 'Következő állomás',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: arrived ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_targetIndex + 1}. ${_stationName(target)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: arrived ? Colors.white : const Color(0xFF1B4332),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            arrived
                ? 'itt'
                : distance != null
                ? _formatDistance(distance)
                : '—',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: arrived ? Colors.white : const Color(0xFF2E7D32),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navShell({required Color color, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildBottomBar() {
    final reachedCount = widget.stations
        .where((s) => _reachedIds.contains(s['id'] as String? ?? ''))
        .length;
    final total = widget.stations.length;
    final target = _targetStation;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.route, size: 18, color: Color(0xFF8D6E63)),
              const SizedBox(width: 8),
              Text(
                'Haladás: $reachedCount / $total állomás',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3E2723),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : reachedCount / total,
              minHeight: 7,
              backgroundColor: const Color(0xFFE8E0D2),
              color: const Color(0xFF2E7D32),
            ),
          ),
          const SizedBox(height: 12),
          if (!_allDone)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _scanAtStation,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('QR beolvasása – állomás teljesítése'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: target == null
                      ? null
                      : () => showStationDetailSheet(
                          context,
                          station: target,
                          isCompleted: widget.completedIds.contains(
                            target['id'] as String? ?? '',
                          ),
                        ),
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Állomás'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2E7D32),
                    side: const BorderSide(color: Color(0xFF2E7D32)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  // Szándékosan NEM szabadon kattintható: csak akkor
                  // engedélyezett, ha a GPS ténylegesen a célállomás
                  // közelébe (30 m) ért — a pontot ettől függetlenül
                  // csak a QR-beolvasás adja.
                  onPressed: (_allDone || !_arrivalAnnounced)
                      ? null
                      : _advanceTarget,
                  icon: const Icon(Icons.skip_next),
                  label: const Text('Tovább (helyszínen vagyok)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2E7D32),
                    side: const BorderSide(color: Color(0xFF2E7D32)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionMessage() {
    final deniedForever = _readyState == LocationReadyState.deniedForever;
    final serviceOff = _readyState == LocationReadyState.serviceDisabled;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            serviceOff ? Icons.location_off : Icons.location_disabled,
            size: 56,
            color: const Color(0xFF8D6E63),
          ),
          const SizedBox(height: 16),
          Text(
            serviceOff
                ? 'A helymeghatározás ki van kapcsolva'
                : 'Helyhozzáférés szükséges a navigációhoz',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            serviceOff
                ? 'Kapcsold be a helymeghatározást (GPS-t), majd próbáld újra.'
                : deniedForever
                ? 'A helyhozzáférést véglegesen letiltottad. Engedélyezd az alkalmazás beállításainál.'
                : 'A navigációhoz engedélyezned kell, hogy az app hozzáférjen a helyzetedhez.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, height: 1.4),
          ),
          const SizedBox(height: 20),
          if (deniedForever)
            FilledButton.icon(
              onPressed: () => Geolocator.openAppSettings(),
              icon: const Icon(Icons.settings),
              label: const Text('Beállítások megnyitása'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
              ),
            )
          else
            FilledButton.icon(
              onPressed: () {
                setState(() => _initializing = true);
                _startTracking();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Újrapróbálás'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
              ),
            ),
        ],
      ),
    );
  }
}
