import 'package:flutter/material.dart';

import 'offline_image.dart';

/// A feloldott tartalmak listájának egy kártyája. Meleg, „pergamen"-hangulatú
/// megjelenés az app témájához illesztve (krém háttér, olvasható sötét szöveg),
/// típus szerint megkülönböztető akcentszínnel:
///   • érdekesség (funFact) → borostyán/arany
///   • feloldott tartalom (unlock) → olívazöld (a téma seed-színe)
class UnlockedCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTapImage;

  const UnlockedCard({
    super.key,
    required this.item,
    required this.onTapImage,
  });

  static const _cardBg = Color(0xFFFBF7EF);
  static const _cardBorder = Color(0xFFE3D5BC);
  static const _titleColor = Color(0xFF4A3F2E);
  static const _bodyColor = Color(0xFF3A3226);
  static const _amber = Color(0xFFA16207); // érdekesség akcent
  static const _olive = Color(0xFF5B6F4C); // feloldott tartalom akcent

  @override
  Widget build(BuildContext context) {
    final images = (item['images'] as List<String>? ?? const []);
    final imageUrl = images.isNotEmpty ? images.first : '';
    final isFunFact = (item['type']?.toString() ?? 'unlock') == 'funFact';

    final accent = isFunFact ? _amber : _olive;
    final icon = isFunFact
        ? Icons.auto_awesome_rounded
        : Icons.auto_stories_rounded;
    final badge = isFunFact ? 'Érdekesség' : 'Feloldott tartalom';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3A3226).withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fejléc: akcentszínű ikon + állomásnév + típuscímke
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        badge.toUpperCase(),
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item['stationName']?.toString() ?? 'Ismeretlen állomás',
                        style: const TextStyle(
                          color: _titleColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Kép (ha van) — a fejléc és a szöveg között
          if (imageUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: GestureDetector(
                onTap: onTapImage,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      OfflineImage.network(
                        imageUrl,
                        height: 190,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          height: 190,
                          color: const Color(0xFFEADFCC),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: Color(0xFF9C8A6E),
                          ),
                        ),
                      ),
                      if (images.length > 1)
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.photo_library_outlined,
                                  color: Colors.white,
                                  size: 13,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${images.length} kép',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
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
            ),

          // Szöveg
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Text(
              item['content']?.toString() ?? '',
              style: const TextStyle(
                color: _bodyColor,
                fontSize: 15,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
