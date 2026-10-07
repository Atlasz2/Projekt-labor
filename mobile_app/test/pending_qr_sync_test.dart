import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/pending_qr_sync_service.dart';
import 'package:mobile_app/services/qr_processing_service.dart';

void main() {
  group('PendingQrSyncService.drainQueue', () {
    late List<String> removed;
    late List<String> processed;

    setUp(() {
      removed = [];
      processed = [];
    });

    Future<PendingQrDrainResult> drain(
      List<String> codes,
      Map<String, Object> failures,
    ) {
      return PendingQrSyncService.drainQueue(
        codes: codes,
        process: (code) async {
          processed.add(code);
          final failure = failures[code];
          if (failure != null) throw failure;
        },
        remove: (code) async => removed.add(code),
      );
    }

    test('sikeres jóváírás után az elem kikerül a sorból', () async {
      final result = await drain(['A', 'B'], const {});
      expect(removed, ['A', 'B']);
      expect(result, (credited: 2, dropped: 0, kept: 0));
    });

    test('a végleges hibák (ismeretlen kód, másik település, távolság, '
        'hiányzó kötelező pozíció) '
        'eldobják az elemet', () async {
      final result = await drain(
        ['ISMERETLEN', 'MASIK', 'MESSZE', 'GPS'],
        {
          'ISMERETLEN': const QrCodeNotFoundException('ISMERETLEN'),
          'MASIK': const QrWrongProjectException(),
          'MESSZE': const QrOutOfRangeException(distance: 900, threshold: 150),
          'GPS': const QrLocationRequiredException(),
        },
      );
      expect(removed, ['ISMERETLEN', 'MASIK', 'MESSZE', 'GPS']);
      expect(result, (credited: 0, dropped: 4, kept: 0));
    });

    test('átmeneti hibánál az elem a sorban marad', () async {
      final result = await drain(
        ['HALO', 'IDO', 'SZERVER'],
        {
          'HALO': FirebaseFunctionsException(
            code: 'unavailable',
            message: 'offline',
          ),
          'IDO': TimeoutException('lassú hálózat'),
          'SZERVER': const QrServerUnavailableException(),
        },
      );
      expect(removed, isEmpty);
      expect(result, (credited: 0, dropped: 0, kept: 3));
    });

    test('egy hibás elem nem állítja meg a többi feldolgozását', () async {
      final result = await drain(
        ['ROSSZ', 'JO', 'MERGEZETT'],
        {
          'ROSSZ': FirebaseFunctionsException(code: 'internal', message: 'x'),
          'MERGEZETT': const QrCodeNotFoundException('MERGEZETT'),
        },
      );
      expect(processed, ['ROSSZ', 'JO', 'MERGEZETT']);
      expect(removed, ['JO', 'MERGEZETT']);
      expect(result, (credited: 1, dropped: 1, kept: 1));
    });

    test('üres sornál nincs teendő', () async {
      final result = await drain(const [], const {});
      expect(processed, isEmpty);
      expect(result, (credited: 0, dropped: 0, kept: 0));
    });
  });
}
