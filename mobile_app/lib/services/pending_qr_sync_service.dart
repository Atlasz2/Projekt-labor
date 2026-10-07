import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'local_cache.dart';
import 'offline_sync_service.dart';
import 'qr_processing_service.dart';

class PendingQrSyncService {
  static bool _started = false;
  static bool _syncInProgress = false;
  static VoidCallback? _onlineListener;

  static Future<void> start() async {
    if (_started) return;
    _started = true;

    // Sync whenever the device becomes *confirmed* online. We listen to
    // OfflineSyncService.onlineNotifier (which flips only after a real
    // reachability probe) instead of the raw connectivity stream — otherwise
    // syncNow runs before connectivity is verified and bails out on the stale
    // offline flag, leaving scanned codes stuck in the queue.
    final sync = OfflineSyncService();
    await sync.init();
    void onlineChanged() {
      if (sync.onlineNotifier.value) {
        unawaited(syncNow());
      }
    }

    _onlineListener = onlineChanged;
    sync.onlineNotifier.addListener(onlineChanged);

    await syncNow();
  }

  static Future<void> stop() async {
    _started = false;
    final listener = _onlineListener;
    if (listener != null) {
      OfflineSyncService().onlineNotifier.removeListener(listener);
      _onlineListener = null;
    }
  }

  static Future<void> syncNow() async {
    if (_syncInProgress) return;
    if (!LocalCache.hasPendingQr) return;

    final syncService = OfflineSyncService();
    await syncService.init();
    if (!syncService.isOnline) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _syncInProgress = true;
    try {
      await drainQueue(
        codes: LocalCache.getPendingQrQueue().map((e) => e.key).toList(),
        process: (code) => QrProcessingService.processByCode(
          code: code,
          location: LocalCache.getPendingQrLocation(code),
        ),
        remove: LocalCache.removePendingQr,
      );
    } finally {
      _syncInProgress = false;
    }
  }

  /// A sor egyszeri feldolgozása, hibaosztályozással. Sikeres jóváírás és
  /// végleges hiba (ismeretlen kód, másik település, helyszínen kívül) után az
  /// elem kikerül a sorból – így egy soha fel nem dolgozható („mérgezett”)
  /// elem sem blokkolja örökre –, minden más (hálózati, átmeneti szerver-)
  /// hiba esetén marad a következő próbálkozásig. A [process] és a [remove]
  /// tesztekben lecserélhető.
  @visibleForTesting
  static Future<PendingQrDrainResult> drainQueue({
    required List<String> codes,
    required Future<void> Function(String code) process,
    required Future<void> Function(String code) remove,
  }) async {
    var credited = 0, dropped = 0, kept = 0;
    for (final code in codes) {
      try {
        await process(code);
        await remove(code);
        credited++;
      } on QrCodeNotFoundException {
        await remove(code);
        dropped++;
        debugPrint('Pending QR eldobva (ismeretlen kód): $code');
      } on QrWrongProjectException {
        await remove(code);
        dropped++;
        debugPrint('Pending QR eldobva (másik település): $code');
      } on QrLocationRequiredException {
        // A beolvasáskor nem volt pozíció, pedig az állomás megköveteli.
        await remove(code);
        dropped++;
        debugPrint('Pending QR eldobva (pozíció nélkül): $code');
      } on QrOutOfRangeException {
        // Erre a beolvasásra végleges: a rögzített pozíció túl messze volt.
        // Egy helyszíni újrabeolvasás sikerülni fog.
        await remove(code);
        dropped++;
        debugPrint('Pending QR eldobva (helyszínen kívül): $code');
      } catch (e) {
        kept++;
        debugPrint('Pending QR sync failed for $code: $e');
      }
    }
    return (credited: credited, dropped: dropped, kept: kept);
  }
}

/// A sorfeldolgozás eredménye: jóváírt, véglegesen eldobott és megtartott elemek.
typedef PendingQrDrainResult = ({int credited, int dropped, int kept});
