import 'package:flutter/material.dart';

import '../utils/image_normalizer.dart';
import 'offline_image.dart';
import 'station_image_viewer.dart';

/// Az állomás részleteit mutató alsó lap (fotógaléria, leírás, és teljesített
/// állomásnál a feloldott fun fact).
void showStationDetailSheet(
  BuildContext context, {
  required Map<String, dynamic> station,
  required bool isCompleted,
}) {
  final photos = photoListFromDoc(station);
  final stationName = station['name']?.toString() ?? 'Állomás';

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      maxChildSize: 0.9,
      minChildSize: 0.42,
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
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stationName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isCompleted
                            ? 'Teljesítve • ${station['points'] ?? 10} pont'
                            : '${station['points'] ?? 10} pont szerezhető',
                        style: TextStyle(
                          color: isCompleted
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFF8B5E34),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (photos.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('${photos.length} fotó'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (photos.isNotEmpty)
              SizedBox(
                height: 210,
                child: PageView.builder(
                  controller: PageController(viewportFraction: 0.9),
                  itemCount: photos.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () =>
                          showStationImageViewer(context, photos, index),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            OfflineImage.network(
                              photos[index],
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: const Color(0xFFEADFCC),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.broken_image_outlined,
                                  size: 34,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.56),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${index + 1}/${photos.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
              Container(
                height: 140,
                decoration: BoxDecoration(
                  color: const Color(0xFFEADFCC),
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: const Text('Ehhez az állomáshoz még nincs fotó.'),
              ),
            if ((station['description']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text(
                'Leírás',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                station['description'].toString(),
                style: const TextStyle(height: 1.45),
              ),
            ],
            if (isCompleted &&
                (station['funFact']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBF3E3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE8D5A8)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFA16207).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Color(0xFFA16207),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ÉRDEKESSÉG',
                            style: TextStyle(
                              color: Color(0xFFA16207),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            station['funFact'].toString(),
                            style: const TextStyle(
                              color: Color(0xFF3A3226),
                              fontWeight: FontWeight.w500,
                              height: 1.45,
                            ),
                          ),
                        ],
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
