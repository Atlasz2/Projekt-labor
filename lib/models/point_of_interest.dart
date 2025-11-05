class PointOfInterest {
  final int id;
  final int tripId;
  final String? crybcodeIdentifier;
  final String? description;
  final double latitude;
  final double longitude;
  final String? imageUrl;

  PointOfInterest({
    required this.id,
    required this.tripId,
    this.crybcodeIdentifier,
    this.description,
    required this.latitude,
    required this.longitude,
    this.imageUrl,
  });

  factory PointOfInterest.fromJson(Map<String, dynamic> json) {
    return PointOfInterest(
      id: json['id'],
      tripId: json['tripId'],
      crybcodeIdentifier: json['crybcodeIdentifier'],
      description: json['description'],
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      imageUrl: json['imageUrl'],
    );
  }
}
