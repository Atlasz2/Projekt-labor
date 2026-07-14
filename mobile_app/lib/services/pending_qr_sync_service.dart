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
      final queueEntries = LocalCache.getPendingQrQueue();
      for (final entry in queueEntries) {
        try {
          await QrProcessingService.processByCode(
            uid: uid,
            code: entry.key,
            location: LocalCache.getPendingQrLocation(entry.key),
          );
          await LocalCache.removePendingQr(entry.key);
        } on QrCodeNotFoundException {
          // Permanent: the code maps to no station or event — drop it so the
          // queue can drain instead of retrying this poison entry forever.
          await LocalCache.removePendingQr(entry.key);
          debugPrint('Pending QR eldobva (ismeretlen kód): ${entry.key}');
        } on QrOutOfRangeException {
          // Permanent for this scan: the recorded position was too far from the
          // station. Drop it so the queue can drain (a valid re-scan on site
          // will succeed).
          await LocalCache.removePendingQr(entry.key);
          debugPrint('Pending QR eldobva (helyszínen kívül): ${entry.key}');
        } catch (e) {
          // Transient (network/Firestore) — keep it queued for the next attempt.
          debugPrint('Pending QR sync failed for ${entry.key}: $e');
        }
      }
    } finally {
      _syncInProgress = false;
    }
  }
}