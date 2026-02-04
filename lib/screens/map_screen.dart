import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/trip.dart';
import '../models/station.dart';
import '../services/firestore_service.dart';
import '../services/geolocation_service.dart';

class MapScreen extends StatefulWidget {
  final Trip trip;

  const MapScreen({
    Key? key,
    required this.trip,
  }) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController _mapController;
  final FirestoreService _firestoreService = FirestoreService();
  final GeolocationService _geolocationService = GeolocationService();
  
  late Stream<List<Station>> _stationsStream;
  late Stream<Position> _positionStream;
  
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Position? _currentPosition;
  List<Station> _allStations = [];

  @override
  void initState() {
    super.initState();
    _initializeStreams();
  }

  void _initializeStreams() {
    _stationsStream = _firestoreService.watchStationsByTripId(widget.trip.id);
    _positionStream = _geolocationService.getPositionStream();
  }

  void _updateMarkers(List<Station> stations) {
    setState(() {
      _allStations = stations;
      _markers.clear();

      // Állomás markerek
      for (var station in stations) {
        _markers.add(
          Marker(
            markerId: MarkerId(station.id),
            position: LatLng(station.location.latitude, station.location.longitude),
            infoWindow: InfoWindow(title: station.name),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              station.isUnlocked ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueBlue,
            ),
            onTap: () {
              _showStationDetails(station);
            },
          ),
        );
      }

      // Felhasználó markere
      if (_currentPosition != null) {
        _markers.add(
          Marker(
            markerId: const MarkerId('current_position'),
            position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          ),
        );
      }
    });
  }

  void _updatePolylines(List<Station> stations) {
    if (stations.length < 2) return;

    final points = stations
        .map((s) => LatLng(s.location.latitude, s.location.longitude))
        .toList();

    setState(() {
      _polylines.clear();
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('trip_route'),
          points: points,
          color: Theme.of(context).primaryColor,
          width: 5,
        ),
      );
    });
  }

  void _showStationDetails(Station station) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              station.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(station.description),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(
                  context,
                  '/station_detail',
                  arguments: station,
                );
              },
              child: const Text('Részletek megtekintése'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.trip.name),
      ),
      body: Stack(
        children: [
          // Google Map
          StreamBuilder<Position>(
            stream: _positionStream,
            builder: (context, positionSnapshot) {
              return StreamBuilder<List<Station>>(
                stream: _stationsStream,
                builder: (context, stationsSnapshot) {
                  if (stationsSnapshot.hasData) {
                    _updateMarkers(stationsSnapshot.data!);
                    _updatePolylines(stationsSnapshot.data!);
                  }

                  if (positionSnapshot.hasData) {
                    _currentPosition = positionSnapshot.data;
                  }

                  final initialPosition = _allStations.isNotEmpty
                      ? LatLng(
                          _allStations[0].location.latitude,
                          _allStations[0].location.longitude,
                        )
                      : LatLng(widget.trip.startPoint.latitude,
                          widget.trip.startPoint.longitude);

                  return GoogleMap(
                    onMapCreated: (controller) {
                      _mapController = controller;
                    },
                    initialCameraPosition: CameraPosition(
                      target: initialPosition,
                      zoom: 15,
                    ),
                    markers: _markers,
                    polylines: _polylines,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                  );
                },
              );
            },
          ),
          // Info panel
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Felhasználó pozíciója',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_currentPosition != null)
                    Text(
                      '\, \',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }
}
