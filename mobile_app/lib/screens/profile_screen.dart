import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Map<String, dynamic>? _currentUserData;
  List<Map<String, dynamic>> _allUsers = [];
  bool _isLoading = true;
  String? _error;
  int _userRank = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  int _safeCount(dynamic value) {
    if (value is List) return value.length;
    if (value is num) return value.toInt();
    return 0;
  }

  int _safeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  Future<void> _loadUserData() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final snapshot = await _firestore.collection('user_progress').get();
      final List<Map<String, dynamic>> users = snapshot.docs.map((doc) {
        final data = doc.data();
        final completedStations = _safeCount(data['completedStations']);
        final completedEvents = _safeCount(data['completedEvents']);
        final totalPoints = _safeInt(data['totalPoints']);

        return {
          'id': doc.id,
          'name': data['name']?.toString() ?? 'Ismeretlen',
          'email': data['email']?.toString() ?? '',
          'completedStations': completedStations,
          'completedEvents': completedEvents,
          'points': totalPoints,
          'currentTrip': data['currentTrip']?.toString() ?? 'Nincs túra',
        };
      }).toList();

      users.sort((a, b) => (b['points'] as int).compareTo(a['points'] as int));

      final currentUid = _auth.currentUser?.uid;
      Map<String, dynamic>? current = users.cast<Map<String, dynamic>?>().firstWhere(
            (item) => item?['id'] == currentUid,
            orElse: () => null,
          );

      if (current == null) {
        final userDoc = await _firestore.collection('users').doc(currentUid).get();
        final data = userDoc.data() ?? {};
        current = {
          'id': currentUid ?? 'unknown',
          'name': data['displayName']?.toString() ?? data['name']?.toString() ?? 'Felhasználó',
          'email': data['email']?.toString() ?? _auth.currentUser?.email ?? '',
          'completedStations': _safeCount(data['visitedStations']),
          'completedEvents': _safeCount(data['visitedEvents']),
          'points': _safeInt(data['points']),
          'currentTrip': 'Nincs túra',
        };
        users.add(Map<String, dynamic>.from(current));
      }

      users.sort((a, b) => (b['points'] as int).compareTo(a['points'] as int));
      final userRank = users.indexWhere((item) => item['id'] == current?['id']) + 1;

      setState(() {
        _currentUserData = current;
        _allUsers = users;
        _userRank = userRank > 0 ? userRank : 0;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Hiba az adatok betöltésekor: $e';
        _isLoading = false;
      });
    }
  }

  String _getRankMedal(int rank) {
    if (rank == 1) return '🥇';
    if (rank == 2) return '🥈';
    if (rank == 3) return '🥉';
    return '#$rank';
  }

  List<_Achievement> _buildAchievements() {
    final points = _safeInt(_currentUserData?['points']);
    final stations = _safeCount(_currentUserData?['completedStations']);
    final events = _safeCount(_currentUserData?['completedEvents']);

    return [
      _Achievement('Első lépések', 'Olvass be 1 QR-kódot', stations >= 1 || events >= 1, Icons.flag_outlined),
      _Achievement('Felfedező', 'Látogass meg legalább 3 állomást', stations >= 3, Icons.hiking_outlined),
      _Achievement('Túrahős', 'Gyűjts össze 140 pontot', points >= 140, Icons.workspace_premium_outlined),
      _Achievement('Eseményvadász', 'Vegyél részt 1 eseményen', events >= 1, Icons.celebration_outlined),
      _Achievement('Helyi legenda', 'Legyél top 3 a ranglistán', _userRank > 0 && _userRank <= 3, Icons.military_tech_outlined),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final currentPoints = _safeInt(_currentUserData?['points']);
    final stationCount = _safeCount(_currentUserData?['completedStations']);
    final eventCount = _safeCount(_currentUserData?['completedEvents']);
    final progressToReward = (currentPoints / 140).clamp(0.0, 1.0);
    final achievements = _buildAchievements();

    return Scaffold(
      appBar: AppBar(title: const Text('Fiókom')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _loadUserData, child: const Text('Újrapróbálás')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadUserData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildProfileHeader(),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _buildStatCard('Pontok', currentPoints.toString(), Icons.star, Colors.amber),
                          const SizedBox(width: 12),
                          _buildStatCard('Állomások', stationCount.toString(), Icons.place, Colors.blue),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildStatCard('Események', eventCount.toString(), Icons.celebration, Colors.deepOrange),
                          const SizedBox(width: 12),
                          _buildStatCard('Rang', _userRank == 0 ? '-' : _getRankMedal(_userRank), Icons.leaderboard, Colors.teal),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Jutalom előrehaladás', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: progressToReward,
                                minHeight: 10,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              const SizedBox(height: 8),
                              Text('$currentPoints / 140 pont'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: ListTile(
                          leading: Icon(Icons.map, color: Colors.blue.shade400),
                          title: const Text('Jelenlegi túra'),
                          subtitle: Text(_currentUserData?['currentTrip']?.toString() ?? 'Nincs túra'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Achievementek', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: achievements.map((a) => _AchievementChip(achievement: a)).toList(),
                      ),
                      const SizedBox(height: 16),
                      const Text('Rangsor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Card(
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _allUsers.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final user = _allUsers[index];
                            final isCurrentUser = user['id'] == _currentUserData?['id'];

                            return Container(
                              color: isCurrentUser ? Colors.blue.shade50 : Colors.transparent,
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Text(_getRankMedal(index + 1), style: const TextStyle(fontSize: 20)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(user['name'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                                        Text(
                                          '${_safeCount(user['completedStations'])} állomás · ${_safeCount(user['completedEvents'])} esemény',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${_safeInt(user['points'])} pont',
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
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade400, Colors.blue.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 42,
            backgroundColor: Colors.white,
            child: Icon(Icons.person, size: 48, color: Colors.blue),
          ),
          const SizedBox(height: 12),
          Text(
            _currentUserData?['name']?.toString() ?? 'Felhasználó',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            _currentUserData?['email']?.toString() ?? '',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            'Rang: ${_getRankMedal(_userRank)}',
            style: const TextStyle(color: Colors.white),
          ),
        ],
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
              Icon(icon, color: color, size: 30),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Achievement {
  final String title;
  final String description;
  final bool unlocked;
  final IconData icon;

  _Achievement(this.title, this.description, this.unlocked, this.icon);
}

class _AchievementChip extends StatelessWidget {
  final _Achievement achievement;

  const _AchievementChip({required this.achievement});

  @override
  Widget build(BuildContext context) {
    final bg = achievement.unlocked ? const Color(0xFFE7F5EA) : const Color(0xFFF3F4F6);
    final fg = achievement.unlocked ? const Color(0xFF166534) : const Color(0xFF6B7280);

    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(achievement.icon, size: 18, color: fg),
              const Spacer(),
              Icon(
                achievement.unlocked ? Icons.check_circle : Icons.lock_outline,
                size: 18,
                color: fg,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(achievement.title, style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
          const SizedBox(height: 4),
          Text(
            achievement.description,
            style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.84)),
          ),
        ],
      ),
    );
  }
}
