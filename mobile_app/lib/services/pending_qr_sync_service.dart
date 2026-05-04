import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'local_cache.dart';
import 'offline_sync_service.dart';
import 'qr_processing_service.dart';

class PendingQrSyncService {
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  static bool _started = false;
  static bool _syncInProgress = false;

  static Future<void> start() async {
    if (_started) return;
    _started = true;

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        unawaited(syncNow());
      }
    });

    await syncNow();
  }

  static Future<void> stop() async {
    _started = false;
    await _connectivitySub?.cancel();
    _connectivitySub = null;
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
          await QrProcessingService.processByCode(uid: uid, code: entry.key);
          await LocalCache.removePendingQr(entry.key);
        } catch (e) {
          debugPrint('Pending QR sync failed for ${entry.key}: $e');
        }
      }
    } finally {
      _syncInProgress = false;
    }
  }
}