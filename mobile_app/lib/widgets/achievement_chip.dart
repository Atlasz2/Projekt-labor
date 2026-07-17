import 'package:flutter/material.dart';

/// Egy achievement megjelenítési modellje (a profil képernyő állítja össze a
/// Firestore-definíciókból és a felhasználó feloldott jutalmaiból).
class Achievement {
  final String title;
  final String description;
  final bool unlocked;
  final String iconEmoji;
  final String condition;

  const Achievement({
    required this.title,
    required this.description,
    required this.unlocked,
    required this.iconEmoji,
    required this.condition,
  });
}

/// Egy achievement kártya-chipje a profil rácsában (feloldott/zárolt állapot).
class AchievementChip extends StatelessWidget {
  final Achievement achievement;

  const AchievementChip({super.key, required this.achievement});

  @override
  Widget build(BuildContext context) {
    final bg = achievement.unlocked
        ? const Color(0xFFE7F5EA)
        : const Color(0xFFF3F4F6);
    // WCAG AA (4.5:1) kontraszt a chip halvány hátterén; a korábbi #166534
    // a "Feltétel" badge-en épphogy alálőtte a küszöböt (4.47).
    final fg = achievement.unlocked
        ? const Color(0xFF14532D)
        : const Color(0xFF6B7280);

    return Container(
      width: 178,
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
              Text(
                achievement.iconEmoji,
                style: TextStyle(fontSize: 18, color: fg),
              ),
              const Spacer(),
              Icon(
                achievement.unlocked ? Icons.check_circle : Icons.lock_outline,
                size: 18,
                color: fg,
                semanticLabel: achievement.unlocked ? 'Feloldva' : 'Zárolva',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            achievement.title,
            style: TextStyle(fontWeight: FontWeight.w700, color: fg),
          ),
          const SizedBox(height: 4),
          Text(
            achievement.description,
            style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.84)),
          ),
          if (achievement.condition.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.68),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Feltétel: ${achievement.condition}',
                style: TextStyle(fontSize: 11, color: fg),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
