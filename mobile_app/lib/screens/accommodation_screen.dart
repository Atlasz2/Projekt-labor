import 'package:cloud_firestore/cloud_firestore.dart';
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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

  String _safe(dynamic v, {String fallback = ''}) {
    if (v == null) return fallback;
    if (v is String) return v.trim().isEmpty ? fallback : v.trim();
    if (v is Map && v.containsKey('seconds')) return fallback;
    return v.toString().trim().isEmpty ? fallback : v.toString().trim();
  }

  Future<void> _launchUrl(String url) async {
    if (url.isEmpty) return;
    final raw = url.startsWith('http') ? url : 'https://$url';
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nem sikerült megnyitni a weboldalt.')),
        );
      }
    }
  }

  Future<void> _launchPhone(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (!await launchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nem sikerült hívni a számot.')),
        );
      }
    }
  }

  void _showDetails(BuildContext context, Map<String, dynamic> item,
      {required bool isRestaurant}) {
    final imageUrl = _safe(item['imageUrl']);
    final website = _safe(item['website']);
    final phone = _safe(item['phone']);
    final name = _safe(item['name'], fallback: 'Ismeretlen');
    final type = _safe(item['type']);
    final desc = _safe(item['description']);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (ctx, scroll) {
            return SingleChildScrollView(
              controller: scroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (imageUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20)),
                      child: Image.network(
                        imageUrl,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, st) =>
                            _headerPlaceholder(isRestaurant),
                      ),
                    )
                  else
                    _headerPlaceholder(isRestaurant),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold)),
                        if (type.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Chip(
                            label: Text(type,
                                style: const TextStyle(fontSize: 12)),
                            backgroundColor:
                                const Color(0xFF667EEA).withValues(alpha: 0.12),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (!isRestaurant) ...[
                          if (_safe(item['pricePerNight']).isNotEmpty)
                            _detailRow(Icons.hotel,
                                '${_safe(item["pricePerNight"])} Ft/éj'),
                          if (_safe(item['capacity']).isNotEmpty)
                            _detailRow(Icons.people_outline,
                                '${_safe(item["capacity"])} férőhely'),
                        ] else ...[
                          if (_safe(item['cuisine']).isNotEmpty)
                            _detailRow(Icons.restaurant_menu,
                                _safe(item['cuisine'])),
                          if (_safe(item['priceRange']).isNotEmpty)
                            _detailRow(Icons.payments_outlined,
                                _safe(item['priceRange'])),
                        ],
                        if (desc.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(desc,
                              style: TextStyle(
                                  color: Colors.grey.shade700,
                                  height: 1.5)),
                        ],
                        const SizedBox(height: 20),
                        if (phone.isNotEmpty || website.isNotEmpty)
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              if (phone.isNotEmpty)
                                FilledButton.icon(
                                  onPressed: () => _launchPhone(phone),
                                  icon: const Icon(Icons.phone, size: 16),
                                  label: Text(phone,
                                      overflow: TextOverflow.ellipsis),
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                        const Color(0xFF52B788),
                                  ),
                                ),
                              if (website.isNotEmpty)
                                FilledButton.icon(
                                  onPressed: () => _launchUrl(website),
                                  icon: const Icon(Icons.language, size: 16),
                                  label: const Text('Weboldal'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                        const Color(0xFF667EEA),
                                  ),
                                ),
                            ],
                          ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF667EEA)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(color: Colors.grey.shade700))),
        ],
      ),
    );
  }

  Widget _headerPlaceholder(bool isRestaurant) {
    return Container(
      height: 140,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
      ),
      child: Icon(
        isRestaurant ? Icons.restaurant : Icons.hotel,
        size: 56,
        color: Colors.white38,
      ),
    );
  }

  Widget _buildList({required String collection, required bool isRestaurant}) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection(collection).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text('Hiba: ${snapshot.error}',
                    textAlign: TextAlign.center),
              ],
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isRestaurant ? Icons.restaurant : Icons.hotel,
                  size: 72,
                  color: Colors.black26,
                ),
                const SizedBox(height: 16),
                Text(
                  isRestaurant
                      ? 'Nincsenek éttermek.'
                      : 'Nincsenek szállások.',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final items = docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {'id': doc.id, ...data};
        }).toList();

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final item = items[i];
            final imageUrl = _safe(item['imageUrl']);
            final name = _safe(item['name'], fallback: 'Ismeretlen');
            final type = _safe(item['type']);
            final website = _safe(item['website']);
            final phone = _safe(item['phone']);

            return Card(
              margin: const EdgeInsets.only(bottom: 14),
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (imageUrl.isNotEmpty)
                    Image.network(
                      imageUrl,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, st) =>
                          _headerPlaceholder(isRestaurant),
                    )
                  else
                    _headerPlaceholder(isRestaurant),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                        if (type.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(type,
                              style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 13)),
                        ],
                        if (!isRestaurant) ...[
                          if (_safe(item['pricePerNight']).isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(Icons.hotel, size: 14,
                                  color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text(
                                '${_safe(item["pricePerNight"])} Ft/éj',
                                style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12),
                              ),
                            ]),
                          ],
                        ] else ...[
                          if (_safe(item['cuisine']).isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(Icons.restaurant_menu, size: 14,
                                  color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text(
                                _safe(item['cuisine']),
                                style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12),
                              ),
                            ]),
                          ],
                        ],
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (phone.isNotEmpty)
                              IconButton(
                                onPressed: () => _launchPhone(phone),
                                icon: const Icon(Icons.phone_outlined),
                                color: const Color(0xFF52B788),
                                tooltip: 'Hívás',
                                visualDensity: VisualDensity.compact,
                              ),
                            if (website.isNotEmpty)
                              IconButton(
                                onPressed: () => _launchUrl(website),
                                icon: const Icon(Icons.language_outlined),
                                color: const Color(0xFF667EEA),
                                tooltip: 'Weboldal',
                                visualDensity: VisualDensity.compact,
                              ),
                            TextButton(
                              onPressed: () => _showDetails(context, item,
                                  isRestaurant: isRestaurant),
                              child: const Text('Részletek'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Szállások & Vendéglátás'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.hotel), text: 'Szállások'),
            Tab(icon: Icon(Icons.restaurant), text: 'Éttermek'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildList(collection: 'accommodations', isRestaurant: false),
          _buildList(collection: 'restaurants', isRestaurant: true),
        ],
      ),
    );
  }
}