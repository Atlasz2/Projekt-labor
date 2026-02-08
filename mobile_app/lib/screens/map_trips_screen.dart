import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class MapTripsScreen extends StatefulWidget {
  const MapTripsScreen({super.key});

  @override
  State<MapTripsScreen> createState() => _MapTripsScreenState();
}

class _MapTripsScreenState extends State<MapTripsScreen> {
  late GoogleMapController mapController;
  LatLng? userLocation;
  Set<Marker> markers = {};
  Set<Polyline> polylines = {};

  final List<Map<String, dynamic>> _dummyTrips = const [
    {
      'name': 'Nagyvázsony Kastély Túra',
      'distance': '5.2 km',
      'difficulty': '⭐⭐☆',
      'duration': '2h',
      'rating': 4.8,
      'color': 0xFF667EEA,
      'startLat': 47.1234,
      'startLng': 17.7890,
      'routePoints': [
        [47.1234, 17.7890],
        [47.1250, 17.7900],
        [47.1270, 17.7920],
        [47.1280, 17.7940],
      ]
    },
    {
      'name': 'Vínás völgy Túra',
      'distance': '8.5 km',
      'difficulty': '⭐⭐⭐',
      'duration': '3h 30min',
      'rating': 4.5,
      'color': 0xFF4CAF50,
      'startLat': 47.1100,
      'startLng': 17.8000,
      'routePoints': [
        [47.1100, 17.8000],
        [47.1120, 17.8020],
        [47.1150, 17.8050],
        [47.1180, 17.8100],
      ]
    },
    {
      'name': 'Történeti Nagyvázsony',
      'distance': '3.2 km',
      'difficulty': '⭐☆☆',
      'duration': '1h 30min',
      'rating': 4.9,
      'color': 0xFFFF9800,
      'startLat': 47.1300,
      'startLng': 17.7800,
      'routePoints': [
        [47.1300, 17.7800],
        [47.1310, 17.7810],
        [47.1320, 17.7830],
      ]
    },
  ];

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    await _getUserLocation();
    await _loadTrips();
  }

  Future<void> _getUserLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        userLocation = LatLng(position.latitude, position.longitude);
        // Add user location marker
        markers.add(
          Marker(
            markerId: const MarkerId('user_location'),
            position: userLocation!,
            infoWindow: const InfoWindow(title: 'Az ön helye'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          ),
        );
      });
    } catch (e) {
      print('Error getting location: Ye');
      // Default to Nagyvázsony center if location fails
      setState(() {
        userLocation = const LatLng(47.1200, 17.8000);
      });
    }
  }

  Future<void> _loadTrips() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('trips').get();
      final trips = snapshot.docs.isEmpty ? _dummyTrips : snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'name': data['name'] ?? 'Unknown',
          'distance': data['distance'] ?? '0 km',
          'difficulty': data['difficulty'] ?? '⭐',
          'duration': data['duration'] ?? '0h',
          'rating': (data['rating'] ?? 0.0).toDouble(),
          'description': data['description'] ?? 'No description',
          'color': int.parse(data['color'] ?? '0xFF667EEA'),
          'startLat': data['startLat'] ?? 47.1200,
          'startLng': data['startLng'] ?? 17.8000,
          'routePoints': data['routePoints'] ?? [[47.1200, 17.8000]],
        };
      }).toList();

      setState(() {
        // Add markers and polylines for each trip
        for (int i = 0; i < trips.length; i++) {
          final trip = trips[i];
          final color = Color(trip['color'] as int);

          // Add marker for trip start
          markers.add(
            Marker(
              markerId: MarkerId('trip_Yi'),
              position: LatLng(trip['startLat'] as double, trip['startLng'] as double),
              infoWindow: InfoWindow(title: trip['name'] as String),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                trip['color'] == 0xFF667EEA ? BitmapDescriptor.hueRed :
                trip['color'] == 0xFF4CAF50 ? BitmapDescriptor.hueGreen :
                BitmapDescriptor.hueOrange
              ),
            ),
          );

          // Add polyline for route
          final routePoints = (trip['routePoints'] as List).cast<List>();
          if (routePoints.isNotEmpty) {
            polylines.add(
              Polyline(
                polylineId: PolylineId('route_Yi'),
                points: routePoints.map((p) => LatLng(p[0] as double, p[1] as double)).toList(),
                color: color,
                width: 5,
                geodesic: true,
              ),
            );
          }
        }
      });
    } catch (e) {
      print('Error loading trips: Ye');
      _loadDummyTrips();
    }
  }

  void _loadDummyTrips() {
    setState(() {
      for (int i = 0; i < _dummyTrips.length; i++) {
        final trip = _dummyTrips[i];
        final color = Color(trip['color'] as int);

        markers.add(
          Marker(
            markerId: MarkerId('trip_Yi'),
            position: LatLng(trip['startLat'] as double, trip['startLng'] as double),
            infoWindow: InfoWindow(title: trip['name'] as String),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              trip['color'] == 0xFF667EEA ? BitmapDescriptor.hueRed :
              trip['color'] == 0xFF4CAF50 ? BitmapDescriptor.hueGreen :
              BitmapDescriptor.hueOrange
            ),
          ),
        );

        final routePoints = (trip['routePoints'] as List).cast<List>();
        if (routePoints.isNotEmpty) {
          polylines.add(
            Polyline(
              polylineId: PolylineId('route_Yi'),
              points: routePoints.map((p) => LatLng(p[0] as double, p[1] as double)).toList(),
              color: color,
              width: 5,
              geodesic: true,
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Térkép & Túrák')),
      body: userLocation == null
          ? const Center(child: CircularProgressIndicator())
          : GoogleMap(
              onMapCreated: (controller) => mapController = controller,
              initialCameraPosition: CameraPosition(
                target: userLocation!,
                zoom: 13,
              ),
              markers: markers,
              polylines: polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              compassEnabled: true,
              mapToolbarEnabled: true,
            ),
    );
  }

  @override
  void dispose() {
    mapController.dispose();
    super.dispose();
  }
}