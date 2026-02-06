import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AccommodationScreen extends StatefulWidget {
  const AccommodationScreen({super.key});

  @override
  State<AccommodationScreen> createState() => _AccommodationScreenState();
}

class _AccommodationScreenState extends State<AccommodationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final List<Map<String, dynamic>> _dummyAccommodations = [
    {
      'name': 'Nagyvázsony Kastély Hotel',
      'rating': 4.7,
      'phone': '+36 88 564 000',
      'description': 'Luxus szálloda a történelmi kastély mellett.',
      'address': 'Nagyvázsony, Kastély utca 1.'
    },
    {
      'name': 'Vínás Völgy Panzió',
      'rating': 4.5,
      'phone': '+36 88 564 111',
      'description': 'Gemütliches Gästehaus mit herrlichem Ausblick auf die Weinberge.',
      'address': 'Nagyvázsony, Völgy utca 12.'
    },
    {
      'name': 'Történeti Fogadó',
      'rating': 4.3,
      'phone': '+36 88 564 222',
      'description': 'Tradicionális magyar fogadó a történelmi belvárosban.',
      'address': 'Nagyvázsony, Fő tér 5.'
    },
  ];

  final List<Map<String, dynamic>> _dummyRestaurants = [
    {
      'name': 'Vár Étterem',
      'cuisine': 'Magyar',
      'rating': 4.8,
      'phone': '+36 88 564 333',
      'description': 'Autentikus magyar konyhát kínál a kastély árnyékában.',
      'address': 'Nagyvázsony, Kastély utca 2.'
    },
    {
      'name': 'Borozó Kúria',
      'cuisine': 'Borpárosítás',
      'rating': 4.6,
      'phone': '+36 88 564 444',
      'description': 'Prémium borpárosítási élmény helyi borászatokkal.',
      'address': 'Nagyvázsony, Szőlő út 15.'
    },
    {
      'name': 'Családi Konyha',
      'cuisine': 'Magyar konyha',
      'rating': 4.4,
      'phone': '+36 88 564 555',
      'description': 'Családias hangulatú étterem házias magyar ételekkel.',
      'address': 'Nagyvázsony, Petőfi utca 8.'
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Szállások & Vendéglátás'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Szállások'),
            Tab(text: 'Étterme'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAccommodationList(),
          _buildRestaurantList(),
        ],
      ),
    );
  }

  Widget _buildAccommodationList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('accommodations').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final accommodations = snapshot.data?.docs.isEmpty ?? true
            ? _dummyAccommodations
            : snapshot.data!.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: accommodations.length,
          itemBuilder: (context, index) {
            final place = accommodations[index];
            return _buildPlaceCard(place, isRestaurant: false);
          },
        );
      },
    );
  }

  Widget _buildRestaurantList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('restaurants').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final restaurants = snapshot.data?.docs.isEmpty ?? true
            ? _dummyRestaurants
            : snapshot.data!.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: restaurants.length,
          itemBuilder: (context, index) {
            final place = restaurants[index];
            return _buildPlaceCard(place, isRestaurant: true);
          },
        );
      },
    );
  }

  Widget _buildPlaceCard(Map<String, dynamic> place, {required bool isRestaurant}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showPlaceDetails(context, place),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      place['name'] as String,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.star, size: 16, color: Colors.amberAccent),
                      const SizedBox(width: 4),
                      Text(
                        '${place['rating']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Text(
                    isRestaurant ? place['cuisine']?.toString() ?? '' : place['phone']?.toString() ?? '',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.phone),
                      onPressed: () {},
                      label: const Text('Hívás'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.info),
                      onPressed: () => _showPlaceDetails(context, place),
                      label: const Text('Info'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPlaceDetails(BuildContext context, Map<String, dynamic> place) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(place['name'].toString()),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(Icons.location_on, size: 60, color: Colors.blue),
                ),
              ),
              const SizedBox(height: 16),
              _detailRow('Cím:', place['address']?.toString() ?? ''),
              _detailRow('Telefon:', place['phone']?.toString() ?? ''),
              _detailRow('Értékelés:', '⭐ ${place['rating'] ?? 0.0}'),
              if (place['cuisine'] != null)
                _detailRow('Konyha:', place['cuisine']?.toString() ?? ''),
              const SizedBox(height: 12),
              const Text('Leírás:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(place['description']?.toString() ?? 'Nincs leírás elérhető.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Bezárás')),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
