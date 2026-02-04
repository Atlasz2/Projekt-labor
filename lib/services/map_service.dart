import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/station.dart';
import '../models/trip.dart';

class MapService {
  // Do not obtain FirebaseFirestore.instance at field initialization
  // time. This can fail on web if Firebase hasn't been initialized yet.
  // Instead get the instance lazily inside each method and handle
  // exceptions so the app can run for frontend work without a
  // configured backend.

  Future<List<Trip>> getTrips() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final snapshot = await firestore.collection('trips').get();
      return snapshot.docs.map((doc) => Trip.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('Error loading trips: $e');
      return [];
    }
  }

  Future<List<Station>> getStationsForTrip(int tripId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final snapshot = await firestore
          .collection('points_of_interest')
          .where('tripId', isEqualTo: tripId)
          .get();
      return snapshot.docs.map((doc) => Station.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('Error loading stations: $e');
      return [];
    }
  }

  Future<List<LatLng>> getTripPath(int tripId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final snapshot = await firestore
          .collection('points_of_interest')
          .where('tripId', isEqualTo: tripId)
          .orderBy('order')
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return LatLng(
          (data['latitude'] as num).toDouble(),
          (data['longitude'] as num).toDouble(),
        );
      }).toList();
    } catch (e) {
      debugPrint('Error loading trip path: $e');
      return [];
    }
  }

  Future<bool> verifyQRCode(String qrCode, String stationId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final doc = await firestore
          .collection('points_of_interest')
          .doc(stationId)
          .get();
      if (!doc.exists) return false;

      final station = Station.fromFirestore(doc);
      return station.qrCode == qrCode;
    } catch (e) {
      debugPrint('Error verifying QR code: $e');
      return false;
    }
  }
}