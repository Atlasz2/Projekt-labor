import 'package:flutter/material.dart';

import '../utils/image_normalizer.dart';
import 'offline_image.dart';

/// A QR-beolvasás eredményét mutató nézet: állomás/esemény fejléc, a szerzett
/// pontok, az esetleg feloldott jutalmak és tartalom, valamint az "Újabb
/// beolvasás" gomb. A `station` a QrProcessResult-ból összeállított map
/// (a hívó camera_screen tölti fel a megjelenítési kulcsokkal).
class ScanResultView extends StatelessWidget {
  const ScanResultView({
    super.key,
    required this.station,
    required this.onScanAgain,
  });

  final Map<String, dynamic> station;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context) {
    final alreadyDone = station['alreadyDone'] == true;
    final points = (station['points'] as num?)?.toInt() ?? 10;
    final name = station['name']?.toString() ?? 'Állomás';
    final unlockContent = station['unlockContent']?.toString() ?? '';
    final extraInfo = station['extraInfo']?.toString() ?? '';
    final imageUrl = primaryPhotoFromDoc(station);
    final newAch =
        (station['newAchievements'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final offlineQueued = station['offlineQueued'] == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 12),
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: OfflineImage.network(
                imageUrl,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, trace) => const SizedBox.shrink(),
              ),
            ),
          const SizedBox(height: 20),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: alreadyDone
                  ? Colors.grey.shade200
                  : const Color(0xFF4CAF50).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              alreadyDone ? Icons.repeat_rounded : Icons.check_circle_rounded,
              size: 48,
              color: alreadyDone ? Colors.grey : const Color(0xFF4CAF50),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: alreadyDone
                  ? Colors.grey.shade100
                  : Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.star_rounded,
                  color: alreadyDone ? Colors.grey : Colors.amber,
                ),
                const SizedBox(width: 6),
                Text(
                  alreadyDone
                      ? 'Már feloldott (+0 pt)'
                      : (offlineQueued
                            ? ('Offline sorban (+$points pt)')
                            : ('+$points pont')),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: alreadyDone ? Colors.grey : Colors.amber.shade700,
                  ),
                ),
              ],
            ),
          ),
          if (newAch.isNotEmpty) ...[
            const SizedBox(height: 20),
            _UnlockedAchievements(achievements: newAch),
          ],
          if (unlockContent.isNotEmpty) ...[
            const SizedBox(height: 20),
            _InfoPanel(
              backgroundColor: const Color(0xFFFFF8E1),
              borderColor: Colors.amber.shade200,
              iconColor: Colors.amber,
              icon: Icons.lock_open,
              title: 'Feloldott tartalom',
              body: unlockContent,
            ),
          ],
          if (extraInfo.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF667EEA), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      extraInfo,
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onScanAgain,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Újabb beolvasás'),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _UnlockedAchievements extends StatelessWidget {
  const _UnlockedAchievements({required this.achievements});

  final List<Map<String, dynamic>> achievements;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF9C4), Color(0xFFFFF3E0)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.emoji_events, color: Colors.amber, size: 20),
              SizedBox(width: 8),
              Text(
                'Új jutalom feloldva! 🎉',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...achievements.map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text(
                    a['icon']?.toString() ?? '🏆',
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a['name']?.toString() ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if ((a['description']?.toString() ?? '').isNotEmpty)
                          Text(
                            a['description'].toString(),
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.backgroundColor,
    required this.borderColor,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.body,
  });

  final Color backgroundColor;
  final Color borderColor;
  final Color iconColor;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.bold, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(body, style: const TextStyle(fontSize: 14, height: 1.6)),
        ],
      ),
    );
  }
}
