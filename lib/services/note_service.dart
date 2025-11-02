import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/point_content.dart';

class NoteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> saveNote(String stationId, String note) async {
    try {
      final pointContent = PointContent(
        id: DateTime.now().millisecondsSinceEpoch,
        pointOfInterestId: int.parse(stationId),
        contentType: 'note',
        textContent: note,
      );

      await _firestore.collection('stations').doc(stationId).collection('notes').add(
        pointContent.toMap(),
      );
    } catch (e) {
      print('Error saving note: $e');
      rethrow;
    }
  }

  Future<List<PointContent>> getNotes(String stationId) async {
    try {
      final snapshot = await _firestore
          .collection('stations')
          .doc(stationId)
          .collection('notes')
          .get();

      return snapshot.docs
          .map((doc) => PointContent.fromMap(doc.data()))
          .toList();
    } catch (e) {
      print('Error getting notes: $e');
      return [];
    }
  }
}