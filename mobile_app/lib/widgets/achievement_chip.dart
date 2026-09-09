import 'package:flutter/material.dart';

/// Egy achievement megjelenítési modellje (a profil képernyő állítja össze a
/// Firestore-definíciókból és a felhasználó feloldott jutalmaiból).
class Achievement {
  final String title;
  final String description;
  final bool unlocked;
  final String iconEmoji;
  final String condition;

  /// Mikor oldotta fel a felhasználó (null, ha még nincs feloldva, vagy az
  /// időpont ismeretlen).
  final DateTime? unlockedAt;

  /// Ha nem üres, ehhez az achievementhez fizikai/kedvezmény jutalom jár,
  /// amit a felhasználó fel tud mutatni (lásd `showAchievementDetailSheet`).
  final String rewardInfo;

  /// Mikor jelölte az admin/developer beváltottnak a jutalmat (null, ha még
  /// nem váltották be, vagy nem jár hozzá jutalom). Ez akadályozza meg, hogy
  /// ugyanazt a jutalmat többször is fel lehessen mutatni.
  final DateTime? redeemedAt;

  const Achievement({
    required this.title,
    required this.description,
    required this.unlocked,
    required this.iconEmoji,
    required this.condition,
    this.unlockedAt,
    this.rewardInfo = '',
    this.redeemedAt,
  });

  bool get hasReward => rewardInfo.trim().isNotEmpty;
  bool get isRedeemed => redeemedAt != null;
}

/// Egy achievement kártya-chipje a profil rácsában (feloldott/zárolt
/// állapot). Feloldott achievementre rákoppintva a `onTap` a részleteket
/// (mikor, mivel oldotta fel, jár-e érte jutalom) mutató lapot nyithatja meg.
class AchievementChip extends StatelessWidget {
  final Achievement achievement;
  final VoidCallback? onTap;

  const AchievementChip({super.key, required this.achievement, this.onTap});

  @override
  Widget build(BuildContext context) {
    // Feloldva: meleg arany-borostyán árnyalat (trófea-hangulat, nem a
    // korábbi lila). Zárolva: semleges szürke.
    final bg = achievement.unlocked
        ? const Color(0xFFFFF3D6)
        : const Color(0xFFF3F4F6);
    final borderColor = achievement.unlocked
        ? const Color(0xFFE8B93A)
        : const Color(0xFFD1D5DB);
    // WCAG AA (4.5:1) kontraszt a chip halvány hátterén — a leírás-szöveg
    // 0.84 alfával jelenik meg, ezért ott mérve is 4.5 fölött kell lennie
    // (lásd test/accessibility_test.dart).
    final fg = achievement.unlocked
        ? const Color(0xFF6B4400)
        : const Color(0xFF6B7280);

    final card = Container(
      width: 178,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: achievement.unlocked ? 1.4 : 1),
        boxShadow: achievement.unlocked
            ? [
                BoxShadow(
                  color: const Color(0xFFE8B93A).withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
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
              if (achievement.unlocked && achievement.hasReward)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    achievement.isRedeemed
                        ? Icons.verified_rounded
                        : Icons.card_giftcard_rounded,
                    size: 16,
                    color: achievement.isRedeemed
                        ? Colors.green.shade700
                        : fg,
                    semanticLabel: achievement.isRedeemed
                        ? 'Jutalom beváltva'
                        : 'Jutalom jár érte',
                  ),
                ),
              Icon(
                achievement.unlocked
                    ? Icons.check_circle_rounded
                    : Icons.lock_outline,
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
          if (achievement.unlocked && onTap != null) ...[
            const SizedBox(height: 6),
            Text(
              achievement.hasReward
                  ? 'Koppints a részletekért →'
                  : 'Koppints: mikor oldottad fel',
              style: TextStyle(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: fg.withValues(alpha: 0.72),
              ),
            ),
          ],
        ],
      ),
    );

    // Az interaktív (Material/InkWell) csomagolást csak akkor tesszük rá, ha
    // valóban van mire koppintani – zárolt achievementnél (vagy ha a hívó
    // nem adott meg onTap-et) a sima kártyát adjuk vissza.
    if (!achievement.unlocked || onTap == null) return card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: card,
      ),
    );
  }
}
