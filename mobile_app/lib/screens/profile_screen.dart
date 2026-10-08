import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/account_service.dart';
import '../services/leaderboard_service.dart';
import '../theme/app_colors.dart';
import '../utils/profile_stats.dart';
import '../widgets/achievement_chip.dart';
import '../widgets/achievement_detail_sheet.dart';
import '../widgets/data_rights_section.dart';
import '../widgets/profile_skeleton.dart';
import 'achievement_progress_screen.dart';
import '../utils/project_filter.dart';

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
  List<Map<String, dynamic>> _achievementDefinitions = [];
  Set<String> _unlockedAchievementIds = <String>{};
  Map<String, DateTime> _unlockedAt = <String, DateTime>{};
  Map<String, DateTime> _redeemedAt = <String, DateTime>{};

  bool _isLoading = true;
  String? _error;
  int _userRank = 0;

  @override
  void initState() {
    super.initState();
    _refreshAll();
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

      // A dobogó (top 3) és a saját helyezés együtt fut; ha a ranglista lassú
      // vagy nem elérhető, a profil akkor is megjelenik (rangsor nélkül).
      List<QueryDocumentSnapshot<Map<String, dynamic>>> podiumDocs = const [];
      var userRank = 0;
      try {
        final leaderboard = await Future.wait<Object>([
          LeaderboardService.top(3),
          LeaderboardService.rankOf(currentUid),
        ]).timeout(const Duration(seconds: 10));
        podiumDocs =
            leaderboard[0] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
        userRank = leaderboard[1] as int;
      } catch (_) {
        // A ranglista nem elérhető — a profil enélkül is használható.
      }

      final users = podiumDocs.map((doc) {
        final data = doc.data();
        return <String, dynamic>{
          'id': doc.id,
          'name': data['displayName']?.toString() ?? 'Felhasználó',
          'completedStations': safeInt(data['completedStationsCount']),
          'completedEvents': safeInt(data['completedEventsCount']),
          'points': safeInt(data['points']),
        };
      }).toList();

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
        _error =
            'A profil betöltése nem sikerült. Ellenőrizd a kapcsolatot, és próbáld újra.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAchievementCatalogAndUnlocks() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      final achSnap = await _firestore.collection('achievements').get();
      // Csak ennek a településnek a jutalmai.
      final defs = whereActiveProject(
        achSnap.docs,
      ).map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList();

      final unlockedSnap = await _firestore
          .collection('user_progress')
          .doc(uid)
          .collection('unlocked_achievements')
          .get();

      final unlockedIds = unlockedSnap.docs.map((d) => d.id).toSet();
      final unlockedAt = <String, DateTime>{};
      final redeemedAt = <String, DateTime>{};
      for (final d in unlockedSnap.docs) {
        final data = d.data();
        final ts = data['unlockedAt'];
        if (ts is Timestamp) unlockedAt[d.id] = ts.toDate();
        // Az admin/developer jelöli be a beváltott (fizikai/kedvezmény)
        // jutalmakat, hogy ugyanaz ne legyen többször felmutatható.
        final redeemedTs = data['redeemedAt'];
        if (redeemedTs is Timestamp) redeemedAt[d.id] = redeemedTs.toDate();
      }

      if (!mounted) return;
      setState(() {
        _achievementDefinitions = defs;
        _unlockedAchievementIds = unlockedIds;
        _unlockedAt = unlockedAt;
        _redeemedAt = redeemedAt;
      });
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
      final rewardInfo = (a['rewardInfo'] ?? '').toString();
      return Achievement(
        title: title,
        description: description,
        unlocked: unlocked,
        iconEmoji: icon,
        condition: condition,
        unlockedAt: _unlockedAt[id],
        rewardInfo: rewardInfo,
        redeemedAt: _redeemedAt[id],
      );
    }).toList();
  }

  /// A rangsorban csak a dobogó (top 3) és — ha a felhasználó azon kívül van —
  /// a saját sora jelenik meg, a valós helyezésével. Így a profil nem a teljes
  /// (akár 50 fős) listát görgeti.
  List<({Map<String, dynamic> user, int rank, bool afterGap})>
  _leaderboardRows() {
    final rows = <({Map<String, dynamic> user, int rank, bool afterGap})>[];
    for (var i = 0; i < _allUsers.length; i++) {
      rows.add((user: _allUsers[i], rank: i + 1, afterGap: false));
    }

    // Ha a felhasználó a dobogón kívül van, a saját sora a valós helyezéssel.
    final current = _currentUserData;
    if (current != null && _userRank > _allUsers.length) {
      rows.add((user: current, rank: _userRank, afterGap: true));
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
    final rewardTarget = nextPointTarget(
      currentPoints,
      _achievementDefinitions,
    );
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
                              .map(
                                (a) => AchievementChip(
                                  achievement: a,
                                  onTap: () => showAchievementDetailSheet(
                                    context,
                                    achievement: a,
                                    holderName:
                                        _currentUserData?['name']?.toString() ??
                                        '',
                                  ),
                                ),
                              )
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
        ],
      ),
    );
  }

  /// A megjelenített név módosítása (a ranglistán és a profilon is).
  Future<void> _renameDialog() async {
    final controller = TextEditingController(
      text: _currentUserData?['name']?.toString() ?? '',
    );
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Név módosítása'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Új név',
            helperText: 'Ez a név jelenik meg a ranglistán.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Mégse'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Mentés'),
          ),
        ],
      ),
    );
    controller.dispose();
    final current = _currentUserData?['name']?.toString() ?? '';
    if (newName == null || newName.isEmpty || newName == current) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await AccountService.rename(newName);
      if (!mounted) return;
      setState(() {
        _currentUserData = {...?_currentUserData, 'name': saved};
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('A nevedet módosítottuk.')),
      );
      unawaited(_loadUserData());
    } on RenameRejectedException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      debugPrint('Névmódosítás sikertelen: $e');
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'A név módosítása nem sikerült. Ellenőrizd a kapcsolatot, és próbáld újra.',
          ),
        ),
      );
    }
  }

  /// E-mail-cím utólagos megadása (ha a regisztrációkor kimaradt): ezzel a
  /// fiók másik eszközön vagy újratelepítés után is visszaállítható.
  Future<void> _addEmailDialog() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('E-mail-cím megadása'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Az e-mail-címmel és a neveddel egy másik telefonon vagy '
              'újratelepítés után is visszakapod a pontjaidat és a '
              'jutalmaidat. Mások nem látják.',
              style: TextStyle(height: 1.35),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-mail-cím',
                hintText: 'pl. kiss.janos@example.com',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Mégse'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Mentés'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (email == null || email.isEmpty || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Érvénytelen e-mail-cím.')),
      );
      return;
    }
    try {
      await AccountService.addEmail(
        email,
        _currentUserData?['name']?.toString() ?? '',
      );
      if (!mounted) return;
      setState(() {
        _currentUserData = {...?_currentUserData, 'email': email};
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'E-mail-cím mentve. Másik eszközön az e-mail-címeddel és a '
            'neveddel léphetsz be.',
          ),
        ),
      );
    } on AddEmailRejectedException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      debugPrint('E-mail hozzáadása sikertelen: $e');
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Az e-mail-cím mentése nem sikerült. Ellenőrizd a kapcsolatot, '
            'és próbáld újra.',
          ),
        ),
      );
    }
  }

  Widget _buildProfileHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6E8460), Color(0xFF46583B)],
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
            child: Icon(Icons.person, size: 48, color: Color(0xFF46583B)),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _currentUserData?['name']?.toString() ?? 'Felhasználó',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                onPressed: _renameDialog,
                tooltip: 'Név módosítása',
                icon: const Icon(Icons.edit_outlined, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // E-mailhez kötött fióknál a cím, egyébként lehetőség a megadására.
          if (FirebaseAuth.instance.currentUser?.email != null)
            Text(
              FirebaseAuth.instance.currentUser!.email!,
              style: const TextStyle(color: Colors.white70),
            )
          else
            TextButton.icon(
              onPressed: _addEmailDialog,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.alternate_email, size: 18),
              label: const Text('E-mail-cím megadása'),
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
