import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'accommodation_screen.dart';
import 'camera_screen.dart';
import 'contact_screen.dart';
import 'events_screen.dart';
import 'history_screen.dart';
import 'map_trips_screen.dart';
import 'profile_screen.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  static double _lastOffset = 0;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(initialScrollOffset: _lastOffset)
      ..addListener(() {
        _lastOffset = _scrollController.offset;
      });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kijelentkezés'),
        content: const Text('Biztosan kijelentkezel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Mégse'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kijelentkezés'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = <_MenuItem>[
      _MenuItem(
        title: 'Térkép és túrák',
        subtitle: 'GPS, útvonal és állomások',
        icon: Icons.map_outlined,
        color: const Color(0xFF667EEA),
        page: const MapTripsScreen(),
      ),
      _MenuItem(
        title: 'QR beolvasás',
        subtitle: 'Pontok és esemény pecsétek',
        icon: Icons.qr_code_scanner,
        color: const Color(0xFF4CAF50),
        page: const CameraScreen(),
      ),
      _MenuItem(
        title: 'Rendezvények',
        subtitle: 'Képek, részletek, pecsétvadászat',
        icon: Icons.celebration_outlined,
        color: const Color(0xFFFF9800),
        page: const EventsScreen(),
      ),
      _MenuItem(
        title: 'Nagyvázsony története',
        subtitle: 'Idővonal és helytörténet',
        icon: Icons.history_edu_outlined,
        color: const Color(0xFF8E44AD),
        page: const HistoryScreen(),
      ),
      _MenuItem(
        title: 'Kapcsolat',
        subtitle: 'Elérhetőségek és iroda',
        icon: Icons.call_outlined,
        color: const Color(0xFF0097A7),
        page: const ContactScreen(),
      ),
      _MenuItem(
        title: 'Szállás és étterem',
        subtitle: 'Képek, linkek, hívás',
        icon: Icons.hotel_outlined,
        color: const Color(0xFFE91E63),
        page: const AccommodationScreen(),
      ),
      _MenuItem(
        title: 'Fiókom',
        subtitle: 'Ranglista és achievementek',
        icon: Icons.person_outline,
        color: const Color(0xFF2196F3),
        page: const ProfileScreen(),
      ),
    ];

    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width < 420 ? 1 : (width < 900 ? 2 : 3);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nagyvázsony'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: 'Kijelentkezés',
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
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFF2EBDD).withValues(alpha: 0.96),
                    const Color(0xFFE7DDC9).withValues(alpha: 0.92),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.93),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset(
                            'assets/logo.png',
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Fedezd fel Nagyvázsonyt',
                                style: TextStyle(
                                  color: Color(0xFF1F2937),
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Túrák, események, történetek és helyi élmények egy alkalmazásban.',
                                style: TextStyle(
                                  color: Color(0xFF475569),
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _MenuCard(item: item);
                      },
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

  _MenuItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.page,
  });
}

class _MenuCard extends StatelessWidget {
  final _MenuItem item;
  const _MenuCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => item.page));
      },
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: item.color.withValues(alpha: 0.42), width: 1.4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: item.color.withValues(alpha: 0.14),
                child: Icon(item.icon, color: item.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }
}

