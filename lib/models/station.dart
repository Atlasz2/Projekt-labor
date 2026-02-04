import 'package:cloud_firestore/cloud_firestore.dart';
import 'point_content.dart';

class Station {
  final String id;
  final String tripId;
  final int orderIndex;
  final String name;
  final LatLng location;
  final String description;
  final String qrCodeIdentifier;
  final String imageUrl;
  final List<PointContent> contents;
  final bool isUnlocked;
  final int radiusMeters;
  final Map<String, dynamic> metadata;

  Station({
    required this.id,
    required this.tripId,
    required this.orderIndex,
    required this.name,
    required this.location,
    required this.description,
    required this.qrCodeIdentifier,
    required this.imageUrl,
    required this.contents,
    this.isUnlocked = false,
    this.radiusMeters = 100,
    this.metadata = const {},
  });

  factory Station.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map;
    
    GeoPoint? geoPoint = data['location'];
    LatLng location = geoPoint != null 
      ? LatLng(geoPoint.latitude, geoPoint.longitude)
      : LatLng(0, 0);
    
    List<PointContent> contents = [];
    if (data['contents'] != null) {
      contents = (data['contents'] as List)
          .map((content) => PointContent.fromMap(content as Map<String, dynamic>))
          .toList();
    }
    
    return Station(
      id: doc.id,
      tripId: data['tripId'] as String? ?? '',
      orderIndex: data['orderIndex'] as int? ?? 0,
      name: data['name'] ?? '',
      location: location,
      description: data['description'] ?? '',
      qrCodeIdentifier: data['qrCodeIdentifier'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      contents: contents,
      isUnlocked: data['isUnlocked'] as bool? ?? false,
      radiusMeters: data['radiusMeters'] as int? ?? 100,
      metadata: data['metadata'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'tripId': tripId,
      'orderIndex': orderIndex,
      'name': name,
      'location': GeoPoint(location.latitude, location.longitude),
      'description': description,
      'qrCodeIdentifier': qrCodeIdentifier,
      'imageUrl': imageUrl,
      'contents': contents.map((c) => c.toMap()).toList(),
      'isUnlocked': isUnlocked,
      'radiusMeters': radiusMeters,
      'metadata': metadata,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Station copyWith({bool? isUnlocked}) {
    return Station(
      id: id,
      tripId: tripId,
      orderIndex: orderIndex,
      name: name,
      location: location,
      description: description,
      qrCodeIdentifier: qrCodeIdentifier,
      imageUrl: imageUrl,
      contents: contents,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      radiusMeters: radiusMeters,
      metadata: metadata,
    );
  }
}

class LatLng {
  final double latitude;
  final double longitude;

  LatLng(this.latitude, this.longitude);

  @override
  String toString() => 'LatLng(\, \)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatLng &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;
}
