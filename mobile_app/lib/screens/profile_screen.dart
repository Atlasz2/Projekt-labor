import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/leaderboard_service.dart';
import '../theme/app_colors.dart';
import '../utils/profile_stats.dart';
import '../widgets/achievement_chip.dart';
import '../widgets/data_rights_section.dart';
import '../widgets/profile_skeleton.dart';
import 'achievement_progress_screen.dart';

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
  List<Map<String, dynamic>> _newlyUnlockedAchievements = [];
  List<Map<String, dynamic>> _achievementDefinitions = [];
  Set<String> _unlockedAchievementIds = <String>{};

  bool _isLoading = true;
  bool _showAchievementBanner = false;
  String? _error;
  int _userRank = 0;
  Timer? _bannerDismissTimer;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  @override
  void dispose() {
    _bannerDismissTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadUserData(), _loadAchievementCatalogAndUnlocks()]);
  }

  Future<void> _loadUserData() async {
    try {
      setState(() {
        _isLoading = _currentUserData == null;
        _error = null;
      });

      final currentUid = _auth.currentUser?.uid;
      if (currentUid == null) {
        throw Exception('Nincs bejelentkezett felhasználó.');
      }

      // Fetch the two profile docs together; if the network is slow/unreachable
      // fall back to the local cache so the screen never hangs on a spinner.
      List<DocumentSnapshot<Map<String, dynamic>>> userDocs;
      try {
        userDocs = await Future.wait([
          _firestore.collection('user_progress').doc(currentUid).get(),
          _firestore.collection('users').doc(currentUid).get(),
        ]).timeout(const Duration(seconds: 10));
      } catch (_) {
        userDocs = await Future.wait([
          _firestore
              .collection('user_progress')
              .doc(currentUid)
              .get(const GetOptions(source: Source.cache)),
          _firestore
              .collection('users')
              .doc(currentUid)
              .get(const GetOptions(source: Source.cache)),
        ]);
      }

      final progressData = userDocs[0].data() ?? <String, dynamic>{};
      final userData = userDocs[1].data() ?? <String, dynamic>{};

      final current = <String, dynamic>{
        'id': currentUid,
        'name':
            userData['displayName']?.toString() ??
            userData['name']?.toString() ??
            progressData['name']?.toString() ??
            'Felhasználó',
        'email':
            userData['email']?.toString() ?? _auth.currentUser?.email ?? '',
        'completedStations': safeCount(progressData['completedStations']) > 0
            ? safeCount(progressData['completedStations'])
            : safeCount(userData['visitedStations']),
        'completedEvents': safeCount(progressData['completedEvents']) > 0
            ? safeCount(progressData['completedEvents'])
            : safeCount(userData['visitedEvents']),
        'points': safeInt(progressData['totalPoints']) > 0
            ? safeInt(progressData['totalPoints'])
            : safeInt(userData['points']),
        'currentTrip': progressData['currentTrip']?.toString() ?? 'Nincs túra',
      };

      // The public leaderboard is already kept fresh when points change (QR
      // scan / name setup), so don't block the profile render on this write.
      unawaited(
        LeaderboardService.syncEntry(
          uid: currentUid,
          displayName: current['name']?.toString(),
          points: safeInt(current['points']),
          completedStationsCount: safeInt(current['completedStations']),
          completedEventsCount: safeInt(current['completedEvents']),
        ).catchError((Object e) => debugPrint('Leaderboard sync skipped: $e')),
      );

      // Top list + rank count run together; if the leaderboard is slow or
      // unavailable, still show the profile (just without the ranking).
      List<QueryDocumentSnapshot<Map<String, dynamic>>> leaderboardDocs =
          const [];
      int? higherCount;
      try {
        final leaderboardResults = await Future.wait<Object>([
          _firestore
              .collection('public_leaderboard')
              .orderBy('points', descending: true)
              .limit(50)
              .get(),
          _firestore
              .collection('public_leaderboard')
              .where('points', isGreaterThan: safeInt(current['points']))
              .count()
              .get(),
        ]).timeout(const Duration(seconds: 10));
        leaderboardDocs =
            (leaderboardResults[0] as QuerySnapshot<Map<String, dynamic>>).docs;
        higherCount = (leaderboardResults[1] as AggregateQuerySnapshot).count;
      } catch (_) {
        // Leaderboard slow/unavailable — keep the profile usable without it.
      }

      final users = leaderboardDocs.map((doc) {
        final data = doc.data();
        return <String, dynamic>{
          'id': doc.id,
          'name': data['displayName']?.toString() ?? 'Felhasználó',
          'completedStations': safeInt(data['completedStationsCount']),
          'completedEvents': safeInt(data['completedEventsCount']),
          'points': safeInt(data['points']),
          'currentTrip': doc.id == currentUid
              ? current['currentTrip']
              : 'Nincs túra',
        };
      }).toList();

      if (!users.any((item) => item['id'] == currentUid)) {
        users.add(Map<String, dynamic>.from(current));
      }

      users.sort(
        (a, b) => safeInt(b['points']).compareTo(safeInt(a['points'])),
      );
      final userRank = higherCount == null ? 0 : higherCount + 1;

      if (!mounted) return;
      setState(() {
        _currentUserData = current;
        _allUsers = users;
        _userRank = userRank;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Hiba az adatok betöltésekor: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAchievementCatalogAndUnlocks() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      final achSnap = await _firestore.collection('achievements').get();
      final defs = achSnap.docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .toList();

      final unlockedSnap = await _firestore
          .collection('user_progress')
          .doc(uid)
          .collection('unlocked_achievements')
          .get();

      final unlockedIds = unlockedSnap.docs.map((d) => d.id).toSet();

      final now = DateTime.now();
      final last24Hours = now.subtract(const Duration(hours: 24));
      final newlyUnlocked = unlockedSnap.docs
          .where((doc) {
            final unlockedAt = doc.data()['unlockedAt'];
            if (unlockedAt == null) return false;
            final date = (unlockedAt as Timestamp).toDate();
            return date.isAfter(last24Hours);
          })
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();

      if (!mounted) return;
      setState(() {
        _achievementDefinitions = defs;
        _unlockedAchievementIds = unlockedIds;
        _newlyUnlockedAchievements = newlyUnlocked;
        _showAchievementBanner = newlyUnlocked.isNotEmpty;
      });

      if (newlyUnlocked.isNotEmpty) {
        _bannerDismissTimer?.cancel();
        _bannerDismissTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() => _showAchievementBanner = false);
          }
        });
      }
    } catch (e) {
      debugPrint('Jutalmak betöltése sikertelen: $e');
    }
  }

  List<Achievement> _buildAchievements() {
    if (_achievementDefinitions.isEmpty) {
      return const [];
    }

    return _achievementDefinitions.map((a) {
      final id = (a['id'] ?? '').toString();
      final title = (a['name'] ?? 'Achievement').toString();
      final description = (a['description'] ?? '').toString();
      final icon = (a['icon'] ?? '🏆').toString();
      final conditionType = (a['conditionType'] ?? '').toString();
      final conditionValue = safeInt(a['conditionValue']);
      final condition = conditionText(conditionType, conditionValue);
      final unlocked = _unlockedAchievementIds.contains(id);
      return Achievement(
        title: title,
        description: description,
        unlocked: unlocked,
        iconEmoji: icon,
        condition: condition,
      );
    }).toList();
  }

  /// A rangsorban csak a dobogó (top 3) és — ha a felhasználó azon kívül van —
  /// a saját sora jelenik meg, a valós helyezésével. Így a profil nem a teljes
  /// (akár 50 fős) listát görgeti.
  List<({Map<String, dynamic> user, int rank, bool afterGap})>
  _leaderboardRows() {
    final rows = <({Map<String, dynamic> user, int rank, bool afterGap})>[];
    final top = _allUsers.take(3).toList();
    for (var i = 0; i < top.length; i++) {
      rows.add((user: top[i], rank: i + 1, afterGap: false));
    }

    final myId = _currentUserData?['id'];
    final myIndex = _allUsers.indexWhere((u) => u['id'] == myId);
    if (myIndex >= 3) {
      rows.add((user: _allUsers[myIndex], rank: myIndex + 1, afterGap: true));
    }
    return rows;
  }

  Widget _buildLeaderboardCard() {
    final rows = _leaderboardRows();
    if (rows.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('A rangsor még nem érhető el.'),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            if (rows[i].afterGap)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Text('⋮', style: TextStyle(color: Colors.grey)),
              ),
            _buildLeaderboardRow(rows[i].user, rows[i].rank),
          ],
        ],
      ),
    );
  }

  Widget _buildLeaderboardRow(Map<String, dynamic> user, int rank) {
    final isCurrentUser = user['id'] == _currentUserData?['id'];
    return Container(
      color: isCurrentUser ? Colors.blue.shade50 : Colors.transparent,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Text(rankMedal(rank), style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user['name'].toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${safeCount(user['completedStations'])} állomás · ${safeCount(user['completedEvents'])} esemény',
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
              '${safeInt(user['points'])} pont',
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
  }

  @override
  Widget build(BuildContext context) {
    final currentPoints = safeInt(_currentUserData?['points']);
    final stationCount = safeCount(_currentUserData?['completedStations']);
    final eventCount = safeCount(_currentUserData?['completedEvents']);
    final rewardTarget = nextPointTarget(currentPoints, _achievementDefinitions);
    final progressToReward = rewardTarget > 0
        ? (currentPoints / rewardTarget).clamp(0.0, 1.0)
        : 1.0;
    final achievements = _buildAchievements();
    final unlockedCount = achievements.where((a) => a.unlocked).length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Fiókom'),
      ),
      body: Stack(
        children: [
          _isLoading
              ? const ProfileSkeleton()
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _refreshAll,
                          child: const Text('Újrapróbálás'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refreshAll,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildProfileHeader(),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _buildStatCard(
                            'Pontok',
                            currentPoints.toString(),
                            Icons.star,
                            Colors.amber,
                          ),
                          const SizedBox(width: 12),
                          _buildStatCard(
                            'Állomások',
                            stationCount.toString(),
                            Icons.place,
                            Colors.blue,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildStatCard(
                            'Események',
                            eventCount.toString(),
                            Icons.celebration,
                            Colors.deepOrange,
                          ),
                          const SizedBox(width: 12),
                          _buildStatCard(
                            'Rang',
                            _userRank == 0 ? '-' : rankMedal(_userRank),
                            Icons.leaderboard,
                            Colors.teal,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Jutalom előrehaladás',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: progressToReward,
                                minHeight: 10,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              const SizedBox(height: 8),
                              Text('$currentPoints / $rewardTarget pont'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: ListTile(
                          leading: Icon(Icons.map, color: Colors.blue.shade400),
                          title: const Text('Jelenlegi túra'),
                          subtitle: Text(
                            _currentUserData?['currentTrip']?.toString() ??
                                'Nincs túra',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Achievementek',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Feloldva: $unlockedCount / ${achievements.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (achievements.isEmpty)
                        Card(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              'A jutalmak listája most nem elérhető. Próbáld meg később újra.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: achievements
                              .map((a) => AchievementChip(achievement: a))
                              .toList(),
                        ),
                      const SizedBox(height: 10),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.track_changes_outlined),
                          title: const Text('Részletes achievement haladás'),
                          subtitle: const Text(
                            'Feltételek, állapotok, pontos előrehaladás',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AchievementProgressScreen(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Rangsor',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildLeaderboardCard(),
                      const SizedBox(height: 16),
                      const DataRightsSection(),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
          if (_showAchievementBanner && _newlyUnlockedAchievements.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.amber[600],
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.stars, color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Új achievement feloldva!',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            _newlyUnlockedAchievements
                                .map((a) => (a['name'] ?? a['id']).toString())
                                .join(', '),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      tooltip: 'Értesítés bezárása',
                      onPressed: () =>
                          setState(() => _showAchievementBanner = false),
                    ),
                  ],
                ),
              ),
            ),
        ],
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
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _currentUserData?['email']?.toString() ?? '',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            'Rang: ${rankMedal(_userRank)}',
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
