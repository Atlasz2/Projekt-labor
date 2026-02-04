import 'package:cloud_firestore/cloud_firestore.dart';

class Trip {
  final String id;
  final String name;
  final String description;
  final String category; // "cultural", "nature", "historical"
  final String difficulty; // "easy", "medium", "hard"
  final double distance; // km-ben
  final int duration; // perc
  final LatLng startPoint;
  final LatLng endPoint;
  final String imageUrl;
  final List<String> stationIds;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Trip({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.difficulty,
    required this.distance,
    required this.duration,
    required this.startPoint,
    required this.endPoint,
    required this.imageUrl,
    required this.stationIds,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Trip.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map;
    
    GeoPoint? geoStart = data['startPoint'];
    GeoPoint? geoEnd = data['endPoint'];
    
    LatLng startPoint = geoStart != null 
      ? LatLng(geoStart.latitude, geoStart.longitude)
      : LatLng(0, 0);
    
    LatLng endPoint = geoEnd != null 
      ? LatLng(geoEnd.latitude, geoEnd.longitude)
      : LatLng(0, 0);
    
    return Trip(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      category: data['category'] ?? 'other',
      difficulty: data['difficulty'] ?? 'medium',
      distance: (data['distance'] ?? 0).toDouble(),
      duration: data['duration'] ?? 0,
      startPoint: startPoint,
      endPoint: endPoint,
      imageUrl: data['imageUrl'] ?? '',
      stationIds: List<String>.from(data['stationIds'] ?? []),
      isActive: data['isActive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'category': category,
      'difficulty': difficulty,
      'distance': distance,
      'duration': duration,
      'startPoint': GeoPoint(startPoint.latitude, startPoint.longitude),
      'endPoint': GeoPoint(endPoint.latitude, endPoint.longitude),
      'imageUrl': imageUrl,
      'stationIds': stationIds,
      'isActive': isActive,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  Trip copyWith({
    String? name,
    String? description,
    bool? isActive,
    List<String>? stationIds,
  }) {
    return Trip(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category,
      difficulty: difficulty,
      distance: distance,
      duration: duration,
      startPoint: startPoint,
      endPoint: endPoint,
      imageUrl: imageUrl,
      stationIds: stationIds ?? this.stationIds,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
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
