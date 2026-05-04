import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/offline_image.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/local_cache.dart';
import '../services/offline_sync_service.dart';
import '../services/pending_qr_sync_service.dart';
import '../services/qr_processing_service.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _controller = MobileScannerController();
  final OfflineSyncService _offlineSyncService = OfflineSyncService();

  bool _scanning = true;
  bool _loading = false;
  Map<String, dynamic>? _station;
  String? _errorMsg;
  List<Map<String, dynamic>> _history = [];

  String _primaryImageUrl(Map<String, dynamic> item) {
    final photos = item['photos'];
    if (photos is List && photos.isNotEmpty) {
      for (final entry in photos) {
        if (entry is String && entry.trim().isNotEmpty) {
          return entry.trim();
        }
        if (entry is Map) {
          final url = entry['url']?.toString().trim() ?? '';
          if (url.isNotEmpty) return url;
        }
      }
    }

    final photoUrls = item['photoUrls'];
    if (photoUrls is List && photoUrls.isNotEmpty) {
      for (final entry in photoUrls) {
        final url = entry?.toString().trim() ?? '';
        if (url.isNotEmpty) return url;
      }
    }

    return item['imageUrl']?.toString().trim() ?? '';
  }

  Map<String, dynamic> _normalizeStation(Map<String, dynamic> item) {
    final imageUrl = _primaryImageUrl(item);
    return {
      ...item,
      'imageUrl': imageUrl,
    };
  }

  @override
  void initState() {
    super.initState();
    unawaited(_offlineSyncService.init());
    unawaited(_loadHistory());
    unawaited(PendingQrSyncService.start());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await _firestore.collection('user_progress').doc(uid).get();
      final data = doc.data() ?? <String, dynamic>{};
      final completed = List<String>.from(data['completedStations'] ?? const []);
      if (completed.isEmpty) {
        if (!mounted) return;
        setState(() => _history = []);
        return;
      }

      final recentIds = completed.reversed.take(10).toList(growable: false);
      final byId = <String, Map<String, dynamic>>{};

      for (var i = 0; i < recentIds.length; i += 10) {
        final end = (i + 10 < recentIds.length) ? i + 10 : recentIds.length;
        final chunk = recentIds.sublist(i, end);
        final snap = await _firestore
            .collection('stations')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final st in snap.docs) {
          byId[st.id] = <String, dynamic>{'id': st.id, ...st.data()};
        }
      }

      if (!mounted) return;
      setState(() {
        _history = recentIds
            .map((id) => byId[id] ?? <String, dynamic>{'id': id, 'name': id})
            .toList(growable: false);
      });
    } catch (_) {}
  }

  Future<void> _onQrDetected(String code) async {
    if (!_scanning || _loading) return;

    await _offlineSyncService.init();
    if (!_offlineSyncService.isOnline) {
      final queuedNow = await LocalCache.enqueuePendingQr(code);
      final cachedStation = _findStationFromLocalCache(code);
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _loading = false;
        _errorMsg = null;
        if (cachedStation != null) {
          _station = {
            ..._normalizeStation(cachedStation),
            'alreadyDone': false,
            'newAchievements': const <Map<String, dynamic>>[],
            'offlineQueued': true,
            'offlineQueuedNow': queuedNow,
          };
        } else {
          _station = null;
          _errorMsg = queuedNow
              ? 'Offline: a QR-kód sorba állt, online állapotban szinkronizál.'
              : 'Ez a QR már offline sorban van, online állapotban szinkronizál.';
        }
      });
      _controller.stop();
      return;
    }

    setState(() {
      _scanning = false;
      _loading = true;
      _errorMsg = null;
    });
    _controller.stop();

    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) throw Exception('Nincs bejelentkezett felhasználó');

      final result = await QrProcessingService.processByCode(uid: uid, code: code);
      if (!mounted) return;

      setState(() {
        _station = {
          ..._normalizeStation(result.station),
          'alreadyDone': result.alreadyDone,
          'newAchievements': result.newAchievements,
        };
        _loading = false;
      });

      if (!result.alreadyDone) {
        unawaited(_loadHistory());
      }
      unawaited(PendingQrSyncService.start());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = 'Hiba: ${e.toString().replaceAll('Exception: ', '')}';
      });
    }
  }

  Map<String, dynamic>? _findStationFromLocalCache(String code) {
    final normalized = code.trim();
    if (normalized.isEmpty) return null;
    final allStations = LocalCache.getStations();
    for (final station in allStations) {
      final qr = station['qrCode']?.toString().trim();
      final id = station['id']?.toString().trim();
      if (qr == normalized || id == normalized) {
        return station;
      }
    }
    return null;
  }

  void _reset() {
    setState(() {
      _scanning = true;
      _station = null;
      _errorMsg = null;
    });
    _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR beolvasás'),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Előzmények',
              onPressed: () => _showHistory(context),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _station != null
          ? _buildResult()
          : _errorMsg != null
          ? _buildError()
          : _buildScanner(),
    );
  }

  Widget _buildScanner() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE8F5E9), Color(0xFFF1F8E9)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFB7DFC0)),
          ),
          child: const Row(
            children: [
              Icon(Icons.tips_and_updates_outlined, color: Color(0xFF2E7D32)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tipp: tartsd stabilan a kamerát. Offline módban a QR beolvasás sorba áll.',
                  style: TextStyle(
                    color: Color(0xFF1B5E20),
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(24),
            ),
            child: Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: (capture) {
                    final code = capture.barcodes.firstOrNull?.rawValue;
                    if (code != null) _onQrDetected(code);
                  },
                ),
                Center(
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.black54,
                    child: const Text(
                      'Irányítsd a QR-kódra a keretet',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_history.isNotEmpty)
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nemrég beolvasva (${_history.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _history.length,
                      itemBuilder: (_, i) => ListTile(
                        leading: const Icon(
                          Icons.check_circle,
                          color: Color(0xFF4CAF50),
                          size: 20,
                        ),
                        title: Text(
                          _history[i]['name'] ?? 'Ismeretlen',
                          style: const TextStyle(fontSize: 13),
                        ),
                        trailing: Text(
                          '${_history[i]['points'] ?? '?'} pt',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildResult() {
    final s = _station!;
    final alreadyDone = s['alreadyDone'] == true;
    final points = (s['points'] as num?)?.toInt() ?? 10;
    final name = s['name']?.toString() ?? 'Állomás';
    final unlockContent = s['unlockContent']?.toString() ?? '';
    final extraInfo = s['extraInfo']?.toString() ?? '';
    final imageUrl = _primaryImageUrl(s);
    final newAch =
        (s['newAchievements'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final offlineQueued = s['offlineQueued'] == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 12),
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: OfflineImage.network(
                imageUrl,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, trace) => const SizedBox.shrink(),
              ),
            ),
          const SizedBox(height: 20),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: alreadyDone
                  ? Colors.grey.shade200
                  : const Color(0xFF4CAF50).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              alreadyDone ? Icons.repeat_rounded : Icons.check_circle_rounded,
              size: 48,
              color: alreadyDone ? Colors.grey : const Color(0xFF4CAF50),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: alreadyDone
                  ? Colors.grey.shade100
                  : Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.star_rounded,
                  color: alreadyDone ? Colors.grey : Colors.amber,
                ),
                const SizedBox(width: 6),
                Text(
                  alreadyDone
                      ? 'Már feloldott (+0 pt)'
                      : (offlineQueued
                            ? ('Offline sorban (+$points pt)')
                            : ('+$points pont')),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: alreadyDone ? Colors.grey : Colors.amber.shade700,
                  ),
                ),
              ],
            ),
          ),
          if (newAch.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF9C4), Color(0xFFFFF3E0)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.emoji_events, color: Colors.amber, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Új jutalom feloldva! 🎉',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...newAch.map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Text(
                            a['icon']?.toString() ?? '🏆',
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a['name']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                if ((a['description']?.toString() ?? '')
                                    .isNotEmpty)
                                  Text(
                                    a['description'].toString(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (unlockContent.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lock_open, color: Colors.amber, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Feloldott tartalom',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    unlockContent,
                    style: const TextStyle(fontSize: 14, height: 1.6),
                  ),
                ],
              ),
            ),
          ],
          if (extraInfo.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Color(0xFF667EEA),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      extraInfo,
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Újabb beolvasás'),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMsg ?? 'Ismeretlen hiba',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh),
              label: const Text('Újrapróbálás'),
            ),
          ],
        ),
      ),
    );
  }

  void _showHistory(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Beolvasási előzmények',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _history.length,
                itemBuilder: (_, i) {
                  final st = _history[i];
                  return ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF4CAF50),
                      child: Icon(Icons.check, color: Colors.white, size: 18),
                    ),
                    title: Text(st['name'] ?? 'Ismeretlen'),
                    subtitle: Text(st['description'] ?? ''),
                    trailing: Text(
                      '${st['points'] ?? '?'} pt',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

