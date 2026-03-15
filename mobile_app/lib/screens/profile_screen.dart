import "package:flutter/material.dart";
import "package:cloud_firestore/cloud_firestore.dart";

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _allUsers = [];
  bool _isLoading = true;
  String? _error;
  int _userRank = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      setState(() => _isLoading = true);

      // Load all users and sort by points
      final snapshot = await _firestore.collection("user_progress").get();
      
      final users = snapshot.docs.map((doc) {
        final data = doc.data();
        final completedStations = (data["completedStations"] as List?)?.length ?? 0;
        final points = completedStations * 10;
        
        return {
          "id": doc.id,
          "name": data["name"]?.toString() ?? "Ismeretlen",
          "email": data["email"]?.toString() ?? "",
          "completedStations": completedStations,
          "points": points,
          "currentTrip": data["currentTrip"]?.toString() ?? "Nincs túra",
        };
      }).toList();

      // Sort by points descending
      users.sort((a, b) => (b["points"] as int).compareTo(a["points"] as int));

      // Get current user (first one for demo)
      final currentUser = users.isNotEmpty ? users.first : null;
      final userRank = users.isNotEmpty ? (users.map((u) => u["id"]).toList().indexOf(currentUser?["id"] ?? "") + 1) : 0;

      setState(() {
        _userData = currentUser;
        _allUsers = users;
        _userRank = userRank;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = "Hiba az adatok betöltésekor: $e";
        _isLoading = false;
      });
    }
  }

  String _getRankMedal(int rank) {
    if (rank == 1) return "🥇";
    if (rank == 2) return "🥈";
    if (rank == 3) return "🥉";
    return "#$rank";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Fiókom"),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(_error!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadUserData,
                        child: const Text("Újrapróbálás"),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      // Profile Header
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.blue.shade400, Colors.blue.shade600],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Column(
                          children: [
                            const CircleAvatar(
                              radius: 50,
                              backgroundColor: Colors.white,
                              child: Icon(Icons.person, size: 60, color: Colors.blue),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _userData?["name"] ?? "Ismeretlen",
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Rang: ${_getRankMedal(_userRank)}",
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Stats Cards
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            _buildStatCard(
                              "Pontok",
                              (_userData?["points"] ?? 0).toString(),
                              Icons.star,
                              Colors.amber,
                            ),
                            const SizedBox(width: 12),
                            _buildStatCard(
                              "Állomások",
                              (_userData?["completedStations"] ?? 0).toString(),
                              Icons.location_on,
                              Colors.blue,
                            ),
                          ],
                        ),
                      ),

                      // Current Trip
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(Icons.map, color: Colors.blue.shade400, size: 28),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        "Jelenlegi túra",
                                        style: TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                      Text(
                                        _userData?["currentTrip"] ?? "Nincs túra",
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Rankings
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Rangsor",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Card(
                              child: ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _allUsers.length,
                                separatorBuilder: (_, _) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final user = _allUsers[index];
                                  final isCurrentUser = user["id"] == _userData?["id"];
                                  
                                  return Container(
                                    color: isCurrentUser
                                        ? Colors.blue.shade50
                                        : Colors.transparent,
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        Text(
                                          _getRankMedal(index + 1),
                                          style: const TextStyle(fontSize: 20),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                user["name"],
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                "${user["completedStations"]} állomás",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.shade100,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            "${user["points"]} pont",
                                            style: TextStyle(
                                              color: Colors.amber.shade900,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

