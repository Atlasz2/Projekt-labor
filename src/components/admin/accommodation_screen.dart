import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AccommodationScreen extends StatefulWidget {
  const AccommodationScreen({super.key});

  @override
  State<AccommodationScreen> createState() => _AccommodationScreenState();
}

class _AccommodationScreenState extends State<AccommodationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Szállás dummy adatok
  final List<Map<String, dynamic>> _accommodations = [
    {
      'name': 'Nagyvázsony Szálloda',
      'rating': 4.5,
      'phone': '+36 88 555 111',
      'website': 'www.nagyvazsonyszalloda.hu',
      'address': 'Fő u. 12, Nagyvázsony',
    },
    {
      'name': 'Történelmi Panzió',
      'rating': 4.2,
      'phone': '+36 88 555 222',
      'website': 'www.tortenelemipanzo.hu',
      'address': 'Vár u. 5, Nagyvázsony',
    },
    {
      'name': 'Völgy Szállás',
      'rating': 4.7,
      'phone': '+36 88 555 333',
      'website': 'www.volgy-szallas.hu',
      'address': 'Park u. 8, Nagyvázsony',
    },
  ];

  // Étterem dummy adatok
  final List<Map<String, dynamic>> _restaurants = [
    {
      'name': 'Vár Étterem',
      'rating': 4.6,
      'phone': '+36 88 666 111',
      'website': 'www.var-etterem.hu',
      'cuisine': 'Magyar konyha',
    },
    {
      'name': 'Történelmi Kert Vendéglő',
      'rating': 4.4,
      'phone': '+36 88 666 222',
      'website': 'www.tortortortenelmi-kert.hu',
      'cuisine': 'Nemzetközi',
    },
    {
      'name': 'Völgy Café',
      'rating': 4.3,
      'phone': '+36 88 666 333',
      'website': 'www.volgy-cafe.hu',
      'cuisine': 'Kávé & Desszert',
    },
  ];

  void _showDetails(BuildContext context, Map<String, dynamic> item, String type) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item['name'] ?? 'Hely'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _InfoRow('⭐', '${item['rating']}/5'),
              _InfoRow('📞', item['phone'] ?? '-'),
              _InfoRow(
                '🌐',
                item['website'] ?? '-',
              ),
              if (type == 'accommodation')
                _InfoRow('📍', item['address'] ?? '-')
              else
                _InfoRow('🍽️', item['cuisine'] ?? '-'),
            ],
          ),
        ),
        actions: [
          if (item['website'] != null)
            TextButton(
              onPressed: () async {
                final url = item['website'];
                if (await canLaunchUrl(Uri.parse('https://$url'))) {
                  // Handle URL launch
                }
              },
              child: const Text('Weboldal'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Bezárás'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '🏨 Szállások'),
            Tab(text: '🍽️ Éttermek'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // SZÁLLÁSOK
              ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _accommodations.length,
                itemBuilder: (context, index) {
                  final acc = _accommodations[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () =>
                          _showDetails(context, acc, 'accommodation'),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              acc['name'],
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _InfoRow('⭐', '${acc['rating']}/5'),
                            _InfoRow('📞', acc['phone']),
                            _InfoRow('📍', acc['address']),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              // ÉTTERMEK
              ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _restaurants.length,
                itemBuilder: (context, index) {
                  final rest = _restaurants[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () =>
                          _showDetails(context, rest, 'restaurant'),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rest['name'],
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _InfoRow('⭐', '${rest['rating']}/5'),
                            _InfoRow('🍽️', rest['cuisine']),
                            _InfoRow('📞', rest['phone']),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String icon;
  final String value;

  const _InfoRow(this.icon, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(icon),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
