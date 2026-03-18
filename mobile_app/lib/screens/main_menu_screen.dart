import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
  static double _lastOffset = 0;
  late final ScrollController _scrollController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _showTopAchievementBanner = false;
  String _bannerTitle = '';
  String _bannerSubtitle = '';
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(initialScrollOffset: _lastOffset)
      ..addListener(() => _lastOffset = _scrollController.offset);
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

    await ref.set({'pendingAchievementBanner': FieldValue.delete()}, SetOptions(merge: true));

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
        title: const Text('Kijelentkezés'),
        content: const Text('Biztosan kijelentkezel?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Mégse')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Kijelentkezés')),
        ],
      ),
    );
    if (confirmed == true) await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final items = <_MenuItem>[
      _MenuItem('Térkép és túrák', 'GPS, útvonal és állomások', Icons.map_outlined, const Color(0xFF667EEA), const MapTripsScreen()),
      _MenuItem('QR beolvasás', 'Pontok és esemény pecsétek', Icons.qr_code_scanner, const Color(0xFF4CAF50), const CameraScreen()),
      _MenuItem('Rendezvények', 'Képek, részletek, pecsétvadászat', Icons.celebration_outlined, const Color(0xFFFF9800), const EventsScreen()),
      _MenuItem('Nagyvázsony története', 'Idővonal és helytörténet', Icons.history_edu_outlined, const Color(0xFF8E44AD), const HistoryScreen()),
      _MenuItem('Kapcsolat', 'Elérhetőségek és iroda', Icons.call_outlined, const Color(0xFF0097A7), const ContactScreen()),
      _MenuItem('Szállás és étterem', 'Képek, linkek, hívás', Icons.hotel_outlined, const Color(0xFFE91E63), const AccommodationScreen()),
      _MenuItem('Feloldott Tartalmak', 'Gyűjtött élmések és jelzések', Icons.collections_outlined, const Color(0xFFFF6B6B), const UnlockedContentScreen()),
      _MenuItem('Fiókom', 'Ranglista és achievementek', Icons.person_outline, const Color(0xFF2196F3), const ProfileScreen()),
    ];

    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width < 420 ? 1 : (width < 900 ? 2 : 3);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nagyvázsony'),
        actions: [
          IconButton(icon: const Icon(Icons.logout_outlined), onPressed: () => _handleLogout(context)),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/var.jpg', fit: BoxFit.cover)),
          Positioned.fill(
            child: Container(
              color: const Color(0xFFF2EBDD).withValues(alpha: 0.97),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_showTopAchievementBanner)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFEC4899)]),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.pink.withValues(alpha: 0.35), blurRadius: 14)],
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
                          )
                        ],
                      ),
                    ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 16, offset: const Offset(0, 8))],
                    ),
                    child: const Text('Fedezd fel Nagyvázsonyt', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Color(0xFF1F2937))),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: GridView.builder(
                      key: const PageStorageKey('main-menu-grid'),
                      controller: _scrollController,
                      itemCount: items.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: width < 420 ? 2.45 : 1.2,
                      ),
                      itemBuilder: (_, index) => _MenuCard(item: items[index]),
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
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => item.page)),
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, item.color.withValues(alpha: 0.09)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: item.color.withValues(alpha: 0.80), width: 1.8),
          boxShadow: [BoxShadow(color: item.color.withValues(alpha: 0.18), blurRadius: 22, offset: const Offset(0, 6))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(radius: 24, backgroundColor: item.color.withValues(alpha: 0.14), child: Icon(item.icon, color: item.color)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF111827))),
                    const SizedBox(height: 4),
                    Text(item.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF374151))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF374151)),
            ],
          ),
        ),
      ),
    );
  }
}
