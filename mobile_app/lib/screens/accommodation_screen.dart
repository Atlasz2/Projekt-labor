import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../utils/image_normalizer.dart';
import '../widgets/offline_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/project_filter.dart';
import '../utils/venue_info.dart';

class AccommodationScreen extends StatefulWidget {
  const AccommodationScreen({super.key});

  @override
  State<AccommodationScreen> createState() => _AccommodationScreenState();
}

class _AccommodationScreenState extends State<AccommodationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Kollekciónként egyszer létrehozott stream — a build-ben létrehozott
  // snapshots() minden újraépítéskor (pl. tab-váltáskor) újra-előfizetett
  // volna, ami akadozást okoz.
  late final Map<String, Stream<QuerySnapshot>> _streams = {
    'accommodations': _firestore.collection('accommodations').snapshots(),
    'restaurants': _firestore.collection('restaurants').snapshots(),
  };

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

  String _safe(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    if (value is String) return value.trim().isEmpty ? fallback : value.trim();
    return value.toString().trim().isEmpty ? fallback : value.toString().trim();
  }

  /// Külső alkalmazás (böngésző, tárcsázó) megnyitása; ha nem sikerül,
  /// a felhasználó visszajelzést kap.
  Future<void> _open(
    Uri uri, {
    LaunchMode mode = LaunchMode.platformDefault,
  }) async {
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: mode);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A hivatkozás nem nyitható meg ezen az eszközön.'),
        ),
      );
    }
  }

  Future<void> _launchPhone(String phone) =>
      _open(Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^\d+]'), '')));

  void _openImageViewer(List<String> photos, int initialIndex) {
    if (photos.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            PageView.builder(
              controller: PageController(initialPage: initialIndex),
              itemCount: photos.length,
              itemBuilder: (_, index) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: OfflineImage.network(
                    photos[index],
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 18,
              right: 18,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Bezárás',
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoCarousel(List<String> photos, {double height = 190}) {
    if (photos.isEmpty) {
      return Container(
        height: height,
        color: const Color(0xFFE7E0CF),
        child: const Center(
          child: Icon(
            Icons.photo_library_outlined,
            size: 52,
            color: Color(0xFF8A8270),
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: PageView.builder(
        itemCount: photos.length,
        itemBuilder: (context, index) => GestureDetector(
          onTap: () => _openImageViewer(photos, index),
          child: Stack(
            fit: StackFit.expand,
            children: [
              OfflineImage.network(
                photos[index],
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: const Color(0xFFE5E7EB),
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A kártya és a részletező lap tömör adatsorai (csak a kitöltött mezők).
  List<({IconData icon, String text})> _facts(
    Map<String, dynamic> item, {
    required bool isRestaurant,
  }) {
    final facts = <({IconData icon, String text})>[];
    void add(IconData icon, String label, String value) {
      if (value.isNotEmpty) facts.add((icon: icon, text: '$label: $value'));
    }

    if (isRestaurant) {
      add(Icons.restaurant_menu_outlined, 'Konyha', _safe(item['cuisine']));
      add(Icons.payments_outlined, 'Árszint', priceLabel(item['priceRange']));
    } else {
      add(
        Icons.payments_outlined,
        'Ár / éj',
        priceLabel(item['pricePerNight']),
      );
      add(Icons.group_outlined, 'Kapacitás', capacityLabel(item['capacity']));
    }
    return facts;
  }

  Widget _factList(List<({IconData icon, String text})> facts) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in facts)
          Chip(
            avatar: Icon(f.icon, size: 18),
            label: Text(f.text),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  void _showDetails(Map<String, dynamic> item, {required bool isRestaurant}) {
    final photos = photoListFromDoc(item);
    final website = websiteUri(item['website']);
    final phone = _safe(item['phone']);
    final name = _safe(item['name'], fallback: 'Ismeretlen');
    final type = venueTypeLabel(
      _safe(item['type']),
      isRestaurant: isRestaurant,
    );
    final facts = _facts(item, isRestaurant: isRestaurant);
    final desc = _safe(item['description']);
    final address = _safe(item['address']);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.42,
          maxChildSize: 0.96,
          expand: false,
          builder: (ctx, scroll) {
            return SingleChildScrollView(
              controller: scroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _photoCarousel(photos, height: 220),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (type.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Chip(label: Text(type)),
                        ],
                        if (facts.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _factList(facts),
                        ],
                        if (address.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(address)),
                            ],
                          ),
                        ],
                        if (desc.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            desc,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              height: 1.55,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            if (phone.isNotEmpty)
                              FilledButton.icon(
                                onPressed: () => _launchPhone(phone),
                                icon: const Icon(Icons.phone_outlined),
                                label: Text(phone),
                              ),
                            if (website != null)
                              FilledButton.tonalIcon(
                                onPressed: () => _open(
                                  website,
                                  mode: LaunchMode.externalApplication,
                                ),
                                icon: const Icon(Icons.open_in_new_rounded),
                                label: const Text('Weboldal megnyitása'),
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

  Widget _buildList({required String collection, required bool isRestaurant}) {
    return StreamBuilder<QuerySnapshot>(
      stream: _streams[collection],
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Az adatok betöltése nem sikerült. Ellenőrizd a kapcsolatot.',
            ),
          );
        }

        // Csak ennek a településnek a szállásai / vendéglátóhelyei.
        final docs = (snapshot.data?.docs ?? [])
            .where((d) => inActiveProject(d.data() as Map<String, dynamic>?))
            .toList();
        if (docs.isEmpty) {
          return Center(
            child: Text(
              isRestaurant ? 'Nincsenek éttermek.' : 'Nincsenek szállások.',
            ),
          );
        }

        final items = docs
            .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
            .toList();

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (_, index) {
            final item = items[index];
            final photos = photoListFromDoc(item);
            final type = venueTypeLabel(
              _safe(item['type']),
              isRestaurant: isRestaurant,
            );
            final address = _safe(item['address']);
            final facts = _facts(item, isRestaurant: isRestaurant);
            final hasWebsite = websiteUri(item['website']) != null;

            return Card(
              margin: const EdgeInsets.only(bottom: 14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _showDetails(item, isRestaurant: isRestaurant),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _photoCarousel(photos, height: 180),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _safe(item['name'], fallback: 'Ismeretlen'),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                          if (type.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              type,
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                          // A cím a listában is látszik – enélkül a felhasználó
                          // nem tudja, hol van a hely.
                          if (address.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.place_outlined,
                                  size: 16,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    address,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (facts.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _factList(facts),
                          ],
                          const SizedBox(height: 10),
                          Text(
                            _safe(
                              item['description'],
                              fallback: 'Érintsd meg a részletekhez.',
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              height: 1.45,
                            ),
                          ),
                          if (hasWebsite) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.language_outlined,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Weboldal a részleteknél',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
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
        title: const Text('Szállás és étterem'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Szállások'),
            Tab(text: 'Éttermek'),
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
