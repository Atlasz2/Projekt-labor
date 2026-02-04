import 'package:cloud_firestore/cloud_firestore.dart';

class PointContent {
  final String id;
  final String stationId;
  final String type; // "text", "image", "video", "audio", "web"
  final String title;
  final String content;
  final String? mediaUrl;
  final String? videoUrl;
  final bool requiresQR;
  final DateTime createdAt;

  PointContent({
    required this.id,
    required this.stationId,
    required this.type,
    required this.title,
    required this.content,
    this.mediaUrl,
    this.videoUrl,
    required this.requiresQR,
    required this.createdAt,
  });

  factory PointContent.fromMap(Map<String, dynamic> data) {
    return PointContent(
      id: data['id'] as String? ?? '',
      stationId: data['stationId'] as String? ?? '',
      type: data['type'] as String? ?? 'text',
      title: data['title'] as String? ?? '',
      content: data['content'] as String? ?? '',
      mediaUrl: data['mediaUrl'] as String?,
      videoUrl: data['videoUrl'] as String?,
      requiresQR: data['requiresQR'] as bool? ?? false,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  factory PointContent.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map;
    return PointContent.fromMap({...data, 'id': doc.id});
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'stationId': stationId,
      'type': type,
      'title': title,
      'content': content,
      'mediaUrl': mediaUrl,
      'videoUrl': videoUrl,
      'requiresQR': requiresQR,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  PointContent copyWith({
    String? content,
    bool? requiresQR,
  }) {
    return PointContent(
      id: id,
      stationId: stationId,
      type: type,
      title: title,
      content: content ?? this.content,
      mediaUrl: mediaUrl,
      videoUrl: videoUrl,
      requiresQR: requiresQR ?? this.requiresQR,
      createdAt: createdAt,
    );
  }
}
