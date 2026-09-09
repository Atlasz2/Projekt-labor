import 'package:flutter/material.dart';

import 'achievement_chip.dart';

const _hunMonths = [
  'január',
  'február',
  'március',
  'április',
  'május',
  'június',
  'július',
  'augusztus',
  'szeptember',
  'október',
  'november',
  'december',
];

/// Magyar dátum-idő szöveg (nincs `intl` függőség hozzáadva ezért az egy
/// helyi jutalom-igazoláshoz).
String _formatHun(DateTime dt) {
  final month = _hunMonths[dt.month - 1];
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '${dt.year}. $month ${dt.day}. $hh:$mm';
}

/// Egy feloldott achievement részleteit mutató alsó lap: mikor és milyen
/// feltétellel oldotta fel a felhasználó, illetve — ha jár érte jutalom — egy
/// jól látható "mutasd fel" kártya, amit a felhasználó a helyszínen az
/// adminnak/recepciósnak megmutathat igazolásként.
void showAchievementDetailSheet(
  BuildContext context, {
  required Achievement achievement,
  required String holderName,
}) {
  final dateText = achievement.unlockedAt != null
      ? _formatHun(achievement.unlockedAt!)
      : null;
  final holderLine = [
    holderName,
    dateText,
  ].where((s) => s != null && s.isNotEmpty).join(' · ');

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: achievement.hasReward ? 0.62 : 0.46,
      maxChildSize: 0.9,
      minChildSize: 0.34,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8F4EC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          children: [
            Center(
              child: Container(
                width: 56,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1C2AE),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3D6),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFE8B93A),
                      width: 1.4,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    achievement.iconEmoji,
                    style: const TextStyle(fontSize: 26),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        achievement.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 15,
                            color: Color(0xFF2E7D32),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Feloldva',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (achievement.description.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                achievement.description,
                style: const TextStyle(height: 1.45),
              ),
            ],
            const SizedBox(height: 14),
            _InfoRow(
              icon: Icons.flag_rounded,
              label: 'Feltétel',
              value: achievement.condition.isNotEmpty
                  ? achievement.condition
                  : '—',
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.event_available_rounded,
              label: 'Mikor oldottad fel',
              value: dateText ?? 'Nincs pontos időpont rögzítve',
            ),
            if (achievement.hasReward) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFF3D6), Color(0xFFFFE1A8)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFE8B93A),
                    width: 1.4,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.card_giftcard_rounded,
                          color: Color(0xFF8A5A00),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            achievement.isRedeemed
                                ? 'Jutalom beváltva'
                                : 'Jutalom jár érte!',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: Color(0xFF8A5A00),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      achievement.rewardInfo,
                      style: const TextStyle(
                        height: 1.5,
                        color: Color(0xFF5C3E00),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: achievement.isRedeemed
                            ? Colors.green.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (achievement.isRedeemed) ...[
                            Icon(
                              Icons.check_circle_rounded,
                              size: 16,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              achievement.isRedeemed
                                  ? 'Beváltva${achievement.redeemedAt != null ? ' · ${_formatHun(achievement.redeemedAt!)}' : ''}'
                                  : 'Mutasd fel ezt a képernyőt a helyszínen',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: achievement.isRedeemed
                                    ? Colors.green.shade800
                                    : Colors.brown.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Igazoló sáv: felhasználó neve + feloldás időpontja, hogy a
              // helyszínen (recepció, infopont) az admin könnyen ellenőrizni
              // tudja, kihez és mikorhoz tartozik a bemutatott jutalom.
              if (holderLine.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5DCC8)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        size: 16,
                        color: Color(0xFF6B7280),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          holderLine,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF8B5E34)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8B5E34),
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}
