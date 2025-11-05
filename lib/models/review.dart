class Review {
  final int id;
  final int pointOfInterestId;
  final int userId;
  final int rating;
  final DateTime createdAt;
  final String? comment;
  final bool isPublic;

  Review({
    required this.id,
    required this.pointOfInterestId,
    required this.userId,
    required this.rating,
    required this.createdAt,
    this.comment,
    required this.isPublic,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'],
      pointOfInterestId: json['pointOfInterestId'],
      userId: json['userId'],
      rating: json['rating'],
      createdAt: DateTime.parse(json['createdAt']),
      comment: json['comment'],
      isPublic: json['isPublic'],
    );
  }
}
