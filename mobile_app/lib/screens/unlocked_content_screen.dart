import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/image_normalizer.dart';
import '../widgets/station_image_viewer.dart';
import '../widgets/unlocked_card.dart';

class UnlockedContentScreen extends StatefulWidget {
  const UnlockedContentScreen({super.key});

  @override
  State<UnlockedContentScreen> createState() => _UnlockedContentScreenState();
}

class _UnlockedContentScreenState extends State<UnlockedContentScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _unlockedItems = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Set<String> _idsFromDynamic(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).toSet();
    }
    if (raw is Map) {
      return raw.entries
          .where((entry) => entry.value == true || entry.value == 1)
          .map((entry) => entry.key.toString())
          .toSet();
    }
    return <String>{};
  }

  Future<Set<String>> _loadCompletedStationIds(String uid) async {
    final ids = <String>{};

    final progressDoc = await _firestore.collection('user_progress').doc(uid).get();
    final data = progressDoc.data();
    if (data != null) {
      ids.addAll(_idsFromDynamic(data['completedStations']));
      ids.addAll(_idsFromDynamic(data['completedStationIds']));
      ids.addAll(_idsFromDynamic(data['completed_stations']));
    }

    final subSnap = await _firestore
        .collection('user_progress')
        .doc(uid)
        .collection('completed_stations')
        .get();
    ids.addAll(subSnap.docs.map((d) => d.id));

    return ids;
  }

  Future<void> _load() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('Nem azonosított felhasználó.');

      final completedIds = await _loadCompletedStationIds(uid);
      if (completedIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _unlockedItems = [];
          _isLoading = false;
        });
        return;
      }

      final stationsSnap = await _firestore.collection('stations').get();
      final unlocked = <Map<String, dynamic>>[];

      for (final doc in stationsSnap.docs) {
        if (!completedIds.contains(doc.id)) continue;
        final data = doc.data();
        final stationName = (data['name'] ?? 'Ismeretlen állomás').toString();

        final funFact = (data['funFact'] ?? '').toString().trim();
        if (funFact.isNotEmpty) {
          unlocked.add({
            'id': '${doc.id}_funfact',
            'stationName': stationName,
            'title': 'Fun fact',
            'content': funFact,
            'type': 'funFact',
            'images': photoListFromDoc(
              data,
              preferred: data['funFactImageUrl']?.toString(),
            ),
          });
        }

        final extra = (data['unlockContent'] ?? '').toString().trim();
        final unlockImage = (data['unlockContentImageUrl'] ?? '').toString().trim();
        if (extra.isNotEmpty) {
          unlocked.add({
            'id': '${doc.id}_unlock',
            'stationName': stationName,
            'title': 'Feloldott tartalom',
            'content': extra,
            'type': 'unlock',
            'images': photoListFromDoc(data, preferred: unlockImage),
          });
        }
      }

      unlocked.sort((a, b) {
        final byStation =
            a['stationName'].toString().compareTo(b['stationName'].toString());
        if (byStation != 0) return byStation;
        return a['title'].toString().compareTo(b['title'].toString());
      });

      if (!mounted) return;
      setState(() {
        _unlockedItems = unlocked;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Hiba: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feloldott tartalmak'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/var.jpg', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: Container(
              color: const Color(0xFFF2EBDD).withValues(alpha: 0.97),
            ),
          ),
          SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 56,
                            color: Colors.red.shade300,
                          ),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Újrapróbálás'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _unlockedItems.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.lock_outline,
                            size: 64,
                            color: Color(0xFFB0A090),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Még nincsenek feloldott tartalmak',
                            style: Theme.of(context).textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Teljesíts állomásokat a térképen, hogy feloldhasd a tartalmakat.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF8B7355),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      itemCount: _unlockedItems.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF312E81),
                                    Color(0xFF7C3AED),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF7C3AED).withValues(
                                      alpha: 0.28,
                                    ),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 54,
                                    height: 54,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: const Icon(
                                      Icons.auto_awesome_rounded,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${_unlockedItems.length} feloldott tartalom',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        const Text(
                                          'Minden teljesített állomás új vizuális vagy szöveges meglepetéseket nyit meg.',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            height: 1.45,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        final item = _unlockedItems[index - 1];
                        return UnlockedCard(
                          item: item,
                          index: index,
                          onTapImage: () {
                            final images =
                                (item['images'] as List<String>? ?? const []);
                            if (images.isNotEmpty) {
                              showStationImageViewer(context, images, 0);
                            }
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
