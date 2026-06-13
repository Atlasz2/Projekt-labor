/// Shared image URL extraction from Firestore document maps.
/// Handles the three legacy storage shapes: photos[{url}|String], photoUrls[], imageUrl.
library;

/// Returns all non-empty, deduplicated photo URLs from a Firestore document map.
///
/// Priority: photos > photoUrls > imageUrl (each field's results appear before the next).
/// If [preferred] is non-empty it is prepended (and deduplicated against later entries).
List<String> photoListFromDoc(
  Map<String, dynamic> data, {
  String? preferred,
}) {
  final seen = <String>{};
  final out = <String>[];

  void add(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isNotEmpty && seen.add(v)) out.add(v);
  }

  if (preferred != null) add(preferred);

  final photos = data['photos'];
  if (photos is List) {
    for (final entry in photos) {
      if (entry is String) {
        add(entry);
      } else if (entry is Map) {
        add(entry['url']?.toString());
      }
    }
  }

  final photoUrls = data['photoUrls'];
  if (photoUrls is List) {
    for (final entry in photoUrls) {
      add(entry?.toString());
    }
  }

  add(data['imageUrl']?.toString());
  return out;
}

/// Returns the first valid photo URL from a Firestore document, or empty string.
String primaryPhotoFromDoc(Map<String, dynamic> data) {
  final list = photoListFromDoc(data);
  return list.isNotEmpty ? list.first : '';
}
