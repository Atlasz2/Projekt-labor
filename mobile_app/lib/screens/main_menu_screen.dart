import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
            child: const Text('Nem'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Igen'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sikeresen kijelentkeztél!')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      _MenuItem(
        title: 'Térkép / Túrák',
        icon: Icons.map_outlined,
        color: const Color(0xFF667EEA),
        page: const SimplePage(
          title: 'Térkép / Túrák',
          body: 'Itt lesz a túrák térképes listája és útvonalak.',
        ),
      ),
      _MenuItem(
        title: 'Kamera',
        icon: Icons.qr_code_scanner,
        color: const Color(0xFF4CAF50),
        page: const SimplePage(
          title: 'Kamera',
          body: 'Itt lesz a QR-kód beolvasás.',
        ),
      ),
      _MenuItem(
        title: 'Rendezvények',
        icon: Icons.celebration_outlined,
        color: const Color(0xFFFF9800),
        page: const SimplePage(
          title: 'Rendezvények',
          body: 'Itt lesznek az aktív programok és események.',
        ),
      ),
      _MenuItem(
        title: 'Nagyvázsony története',
        icon: Icons.history_edu_outlined,
        color: const Color(0xFF8E44AD),
        page: const SimplePage(
          title: 'Nagyvázsony története',
          body: 'Itt lesz a történeti tartalom és leírások.',
        ),
      ),
      _MenuItem(
        title: 'Kapcsolat',
        icon: Icons.call_outlined,
        color: const Color(0xFF0097A7),
        page: const SimplePage(
          title: 'Kapcsolat',
          body: 'Itt lesznek elérhetőségek, cím, email, telefon.',
        ),
      ),
      _MenuItem(
        title: 'Szállások & Vendéglátás',
        icon: Icons.hotel_outlined,
        color: const Color(0xFFE91E63),
        page: const SimplePage(
          title: 'Szállások & Vendéglátás',
          body: 'Itt lesznek szállások, éttermek, vendéglátó helyek.',
        ),
      ),
    ];

    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width < 420 ? 2 : 3;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nagyvázsony'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Kijelentkezés',
            onPressed: () => _handleLogout(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.builder(
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.95,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return _MenuCard(item: item);
          },
        ),
      ),
    );
  }
}

class _MenuItem {
  final String title;
  final IconData icon;
  final Color color;
  final Widget page;

  _MenuItem({
    required this.title,
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
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => item.page),
        );
      },
      child: Ink(
        decoration: BoxDecoration(
          color: item.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: item.color.withValues(alpha: 0.2)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: item.color,
                child: Icon(item.icon, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                item.title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SimplePage extends StatelessWidget {
  final String title;
  final String body;

  const SimplePage({
    super.key,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }
}
