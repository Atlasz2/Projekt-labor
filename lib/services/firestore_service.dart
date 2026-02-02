import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/trip.dart';
import '../models/station.dart';
import '../models/point_content.dart';

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  factory FirestoreService() {
    return _instance;
  }
  
  FirestoreService._internal();

  // ========== TRIPS ==========
  
  Future<List<Trip>> getAllTrips() async {
    try {
      final snapshot = await _db
          .collection('trips')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get();
      return snapshot.docs.map((doc) => Trip.fromFirestore(doc)).toList();
    } catch (e) {
      print('Error fetching trips: \');
      return [];
    }
  }

  Future<Trip?> getTripById(String tripId) async {
    try {
      final doc = await _db.collection('trips').doc(tripId).get();
      return doc.exists ? Trip.fromFirestore(doc) : null;
    } catch (e) {
      print('Error fetching trip: \');
      return null;
    }
  }

  Future<void> createTrip(Trip trip) async {
    try {
      await _db.collection('trips').doc(trip.id).set(trip.toFirestore());
    } catch (e) {
      print('Error creating trip: \');
      rethrow;
    }
  }

  Future<void> updateTrip(Trip trip) async {
    try {
      await _db
          .collection('trips')
          .doc(trip.id)
          .update({
            ...trip.toFirestore(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      print('Error updating trip: \');
      rethrow;
    }
  }

  // ========== STATIONS ==========
  
  Future<List<Station>> getStationsByTripId(String tripId) async {
    try {
      final snapshot = await _db
          .collection('stations')
          .where('tripId', isEqualTo: tripId)
          .orderBy('orderIndex')
          .get();
      return snapshot.docs.map((doc) => Station.fromFirestore(doc)).toList();
    } catch (e) {
      print('Error fetching stations: \');
      return [];
    }
  }

  Future<Station?> getStationById(String stationId) async {
    try {
      final doc = await _db.collection('stations').doc(stationId).get();
      return doc.exists ? Station.fromFirestore(doc) : null;
    } catch (e) {
      print('Error fetching station: \');
      return null;
    }
  }

  Future<Station?> getStationByQRCode(String qrCode) async {
    try {
      final snapshot = await _db
          .collection('stations')
          .where('qrCodeIdentifier', isEqualTo: qrCode)
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty
          ? Station.fromFirestore(snapshot.docs.first)
          : null;
    } catch (e) {
      print('Error fetching station by QR: \');
      return null;
    }
  }

  Future<void> createStation(Station station) async {
    try {
      await _db
          .collection('stations')
          .doc(station.id)
          .set(station.toFirestore());
    } catch (e) {
      print('Error creating station: \');
      rethrow;
    }
  }

  Future<void> updateStation(Station station) async {
    try {
      await _db.collection('stations').doc(station.id).update(
            station.toFirestore(),
          );
    } catch (e) {
      print('Error updating station: \');
      rethrow;
    }
  }

  // ========== POINT CONTENTS ==========
  
  Future<List<PointContent>> getContentsByStationId(String stationId) async {
    try {
      final snapshot = await _db
          .collection('point_contents')
          .where('stationId', isEqualTo: stationId)
          .get();
      return snapshot.docs
          .map((doc) => PointContent.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('Error fetching contents: \');
      return [];
    }
  }

  Future<PointContent?> getContentById(String contentId) async {
    try {
      final doc =
          await _db.collection('point_contents').doc(contentId).get();
      return doc.exists ? PointContent.fromFirestore(doc) : null;
    } catch (e) {
      print('Error fetching content: \');
      return null;
    }
  }

  Future<void> createPointContent(PointContent content) async {
    try {
      await _db
          .collection('point_contents')
          .doc(content.id)
          .set(content.toMap());
    } catch (e) {
      print('Error creating content: \');
      rethrow;
    }
  }

  Future<void> updatePointContent(PointContent content) async {
    try {
      await _db
          .collection('point_contents')
          .doc(content.id)
          .update(content.toMap());
    } catch (e) {
      print('Error updating content: \');
      rethrow;
    }
  }

  // ========== USER PROGRESS ==========
  
  Future<void> updateUserProgress({
    required String userId,
    required String tripId,
    required List<String> visitedStations,
    required List<String> unlockedContents,
    required double progress,
  }) async {
    try {
      final docId = '\_\';
      await _db.collection('user_progress').doc(docId).set(
            {
              'userId': userId,
              'tripId': tripId,
              'visitedStationIds': visitedStations,
              'unlockedContentIds': unlockedContents,
              'progress': progress,
              'lastUpdated': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
    } catch (e) {
      print('Error updating user progress: \');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getUserProgress(
      String userId, String tripId) async {
    try {
      final docId = '\_\';
      final doc = await _db.collection('user_progress').doc(docId).get();
      return doc.data();
    } catch (e) {
      print('Error fetching user progress: \');
      return null;
    }
  }

  // ========== QR CODES ==========
  
  Future<void> recordQRScan(String qrIdentifier) async {
    try {
      final snapshot = await _db
          .collection('qr_codes')
          .where('qrIdentifier', isEqualTo: qrIdentifier)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        await doc.reference.update({
          'lastScanned': FieldValue.serverTimestamp(),
          'scanCount': FieldValue.increment(1),
        });
      }
    } catch (e) {
      print('Error recording QR scan: \');
    }
  }

  // ========== STREAM LISTENERS ==========
  
  Stream<List<Trip>> watchAllTrips() {
    return _db
        .collection('trips')
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Trip.fromFirestore(doc)).toList());
  }

  Stream<List<Station>> watchStationsByTripId(String tripId) {
    return _db
        .collection('stations')
        .where('tripId', isEqualTo: tripId)
        .orderBy('orderIndex')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Station.fromFirestore(doc)).toList());
  }
}
