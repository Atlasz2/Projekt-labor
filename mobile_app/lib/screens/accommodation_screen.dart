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
          return Center(child: Text("Hiba: ${snapshot.error}"));
        }
        final accommodations = snapshot.data?.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            "id": doc.id,
            "name": _safeString(data["name"]),
            "type": _safeString(data["type"]),
            "pricePerNight": _safeString(data["pricePerNight"]),
            "capacity": _safeString(data["capacity"]),
            "description": _safeString(data["description"]),
          };
        }).toList() ?? [];
        if (accommodations.isEmpty) {
          return const Center(child: Text("Nincsenek szállások"));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: accommodations.length,
          itemBuilder: (context, index) =>
              _buildPlaceCard(accommodations[index], isRestaurant: false),
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
          return Center(child: Text("Hiba: ${snapshot.error}"));
        }
        final restaurants = snapshot.data?.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            "id": doc.id,
            "name": _safeString(data["name"]),
            "type": _safeString(data["type"]),
            "cuisine": _safeString(data["cuisine"]),
            "priceRange": _safeString(data["priceRange"]),
            "description": _safeString(data["description"]),
          };
        }).toList() ?? [];
        if (restaurants.isEmpty) {
          return const Center(child: Text("Nincsenek éttermek"));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: restaurants.length,
          itemBuilder: (context, index) =>
              _buildPlaceCard(restaurants[index], isRestaurant: true),
        );
      },
    );
  }

  Widget _buildPlaceCard(Map<String, dynamic> place, {required bool isRestaurant}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showPlaceDetails(context, place, isRestaurant: isRestaurant),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                place["name"] as String,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              if ((place["type"] as String).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    "\u{1F4CC} ${place["type"]}",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              if (isRestaurant && (place["cuisine"] as String).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    "\u{1F374} ${place["cuisine"]}",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              if (!isRestaurant && (place["pricePerNight"] as String).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    "\u{1F3F7} ${place["pricePerNight"]} Ft/éj",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              if (isRestaurant && (place["priceRange"] as String).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    "\u{1F4B0} ${place["priceRange"]}",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => _showPlaceDetails(context, place, isRestaurant: isRestaurant),
                child: const Text("Részletek"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPlaceDetails(BuildContext context, Map<String, dynamic> place, {required bool isRestaurant}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(place["name"] as String),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if ((place["type"] as String).isNotEmpty) ...[
                Text("\u{1F4CC} Típus: ${place["type"]}", style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
              ],
              if (!isRestaurant && (place["pricePerNight"] as String).isNotEmpty) ...[
                Text("\u{1F3F7} Ár: ${place["pricePerNight"]} Ft/éj", style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
              ],
              if (!isRestaurant && (place["capacity"] as String).isNotEmpty) ...[
                Text("\u{1F465} Férőhely: ${place["capacity"]} fő", style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
              ],
              if (isRestaurant && (place["cuisine"] as String).isNotEmpty) ...[
                Text("\u{1F374} Konyha: ${place["cuisine"]}", style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
              ],
              if (isRestaurant && (place["priceRange"] as String).isNotEmpty) ...[
                Text("\u{1F4B0} Árkategória: ${place["priceRange"]}", style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
              ],
              if ((place["description"] as String).isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(place["description"] as String),
              ],
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Bezárás"))],
      ),
    );
  }
}
