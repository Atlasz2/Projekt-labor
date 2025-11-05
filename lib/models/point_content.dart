class PointContent {
  final int id;
  final int pointOfInterestId;
  final String? contentType;
  final String? textContent;
  final String? mediaUrl;

  PointContent({
    required this.id,
    required this.pointOfInterestId,
    this.contentType,
    this.textContent,
    this.mediaUrl,
  });

  factory PointContent.fromMap(Map<String, dynamic> data) {
    return PointContent(
      id: data['id'] as int,
      pointOfInterestId: data['pointOfInterestId'] as int,
      contentType: data['contentType'] as String?,
      textContent: data['textContent'] as String?,
      mediaUrl: data['mediaUrl'] as String?,
    );
  }

  factory PointContent.fromJson(Map<String, dynamic> json) {
    return PointContent(
      id: json['id'],
      pointOfInterestId: json['pointOfInterestId'],
      contentType: json['contentType'],
      textContent: json['textContent'],
      mediaUrl: json['mediaUrl'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pointOfInterestId': pointOfInterestId,
      'contentType': contentType,
      'textContent': textContent,
      'mediaUrl': mediaUrl,
    };
  }
}