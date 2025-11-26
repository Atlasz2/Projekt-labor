import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

class RouteChoice {
  RouteChoice({
    required this.points,
    required this.walkDistanceMeters,
    required this.walkDurationSec,
    required this.summary,
  });

  final List<LatLng> points;
  final int walkDistanceMeters;
  final int walkDurationSec;
  final String summary;
}

class DrivingOverview {
  DrivingOverview({required this.available, this.distanceMeters, this.durationSec});
  final bool available;
  final int? distanceMeters;
  final int? durationSec;
}

class DirectionsService {
  DirectionsService(this.apiKey);
  final String apiKey;

  // Gyalogos alternatívák részletes metaadatokkal
  Future<List<RouteChoice>> getWalkingAlternatives({
    required LatLng origin,
    required LatLng destination,
    List<LatLng> waypoints = const [],
  }) async {
    final wp = waypoints.isEmpty
        ? null
        : waypoints.map((p) => '${p.latitude},${p.longitude}').join('|');

    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'alternatives': 'true',
      'mode': 'walking',
      if (wp != null) 'waypoints': wp,
      'key': apiKey,
    });

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = json.decode(res.body);
    if (data['status'] != 'OK') {
      throw Exception('Directions hiba: ${data['status']} - ${data['error_message'] ?? ''}');
    }

    final polylinePoints = PolylinePoints();
    final List<RouteChoice> choices = [];
    for (final route in data['routes']) {
      final enc = route['overview_polyline']['points'] as String;
      final pts = polylinePoints.decodePolyline(enc).map(
        (p) => LatLng(p.latitude, p.longitude),
      );

      // Összesített táv/idő a route legs alapján
      int dist = 0;
      int dur = 0;
      for (final leg in (route['legs'] as List)) {
        dist += (leg['distance']['value'] as num).toInt();
        dur  += (leg['duration']['value'] as num).toInt();
      }

      choices.add(RouteChoice(
        points: pts.toList(),
        walkDistanceMeters: dist,
        walkDurationSec: dur,
        summary: (route['summary'] as String?) ?? '',
      ));
    }
    return choices;
  }

  // Autós elérhetőség + kb. becslés (leggyorsabb autós út)
  Future<DrivingOverview> getDrivingOverview({
    required LatLng origin,
    required LatLng destination,
    List<LatLng> waypoints = const [],
  }) async {
    final wp = waypoints.isEmpty
        ? null
        : waypoints.map((p) => '${p.latitude},${p.longitude}').join('|');

    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'mode': 'driving',
      'alternatives': 'false',
      if (wp != null) 'waypoints': wp,
      'key': apiKey,
    });

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = json.decode(res.body);
    final status = data['status'];
    if (status == 'ZERO_RESULTS') {
      return DrivingOverview(available: false);
    }
    if (status != 'OK') {
      // Ha engedély gond stb., dobjunk hibaüzenetet a UI felé
      throw Exception('Directions hiba: $status - ${data['error_message'] ?? ''}');
    }

    int dist = 0;
    int dur = 0;
    for (final leg in (data['routes'][0]['legs'] as List)) {
      dist += (leg['distance']['value'] as num).toInt();
      dur  += (leg['duration']['value'] as num).toInt();
    }
    return DrivingOverview(available: true, distanceMeters: dist, durationSec: dur);
  }
}
