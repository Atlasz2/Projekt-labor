import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AccommodationScreen extends StatefulWidget {
  const AccommodationScreen({super.key});

  @override
  State<AccommodationScreen> createState() => _AccommodationScreenState();
}

class _AccommodationScreenState extends State<AccommodationScreen> with SingleTickerProviderStateMixin {
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

  String _safe(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    if (value is String) return value.trim().isEmpty ? fallback : value.trim();
    return value.toString().trim().isEmpty ? fallback : value.toString().trim();
  }

  List<String> _photoUrls(Map<String, dynamic> item) {
    final photos = item['photos'];
    if (photos is List && photos.isNotEmpty) {
      return photos
          .map((entry) {
            if (entry is String) return entry;
            if (entry is Map && entry['url'] != null) return entry['url'].toString();
            return '';
          })
          .where((url) => url.isNotEmpty)
          .cast<String>()
          .toList();
    }
    final photoUrls = item['photoUrls'];
    if (photoUrls is List && photoUrls.isNotEmpty) {
      return photoUrls.map((entry) => entry.toString()).toList();
    }
    final single = _safe(item['imageUrl']);
    return single.isEmpty ? <String>[] : <String>[single];
  }

  Future<void> _launchUrl(String url) async {
    final raw = url.startsWith('http') ? url : 'https://$url';
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _launchPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    await launchUrl(uri);
  }

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
                  child: Image.network(
                    photos[index],
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 18,
              right: 18,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF667EEA), Color(0xFF764BA2)]),
        ),
        child: const Center(
          child: Icon(Icons.photo_library_outlined, size: 58, color: Colors.white38),
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
              Image.network(
                photos[index],
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
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

  Widget _priceBlock(Map<String, dynamic> item) {
    final pricing = (item['pricing'] is Map) ? Map<String, dynamic>.from(item['pricing'] as Map) : <String, dynamic>{};
    final perPerson = (pricing['per_person'] is Map) ? (pricing['per_person']['price'] ?? item['pricePerPerson'] ?? 0) : (item['pricePerPerson'] ?? 0);
    final perApartment = (pricing['per_apartment'] is Map) ? (pricing['per_apartment']['price'] ?? item['pricePerNight'] ?? 0) : (item['pricePerNight'] ?? 0);
    final maxPersons = (pricing['per_apartment'] is Map) ? (pricing['per_apartment']['max_persons'] ?? item['capacity'] ?? 0) : (item['capacity'] ?? 0);

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF4F7FF), borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Per fo', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                const SizedBox(height: 6),
                Text('$perPerson Ft', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF3E8), borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Per apartman', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                const SizedBox(height: 6),
                Text('$perApartment Ft', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 6),
                Text('max $maxPersons fo', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showDetails(Map<String, dynamic> item, {required bool isRestaurant}) {
    final photos = _photoUrls(item);
    final website = _safe(item['website']);
    final phone = _safe(item['phone']);
    final name = _safe(item['name'], fallback: 'Ismeretlen');
    final type = _safe(item['type']);
    final desc = _safe(item['description']);
    final address = _safe(item['address']);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                        Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        if (type.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Chip(label: Text(type)),
                        ],
                        const SizedBox(height: 16),
                        if (!isRestaurant) _priceBlock(item),
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
                          Text(desc, style: TextStyle(color: Colors.grey.shade700, height: 1.55)),
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
                            if (website.isNotEmpty)
                              FilledButton.icon(
                                onPressed: () => _launchUrl(website),
                                icon: const Icon(Icons.language_outlined),
                                label: const Text('Weboldal'),
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
      stream: _firestore.collection(collection).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hiba: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(child: Text(isRestaurant ? 'Nincsenek ettermek.' : 'Nincsenek szallasok.'));
        }

        final items = docs.map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>}).toList();

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (_, index) {
            final item = items[index];
            final photos = _photoUrls(item);
            final type = _safe(item['type']);

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
                          Text(_safe(item['name'], fallback: 'Ismeretlen'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                          if (type.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(type, style: TextStyle(color: Colors.grey.shade600)),
                          ],
                          const SizedBox(height: 10),
                          if (!isRestaurant) _priceBlock(item),
                          const SizedBox(height: 10),
                          Text(
                            _safe(item['description'], fallback: 'Erintsd meg a reszletekhez.'),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey.shade700, height: 1.45),
                          ),
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
        title: const Text('Szallas es etterem'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Szallasok'), Tab(text: 'Ettermek')],
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

