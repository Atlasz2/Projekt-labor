import 'package:cloud_firestore/cloud_firestore.dart';

class Trip {
  final int id;
  final int userId;
  final DateTime createdAt;
  final String? description;
  final String? imageUrl;

  Trip({
    required this.id,
    required this.userId,
    required this.createdAt,
    this.description,
    this.imageUrl,
  });

  factory Trip.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map;
    return Trip(
      id: data['id'] as int,
      userId: data['userId'] as int,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      description: data['description'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
    );
  }

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'],
      userId: json['userId'],
      createdAt: DateTime.parse(json['createdAt']),
      description: json['description'],
      imageUrl: json['imageUrl'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'createdAt': Timestamp.fromDate(createdAt),
      'description': description,
      'imageUrl': imageUrl,
    };
  }
}