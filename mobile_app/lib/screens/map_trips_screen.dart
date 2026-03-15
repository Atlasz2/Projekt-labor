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

  // Default coordinates and routes for trips
  final Map<String, Map<String, dynamic>> tripDefaults = {
    'piás': {
      'startLat': 47.1100,
      'startLng': 17.8000,
      'color': 0xFF4CAF50,
      'routePoints': [
        [47.1100, 17.8000],
        [47.1120, 17.8020],
        [47.1150, 17.8050],
        [47.1180, 17.8100],
      ]
    },
    'történelmi': {
      'startLat': 47.1300,
      'startLng': 17.7800,
      'color': 0xFFFF9800,
      'routePoints': [
        [47.1300, 17.7800],
        [47.1310, 17.7810],
        [47.1320, 17.7830],
        [47.1340, 17.7850],
      ]
    }
  };

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
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      setState(() {
        userLocation = LatLng(position.latitude, position.longitude);
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
      debugPrint('Error getting location: $e');
      setState(() {
        userLocation = const LatLng(47.1200, 17.8000);
      });
    }
  }

  Map<String, dynamic> _getTripDefaults(String tripName) {
    final lowerName = tripName.toLowerCase();
    if (lowerName.contains('piás') || lowerName.contains('vínás')) {
      return tripDefaults['piás']!;
    } else if (lowerName.contains('történelmi') || lowerName.contains('történeti')) {
      return tripDefaults['történelmi']!;
    }
    // Default fallback
    return {
      'startLat': 47.1200,
      'startLng': 17.8000,
      'color': 0xFF667EEA,
      'routePoints': [[47.1200, 17.8000]]
    };
  }

  Future<void> _loadTrips() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('trips').get();
      
      if (snapshot.docs.isEmpty) {
        debugPrint('No trips found in Firestore');
        return;
      }

      setState(() {
        for (int i = 0; i < snapshot.docs.length; i++) {
          final doc = snapshot.docs[i];
          final data = doc.data();
          
          final name = data['name'] ?? 'Unknown Trip';
          final defaults = _getTripDefaults(name);
          
          final startLat = (data['startLat'] ?? defaults['startLat']) as double;
          final startLng = (data['startLng'] ?? defaults['startLng']) as double;
          final colorInt = (data['color'] != null 
              ? int.tryParse(data['color'].toString()) ?? defaults['color']
              : defaults['color']) as int;
          final color = Color(colorInt);
          final routePoints = (data['routePoints'] ?? defaults['routePoints']) as List;

          // Add marker for trip start
          markers.add(
            Marker(
              markerId: MarkerId('trip_$i'),
              position: LatLng(startLat, startLng),
              infoWindow: InfoWindow(title: name as String),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                colorInt == 0xFF667EEA ? BitmapDescriptor.hueRed :
                colorInt == 0xFF4CAF50 ? BitmapDescriptor.hueGreen :
                BitmapDescriptor.hueOrange
              ),
            ),
          );

          if (routePoints.isNotEmpty) {
            try {
              final points = routePoints.map((p) {
                if (p is List && p.length >= 2) {
                  return LatLng(p[0] as double, p[1] as double);
                }
                return null;
              }).whereType<LatLng>().toList();

              if (points.isNotEmpty) {
                polylines.add(
                  Polyline(
                    polylineId: PolylineId('route_$i'),
                    points: points,
                    color: color,
                    width: 5,
                    geodesic: true,
                  ),
                );
              }
            } catch (e) {
              debugPrint('Error parsing route points for trip $i: $e');
            }
          }
        }
      });
    } catch (e) {
      debugPrint('Error loading trips from Firestore: $e');
    }
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

