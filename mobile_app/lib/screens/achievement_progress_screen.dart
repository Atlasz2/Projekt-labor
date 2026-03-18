import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AchievementProgressScreen extends StatefulWidget {
  const AchievementProgressScreen({super.key});

  @override
  State<AchievementProgressScreen> createState() => _AchievementProgressScreenState();
}

class _AchievementProgressScreenState extends State<AchievementProgressScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _achievements = [];
  Set<String> _unlockedIds = <String>{};
  int _stations = 0;
  int _events = 0;
  int _points = 0;
  int _completedTrips = 0;
  int _rank = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  int _safeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  Future<void> _loadData() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Nincs bejelentkezett felhasznalo.';
      });
      return;
    }

    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final progressDoc = await _firestore.collection('user_progress').doc(uid).get();
      final progressData = progressDoc.data() ?? {};

      final stations = ((progressData['completedStations'] as List<dynamic>?) ?? []).length;
      final events = ((progressData['completedEvents'] as List<dynamic>?) ?? []).length;
      final points = _safeInt(progressData['totalPoints']);
      final completedTrips = ((progressData['completedTripIds'] as List<dynamic>?) ?? []).length;

      final achSnap = await _firestore.collection('achievements').get();
      final achievements = achSnap.docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .toList();

      final unlockedSnap = await _firestore
          .collection('user_progress')
          .doc(uid)
          .collection('unlocked_achievements')
          .get();
      final unlockedIds = unlockedSnap.docs.map((d) => d.id).toSet();

      final rankSnap = await _firestore
          .collection('user_progress')
          .orderBy('totalPoints', descending: true)
          .get();
      final rank = rankSnap.docs.indexWhere((d) => d.id == uid) + 1;

      if (!mounted) return;
      setState(() {
        _stations = stations;
        _events = events;
        _points = points;
        _completedTrips = completedTrips;
        _achievements = achievements;
        _unlockedIds = unlockedIds;
        _rank = rank > 0 ? rank : 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Hiba a betolteskor: $e';
      });
    }
  }

  _ProgressData _progressFor(Map<String, dynamic> ach) {
    final type = (ach['conditionType'] ?? '').toString();
    final target = (_safeInt(ach['conditionValue']) <= 0) ? 1 : _safeInt(ach['conditionValue']);
    final id = (ach['id'] ?? '').toString();

    if (_unlockedIds.contains(id)) {
      return const _ProgressData(
        conditionLabel: 'Feloldva',
        currentLabel: 'Kesz',
        remainingLabel: 'Teljesitve',
        progress: 1,
        sortScore: 1,
      );
    }

    if (type == 'station_count') {
      final current = _stations;
      final remaining = (target - current).clamp(0, target);
      return _ProgressData(
        conditionLabel: '$target allomas',
        currentLabel: '$current / $target',
        remainingLabel: remaining == 0 ? 'Teljesitve' : 'Hianyzik $remaining allomas',
        progress: (current / target).clamp(0.0, 1.0),
        sortScore: (current / target).clamp(0.0, 1.0),
      );
    }
    if (type == 'event_count') {
      final current = _events;
      final remaining = (target - current).clamp(0, target);
      return _ProgressData(
        conditionLabel: '$target esemeny',
        currentLabel: '$current / $target',
        remainingLabel: remaining == 0 ? 'Teljesitve' : 'Hianyzik $remaining esemeny',
        progress: (current / target).clamp(0.0, 1.0),
        sortScore: (current / target).clamp(0.0, 1.0),
      );
    }
    if (type == 'qr_count') {
      final current = _stations + _events;
      final remaining = (target - current).clamp(0, target);
      return _ProgressData(
        conditionLabel: '$target QR-kod',
        currentLabel: '$current / $target',
        remainingLabel: remaining == 0 ? 'Teljesitve' : 'Hianyzik $remaining QR-kod',
        progress: (current / target).clamp(0.0, 1.0),
        sortScore: (current / target).clamp(0.0, 1.0),
      );
    }
    if (type == 'points_threshold') {
      final current = _points;
      final remaining = (target - current).clamp(0, target);
      return _ProgressData(
        conditionLabel: '$target pont',
        currentLabel: '$current / $target',
        remainingLabel: remaining == 0 ? 'Teljesitve' : 'Hianyzik $remaining pont',
        progress: (current / target).clamp(0.0, 1.0),
        sortScore: (current / target).clamp(0.0, 1.0),
      );
    }
    if (type == 'trip_complete') {
      final current = _completedTrips;
      final remaining = (target - current).clamp(0, target);
      return _ProgressData(
        conditionLabel: '$target teljesitett tura',
        currentLabel: '$current / $target',
        remainingLabel: remaining == 0 ? 'Teljesitve' : 'Hianyzik $remaining teljesitett tura',
        progress: (current / target).clamp(0.0, 1.0),
        sortScore: (current / target).clamp(0.0, 1.0),
      );
    }
    if (type == 'top_n') {
      final rank = _rank == 0 ? 9999 : _rank;
      final done = rank <= target;
      final delta = done ? 0 : rank - target;
      return _ProgressData(
        conditionLabel: 'Top $target helyezes',
        currentLabel: _rank == 0 ? 'Nincs rang' : '$rank. hely',
        remainingLabel: done ? 'Teljesitve' : 'Hianyzik $delta helyezes',
        progress: done ? 1 : (target / rank).clamp(0.0, 1.0),
        sortScore: done ? 1 : (target / rank).clamp(0.0, 1.0),
      );
    }

    return const _ProgressData(
      conditionLabel: 'Manualis',
      currentLabel: 'Admin adja at',
      remainingLabel: 'Varakozas admin jovahagyasra',
      progress: 0,
      sortScore: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _achievements.length;
    final unlocked = _unlockedIds.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Achievement haladas')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _loadData, child: const Text('Ujraprobalas')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              const Icon(Icons.insights_outlined),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Itt latod minden jutalom pontos feltetelet es az aktualis haladasod.',
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _TopStatCard(
                              icon: Icons.emoji_events_outlined,
                              label: 'Feloldott',
                              value: '$unlocked / $total',
                              color: const Color(0xFF166534),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _TopStatCard(
                              icon: Icons.qr_code_scanner,
                              label: 'QR osszesen',
                              value: '${_stations + _events}',
                              color: const Color(0xFF1D4ED8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ..._sortedAchievementViews().map((view) {
                        final a = view.achievement;
                        final title = (a['name'] ?? 'Achievement').toString();
                        final desc = (a['description'] ?? '').toString();
                        final icon = (a['icon'] ?? '🏆').toString();
                        final unlocked = _unlockedIds.contains((a['id'] ?? '').toString());
                        final progress = view.progress;
                        final fg = unlocked ? const Color(0xFF166534) : const Color(0xFF374151);
                        final bg = unlocked ? const Color(0xFFE7F5EA) : Colors.white;

                        return Card(
                          color: bg,
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(icon, style: const TextStyle(fontSize: 20)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
                                    ),
                                    Icon(
                                      unlocked ? Icons.check_circle : Icons.lock_outline,
                                      color: fg,
                                    )
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(desc, style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.86))),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text('Feltetel: ${progress.conditionLabel}', style: const TextStyle(fontSize: 11)),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEEF2FF),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text('Allapot: ${progress.currentLabel}', style: const TextStyle(fontSize: 11)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  progress.remainingLabel,
                                  style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.85)),
                                ),
                                const SizedBox(height: 10),
                                LinearProgressIndicator(
                                  value: progress.progress,
                                  minHeight: 8,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }

  List<_AchievementView> _sortedAchievementViews() {
    final list = _achievements
        .map((a) => _AchievementView(achievement: a, progress: _progressFor(a)))
        .toList();
    list.sort((a, b) {
      final aUnlocked = _unlockedIds.contains((a.achievement['id'] ?? '').toString());
      final bUnlocked = _unlockedIds.contains((b.achievement['id'] ?? '').toString());
      if (aUnlocked != bUnlocked) return aUnlocked ? 1 : -1;
      return b.progress.sortScore.compareTo(a.progress.sortScore);
    });
    return list;
  }
}

class _AchievementView {
  final Map<String, dynamic> achievement;
  final _ProgressData progress;
  _AchievementView({required this.achievement, required this.progress});
}

class _ProgressData {
  final String conditionLabel;
  final String currentLabel;
  final String remainingLabel;
  final double progress;
  final double sortScore;

  const _ProgressData({
    required this.conditionLabel,
    required this.currentLabel,
    required this.remainingLabel,
    required this.progress,
    required this.sortScore,
  });
}

class _TopStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _TopStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}