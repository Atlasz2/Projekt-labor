import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'point_content.dart';

class Station {
  final String id;
  final int tripId;
  final String name;
  final LatLng location;
  final String description;
  final String qrCode;
  final String imageUrl;
  final List<PointContent> contents;
  final bool isUnlocked;

  Station({
    required this.id,
    required this.tripId,
    required this.name,
    required this.location,
    required this.description,
    required this.qrCode,
    required this.imageUrl,
    required this.contents,
    this.isUnlocked = false,
  });

  factory Station.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map;
    List<PointContent> contents = [];
    if (data['contents'] != null) {
      contents = (data['contents'] as List)
          .map((content) => PointContent.fromMap(content as Map<String, dynamic>))
          .toList();
    }
    return Station(
      id: doc.id,
      tripId: data['tripId'] as int,
      name: data['name'] ?? '',
      location: LatLng(data['latitude'] ?? 0, data['longitude'] ?? 0),
      description: data['description'] ?? '',
      qrCode: data['qrCodeIdentifier'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      contents: contents,
    );
  }

  Station copyWith({bool? isUnlocked}) {
    return Station(
      id: id,
      tripId: tripId,
      name: name,
      location: location,
      description: description,
      qrCode: qrCode,
      imageUrl: imageUrl,
      contents: contents,
      isUnlocked: isUnlocked ?? this.isUnlocked,
    );
  }
}