import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/utils/image_normalizer.dart';

void main() {
  group('photoListFromDoc', () {
    test('reads from photos[{url}]', () {
      final result = photoListFromDoc({
        'photos': [
          {'url': 'a.jpg'},
          {'url': 'b.jpg'},
        ],
      });
      expect(result, ['a.jpg', 'b.jpg']);
    });

    test('reads from photos[String]', () {
      final result = photoListFromDoc({
        'photos': ['a.jpg', 'b.jpg'],
      });
      expect(result, ['a.jpg', 'b.jpg']);
    });

    test('reads from photoUrls[]', () {
      final result = photoListFromDoc({
        'photoUrls': ['c.jpg', 'd.jpg'],
      });
      expect(result, ['c.jpg', 'd.jpg']);
    });

    test('reads from imageUrl', () {
      final result = photoListFromDoc({'imageUrl': 'e.jpg'});
      expect(result, ['e.jpg']);
    });

    test('deduplicates across all three sources', () {
      final result = photoListFromDoc({
        'photos': [
          {'url': 'x.jpg'},
        ],
        'photoUrls': ['x.jpg', 'y.jpg'],
        'imageUrl': 'x.jpg',
      });
      expect(result, ['x.jpg', 'y.jpg']);
    });

    test('skips empty, whitespace and null entries', () {
      final result = photoListFromDoc({
        'photos': ['', '  ', null],
        'photoUrls': ['  good.jpg  ', null, ''],
        'imageUrl': '',
      });
      expect(result, ['good.jpg']);
    });

    test('prepends preferred and deduplicates it', () {
      final result = photoListFromDoc({
        'photos': [
          {'url': 'a.jpg'},
        ],
        'imageUrl': 'a.jpg',
      }, preferred: 'a.jpg');
      expect(result, ['a.jpg']);
    });

    test('returns empty list for empty input', () {
      expect(photoListFromDoc({}), isEmpty);
    });
  });

  group('primaryPhotoFromDoc', () {
    test('returns the first valid url with photos priority', () {
      final result = primaryPhotoFromDoc({
        'photos': [
          {'url': 'first.jpg'},
        ],
        'photoUrls': ['second.jpg'],
        'imageUrl': 'third.jpg',
      });
      expect(result, 'first.jpg');
    });

    test('falls back to photoUrls then imageUrl', () {
      expect(
        primaryPhotoFromDoc({
          'photoUrls': ['only.jpg'],
        }),
        'only.jpg',
      );
      expect(primaryPhotoFromDoc({'imageUrl': 'cover.jpg'}), 'cover.jpg');
    });

    test('returns empty string when nothing is present', () {
      expect(primaryPhotoFromDoc({}), '');
    });
  });
}
