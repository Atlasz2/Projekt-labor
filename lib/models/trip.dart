import 'package:cloud_firestore/cloud_firestore.dart';

class Trip {
  final int id;
  final String name;
  final DateTime createdAt;
  final String description;
  final String imageUrl;

  Trip({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.description,
    required this.imageUrl,
  });

  factory Trip.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map;
    return Trip(
      id: data['id'] as int,
      name: data['name'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      description: data['description'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'createdAt': Timestamp.fromDate(createdAt),
      'description': description,
      'imageUrl': imageUrl,
    };
  }
}