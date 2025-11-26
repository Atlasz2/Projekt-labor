class PointContent {
  final int id;
  final int pointOfInterestId;
  final String contentType;
  final String? textContent;
  final String? mediaUrl;

  PointContent({
    required this.id,
    required this.pointOfInterestId,
    required this.contentType,
    this.textContent,
    this.mediaUrl,
  });

  factory PointContent.fromMap(Map<String, dynamic> data) {
    return PointContent(
      id: data['id'] as int,
      pointOfInterestId: data['pointOfInterestId'] as int,
      contentType: data['contentType'] as String,
      textContent: data['textContent'] as String?,
      mediaUrl: data['mediaUrl'] as String?,
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