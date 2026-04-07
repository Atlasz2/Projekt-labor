import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/offline_sync_service.dart';
import 'accommodation_screen.dart';
import 'camera_screen.dart';
import 'contact_screen.dart';
import 'events_screen.dart';
import 'history_screen.dart';
import 'map_trips_screen.dart';
import 'profile_screen.dart';
import 'unlocked_content_screen.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  late final ScrollController _scrollController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final OfflineSyncService _offlineSyncService = OfflineSyncService();

  bool _showTopAchievementBanner = false;
  String _bannerTitle = '';
  String _bannerSubtitle = '';
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _loadPendingAchievementBanner();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPendingAchievementBanner() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = _firestore.collection('user_progress').doc(uid);
    final doc = await ref.get();
    final data = doc.data();
    final banner = data?['pendingAchievementBanner'];
    if (banner is! Map) return;

    final title = (banner['title'] ?? '').toString();
    final subtitle = (banner['subtitle'] ?? '').toString();
    if (title.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _bannerTitle = title;
      _bannerSubtitle = subtitle;
      _showTopAchievementBanner = true;
    });

    await ref.set({
      'pendingAchievementBanner': FieldValue.delete(),
    }, SetOptions(merge: true));

    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _showTopAchievementBanner = false);
    });
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kijelentkezes'),
        content: const Text('Biztosan kijelentkezel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Megse'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kijelentkezes'),
          ),
        ],
      ),
    );
    if (confirmed == true) await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final items = <_MenuItem>[
      _MenuItem('Terkep es turak', 'GPS, utvonal es allomasok', Icons.map_outlined, const Color(0xFF667EEA), const MapTripsScreen()),
      _MenuItem('QR beolvasas', 'Pontok es esemeny pecsetek', Icons.qr_code_scanner, const Color(0xFF4CAF50), const CameraScreen()),
      _MenuItem('Rendezvenyek', 'Kepek, reszletek, pecsetvadaszat', Icons.celebration_outlined, const Color(0xFFFF9800), const EventsScreen()),
      _MenuItem('Nagyvazsony tortenete', 'Idovonal es helytortenet', Icons.history_edu_outlined, const Color(0xFF8E44AD), const HistoryScreen()),
      _MenuItem('Szallas es etterem', 'Kepek, arak, hivas', Icons.hotel_outlined, const Color(0xFFE91E63), const AccommodationScreen()),
      _MenuItem('Feloldott tartalmak', 'Gyujtott elmenyek es jelzesek', Icons.collections_outlined, const Color(0xFFFF6B6B), const UnlockedContentScreen()),
      _MenuItem('Kapcsolat', 'Elerhetosegek es iroda', Icons.call_outlined, const Color(0xFF0097A7), const ContactScreen()),
    ];

    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width < 420 ? 1 : (width < 900 ? 2 : 3);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2EBDD),
        surfaceTintColor: const Color(0xFFF2EBDD),
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.account_circle_outlined, size: 28),
          tooltip: 'Fiokom',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
        ),
        title: const Text('Nagyvazsony'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            onPressed: () => _handleLogout(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/var.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFF2EBDD).withValues(alpha: 0.48),
                    const Color(0xFFF2EBDD).withValues(alpha: 0.60),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_showTopAchievementBanner)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.pink.withValues(alpha: 0.35),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.emoji_events, color: Colors.amberAccent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_bannerTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                Text(_bannerSubtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ValueListenableBuilder<bool>(
                    valueListenable: _offlineSyncService.onlineNotifier,
                    builder: (context, online, _) => Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Icon(
                          online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                          size: 16,
                          color: online ? const Color(0xFF2D6A4F) : const Color(0xFFA16207),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Fedezd fel Nagyvazsonyt',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Color(0xFF1F2937)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2EBDD).withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: ScrollConfiguration(
                          behavior: const _NoGlowScrollBehavior(),
                          child: GridView.builder(
                            key: const PageStorageKey('main-menu-grid'),
                            controller: _scrollController,
                            padding: const EdgeInsets.all(4),
                            physics: const ClampingScrollPhysics(),
                            clipBehavior: Clip.hardEdge,
                            itemCount: items.length,
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 2,
                              mainAxisSpacing: 2,
                              childAspectRatio: width < 420 ? 2.9 : 1.28,
                            ),
                            itemBuilder: (_, index) => _MenuCard(item: items[index]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget page;
  _MenuItem(this.title, this.subtitle, this.icon, this.color, this.page);
}

class _MenuCard extends StatelessWidget {
  final _MenuItem item;
  const _MenuCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => item.page)),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD1D5DB), width: 1.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFF3F4F6),
                child: Icon(item.icon, color: item.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
                    const SizedBox(height: 4),
                    Text(item.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoGlowScrollBehavior extends ScrollBehavior {
  const _NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}






