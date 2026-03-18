import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class UnlockedContentScreen extends StatelessWidget {
  const UnlockedContentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Hiba: felhasználó nem azonosított')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feloldott Tartalmak'),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/var.jpg', fit: BoxFit.cover)),
          Positioned.fill(
            child: Container(color: const Color(0xFFF2EBDD).withValues(alpha: 0.97)),
          ),
          SafeArea(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('user_progress')
                  .doc(uid)
                  .snapshots(),
              builder: (context, userProgressSnapshot) {
                if (userProgressSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (!userProgressSnapshot.hasData ||
                    !userProgressSnapshot.data!.exists) {
                  return const Center(
                    child: Text('Még nincs feloldott tartalom'),
                  );
                }

                final userProgressDoc = userProgressSnapshot.data!;
                final unlockedAchievementIds =
                    List<String>.from((userProgressDoc['unlocked_achievements'] as List?)?.cast<String>() ?? []);

                if (unlockedAchievementIds.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_open_rounded,
                              size: 60, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(
                            'Még nincs feloldott tartalom',
                            style: Theme.of(context).textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Folytass a feltételek teljesítésével!',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('achievements')
                      .snapshots(),
                  builder: (context, achievementsSnapshot) {
                    if (achievementsSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    if (!achievementsSnapshot.hasData) {
                      return const Center(child: Text('Nincs adat'));
                    }

                    final unlockedAchievements = achievementsSnapshot.data!.docs
                        .where(
                            (doc) =>
                                unlockedAchievementIds.contains(doc.id))
                        .toList();

                    if (unlockedAchievements.isEmpty) {
                      return const Center(child: Text('Nincs feloldott tartalom'));
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: unlockedAchievements.length,
                      itemBuilder: (context, index) {
                        final ach = unlockedAchievements[index];
                        final data = ach.data() as Map<String, dynamic>;
                        final title = data['title'] ?? 'Nincs cím';
                        final description = data['description'] ?? '';
                        final color = Color(
                            int.tryParse(data['color'] ?? '0xFF4CAF50',
                                radix: 16) ??
                                0xFF4CAF50);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: color.withValues(alpha: 0.5),
                              width: 2,
                            ),
                          ),
                          elevation: 6,
                          shadowColor: color.withValues(alpha: 0.3),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white,
                                  color.withValues(alpha: 0.08),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.emoji_events,
                                      color: color,
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1F2937),
                                          ),
                                        ),
                                        if (description.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            description,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF6B7280),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.check_circle,
                                      color: color,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
