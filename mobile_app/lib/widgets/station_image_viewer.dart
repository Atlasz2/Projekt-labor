import 'package:flutter/material.dart';

import 'offline_image.dart';

/// Teljes képernyős, lapozható-nagyítható képnézegető az állomásfotókhoz.
void showStationImageViewer(
  BuildContext context,
  List<String> photos,
  int initialIndex,
) {
  if (photos.isEmpty) return;
  var currentIndex = initialIndex;
  final pageController = PageController(initialPage: initialIndex);

  final dialogFuture = showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            PageView.builder(
              controller: pageController,
              itemCount: photos.length,
              onPageChanged: (index) =>
                  setDialogState(() => currentIndex = index),
              itemBuilder: (_, index) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: OfflineImage.network(
                    photos[index],
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Bezárás',
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${currentIndex + 1}/${photos.length}',
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
  );
  dialogFuture.whenComplete(pageController.dispose);
}
