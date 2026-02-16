import "package:flutter/material.dart";
import "package:cloud_firestore/cloud_firestore.dart";

class AccommodationScreen extends StatefulWidget {
  const AccommodationScreen({super.key});

  @override
  State<AccommodationScreen> createState() => _AccommodationScreenState();
}

class _AccommodationScreenState extends State<AccommodationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _safeString(dynamic value) {
    if (value == null) return "";
    if (value is String) return value;
    if (value is Map && value.containsKey("seconds")) return "";
    return value.toString();
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Szállások & Vendéglátás"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Szállások"),
            Tab(text: "Étterem"),
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
      stream: _firestore.collection("accommodations").snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text("Hiba: ${snapshot.error}"),
              ],
            ),
          );
        }

        final accommodations = snapshot.data?.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            "id": doc.id,
            "name": _safeString(data["name"]),
            "address": _safeString(data["address"]),
            "phone": _safeString(data["phone"]),
            "email": _safeString(data["email"]),
            "description": _safeString(data["description"]),
            "rating": data["rating"] ?? 0.0,
          };
        }).toList() ?? [];

        if (accommodations.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hotel, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text("Nincsenek szállások"),
              ],
            ),
          );
        }

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
      stream: _firestore.collection("restaurants").snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text("Hiba: ${snapshot.error}"),
              ],
            ),
          );
        }

        final restaurants = snapshot.data?.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            "id": doc.id,
            "name": _safeString(data["name"]),
            "address": _safeString(data["address"]),
            "phone": _safeString(data["phone"]),
            "email": _safeString(data["email"]),
            "description": _safeString(data["description"]),
            "cuisine": _safeString(data["cuisine"]),
            "rating": data["rating"] ?? 0.0,
          };
        }).toList() ?? [];

        if (restaurants.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.restaurant, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text("Nincsenek éttermek"),
              ],
            ),
          );
        }

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
                      place["name"] as String,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if ((place["rating"] as num) > 0)
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 18),
                        const SizedBox(width: 4),
                        Text((place["rating"] as num).toString()),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (isRestaurant && (place["cuisine"] as String).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text("🍽️ ${place["cuisine"]}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      place["address"] as String,
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: () => _showPlaceDetails(context, place), child: const Text("Részletek")),
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
        title: Text(place["name"] as String),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if ((place["rating"] as num) > 0) ...[
                Row(children: [const Icon(Icons.star, color: Colors.amber), const SizedBox(width: 4), Text("${place["rating"]} / 5.0")]),
                const SizedBox(height: 12),
              ],
              Text("📍 ${place["address"]}", style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text("📞 ${place["phone"]}", style: const TextStyle(fontWeight: FontWeight.bold)),
              if ((place["email"] as String).isNotEmpty) ...[
                const SizedBox(height: 8),
                Text("✉️ ${place["email"]}", style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
              const SizedBox(height: 12),
              Text(place["description"] as String),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Bezárás"))],
      ),
    );
  }
}
