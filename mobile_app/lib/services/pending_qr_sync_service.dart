import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'local_cache.dart';
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
        syncNow().ignore();
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

    final online = await _isOnline();
    if (!online) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _syncInProgress = true;
    try {
      final queueEntries = LocalCache.getPendingQrQueue().entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));

      for (final entry in queueEntries) {
        try {
          await QrProcessingService.processByCode(uid: uid, code: entry.value);
          await LocalCache.removePendingQr(entry.key);
        } catch (e) {
          debugPrint('Pending QR sync failed for ${entry.key}: $e');
        }
      }
    } finally {
      _syncInProgress = false;
    }
  }

  static Future<bool> _isOnline() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }
}
