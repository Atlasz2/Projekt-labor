import 'package:flutter/material.dart';

import 'offline_image.dart';

/// A feloldott tartalmak listájának egy kártyája (állomás/esemény, a
/// beolvasáskor feltárt szöveggel és képekkel).
class UnlockedCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final int index;
  final VoidCallback onTapImage;

  const UnlockedCard({
    super.key,
    required this.item,
    required this.index,
    required this.onTapImage,
  });

  @override
  Widget build(BuildContext context) {
    const gradients = [
      [Color(0xFF7C3AED), Color(0xFF4F46E5)],
      [Color(0xFF0369A1), Color(0xFF0891B2)],
      [Color(0xFF065F46), Color(0xFF059669)],
      [Color(0xFF92400E), Color(0xFFD97706)],
      [Color(0xFF9D174D), Color(0xFFDB2777)],
    ];
    final grad = gradients[(index - 1) % gradients.length];
    final images = (item['images'] as List<String>? ?? const []);
    final imageUrl = images.isNotEmpty ? images.first : '';
    final type = item['type']?.toString() ?? 'unlock';
    final icon = type == 'funFact'
        ? Icons.lightbulb_rounded
        : Icons.celebration_rounded;
    final badge = type == 'funFact' ? 'Fun fact' : 'Feloldott tartalom';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: grad),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: grad[0].withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['stationName']?.toString() ?? 'Ismeretlen állomás',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        badge,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.lock_open_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
              ],
            ),
            if (imageUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: onTapImage,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    children: [
                      OfflineImage.network(
                        imageUrl,
                        height: 210,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          height: 210,
                          color: Colors.white12,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.32),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.48),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.zoom_in,
                                color: Colors.white,
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Megnyitás',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: Colors.white70, size: 34),
                      const SizedBox(height: 8),
                      const Text(
                        'Ehhez a tartalomhoz nincs külön kép',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              item['title']?.toString() ?? '',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item['content']?.toString() ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (images.length > 1) ...[
              const SizedBox(height: 12),
              Text(
                '${images.length} kép érhető el ehhez a feloldott tartalomhoz.',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
