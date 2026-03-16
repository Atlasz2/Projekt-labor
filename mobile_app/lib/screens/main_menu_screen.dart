import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'map_trips_screen.dart';
import 'camera_screen.dart';
import 'events_screen.dart';
import 'history_screen.dart';
import 'contact_screen.dart';
import 'accommodation_screen.dart';
import 'profile_screen.dart';

class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

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
        subtitle: 'Útvonalak és aktív túrák',
        icon: Icons.map_outlined,
        color: const Color(0xFF667EEA),
        page: const MapTripsScreen(),
      ),
      _MenuItem(
        title: 'QR beolvasás',
        subtitle: 'Pontgyűjtés állomásokkal',
        icon: Icons.qr_code_scanner,
        color: const Color(0xFF4CAF50),
        page: const CameraScreen(),
      ),
      _MenuItem(
        title: 'Rendezvények',
        subtitle: 'Közelgő események',
        icon: Icons.celebration_outlined,
        color: const Color(0xFFFF9800),
        page: const EventsScreen(),
      ),
      _MenuItem(
        title: 'Történelem',
        subtitle: 'Nagyvázsony múltja',
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
        subtitle: 'Szállások, vendéglátás',
        icon: Icons.hotel_outlined,
        color: const Color(0xFFE91E63),
        page: const AccommodationScreen(),
      ),
      _MenuItem(
        title: 'Fiókom',
        subtitle: 'Profil és ranglista',
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
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF667EEA),
                    const Color(0xFF667EEA).withValues(alpha: 0.82),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fedezd fel Nagyvázsonyt',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Válassz egy menüpontot a túrákhoz, rendezvényekhez vagy a profilodhoz.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: GridView.builder(
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
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => item.page));
      },
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: item.color.withValues(alpha: 0.24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 23,
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
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
