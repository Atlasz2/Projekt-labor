import 'package:flutter/material.dart';

/// A profil képernyő betöltés alatti csontváza (skeleton), hogy a felület
/// ne ugráljon a valós adat megérkezésekor.
class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final grey = Colors.grey.shade200;
    final bRadius = BorderRadius.circular(8);

    Widget block(double height) => Container(
      height: height,
      decoration: BoxDecoration(color: grey, borderRadius: BorderRadius.circular(12)),
    );

    Widget statRow() => Row(
      children: [
        Expanded(child: block(80)),
        const SizedBox(width: 12),
        Expanded(child: block(80)),
      ],
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: grey, shape: BoxShape.circle),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 18,
                        width: 140,
                        decoration: BoxDecoration(color: grey, borderRadius: bRadius),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 13,
                        width: 100,
                        decoration: BoxDecoration(color: grey, borderRadius: bRadius),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        statRow(),
        const SizedBox(height: 12),
        statRow(),
        const SizedBox(height: 12),
        block(90),
        const SizedBox(height: 12),
        block(160),
      ],
    );
  }
}
