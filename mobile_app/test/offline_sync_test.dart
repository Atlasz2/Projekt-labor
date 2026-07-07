import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/offline_sync_service.dart';
import 'package:mobile_app/services/qr_processing_service.dart';

void main() {
  group('PendingAction', () {
    PendingAction sample({int attempts = 0}) => PendingAction(
          id: 'a1',
          actionType: 'update',
          collection: 'bug_reports',
          docId: 'd1',
          data: const <String, dynamic>{'msg': 'hello'},
          createdAt: DateTime.parse('2026-01-02T03:04:05.000Z'),
          attempts: attempts,
        );

    test('round-trips through JSON including attempts', () {
      final restored = PendingAction.fromJson(sample(attempts: 3).toJson());
      expect(restored.id, 'a1');
      expect(restored.actionType, 'update');
      expect(restored.collection, 'bug_reports');
      expect(restored.docId, 'd1');
      expect(restored.data, {'msg': 'hello'});
      expect(restored.createdAt, DateTime.parse('2026-01-02T03:04:05.000Z'));
      expect(restored.attempts, 3);
    });

    test('defaults attempts to 0 for legacy entries without the field', () {
      final legacy = <String, dynamic>{
        'id': 'a1',
        'actionType': 'create',
        'collection': 'contact',
        'docId': 'd1',
        'data': <String, dynamic>{},
        'createdAt': '2026-01-02T03:04:05.000Z',
      };
      expect(PendingAction.fromJson(legacy).attempts, 0);
    });

    test('copyWith updates only the attempts counter', () {
      final next = sample(attempts: 1).copyWith(attempts: 2);
      expect(next.attempts, 2);
      expect(next.id, 'a1');
      expect(next.collection, 'bug_reports');
      expect(next.data, {'msg': 'hello'});
    });
  });

  group('QrCodeNotFoundException', () {
    test('toString names the unknown code (drives the scan error message)', () {
      expect(
        const QrCodeNotFoundException('XYZ').toString(),
        'Ismeretlen QR kod: XYZ',
      );
    });

    test('is an Exception', () {
      expect(const QrCodeNotFoundException('x'), isA<Exception>());
    });
  });
}
