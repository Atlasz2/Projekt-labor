import 'package:flutter/material.dart';

import 'offline_image.dart';

/// A feloldott tartalmak listájának egy összecsukható kártyája. Alapból zárt,
/// hogy sok teljesített állomásnál is átlátható maradjon a lista — a fejlécen
/// az állomásnév látszik, kinyitva a feloldott kép és szöveg.
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
  static const _olive = Color(0xFF5B6F4C);

  @override
  Widget build(BuildContext context) {
    final images = (item['images'] as List<String>? ?? const []);
    final imageUrl = images.isNotEmpty ? images.first : '';
    final content = item['content']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3A3226).withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Az ExpansionTile alap szürke elválasztóit elrejti.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          iconColor: _olive,
          collapsedIconColor: _olive,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _olive.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_stories_rounded, color: _olive, size: 22),
          ),
          title: Text(
            item['stationName']?.toString() ?? 'Ismeretlen állomás',
            style: const TextStyle(
              color: _titleColor,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          subtitle: const Text(
            'FELOLDOTT TARTALOM',
            style: TextStyle(
              color: _olive,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          children: [
            if (imageUrl.isNotEmpty) ...[
              GestureDetector(
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
              const SizedBox(height: 12),
            ],
            Text(
              content,
              style: const TextStyle(
                color: _bodyColor,
                fontSize: 15,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
