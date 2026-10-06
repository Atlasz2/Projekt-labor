import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/offline_image_service.dart';

class OfflineImage extends StatefulWidget {
  const OfflineImage.network(
    this.imageUrl, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.errorBuilder,
    this.decodeScale = 1.0,
  });

  final String imageUrl;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final ImageErrorWidgetBuilder? errorBuilder;

  /// A megjelenítési méret szorzója a dekódoláshoz (pl. nagyítható nézetben
  /// 2.0, hogy a kép nagyításkor is éles maradjon).
  final double decodeScale;

  @override
  State<OfflineImage> createState() => _OfflineImageState();
}

class _OfflineImageState extends State<OfflineImage> {
  File? _cachedFile;
  Uint8List? _inlineBytes;

  String get _normalizedUrl => widget.imageUrl.trim();

  bool _isDataImageUrl(String url) {
    return url.startsWith('data:image/');
  }

  Uint8List? _decodeInlineImage(String url) {
    try {
      final uriData = UriData.parse(url);
      return Uint8List.fromList(uriData.contentAsBytes());
    } catch (_) {
      final commaIndex = url.indexOf(',');
      if (commaIndex == -1) return null;
      final payload = url
          .substring(commaIndex + 1)
          .replaceAll('\n', '')
          .replaceAll('\r', '');
      try {
        return Uint8List.fromList(base64Decode(payload));
      } catch (_) {
        return null;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant OfflineImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _cachedFile = null;
      _inlineBytes = null;
      _resolveImage();
    }
  }

  Future<void> _resolveImage() async {
    final url = _normalizedUrl;
    if (url.isEmpty) return;

    if (_isDataImageUrl(url)) {
      final bytes = _decodeInlineImage(url);
      if (bytes != null && mounted) {
        setState(() => _inlineBytes = bytes);
      }
      return;
    }

    if (kIsWeb) return;

    // Egy közben érkezett képcsere (didUpdateWidget) után a régi, lassabb
    // betöltés eredménye nem írhatja felül az újat.
    bool stillCurrent() => mounted && url == _normalizedUrl;

    final cached = await OfflineImageService.getCachedFile(url);
    if (cached != null) {
      if (stillCurrent()) setState(() => _cachedFile = cached);
      return;
    }

    final downloaded = await OfflineImageService.cacheImage(url);
    if (downloaded != null && stillCurrent()) {
      setState(() => _cachedFile = downloaded);
    }
  }

  /// A dekódolási szélesség fizikai pixelben: a kép csak akkora felbontásban
  /// kerül a memóriába, amekkorában megjelenik (egy 12 MP-es fotó teljes
  /// felbontásban ~48 MB lenne). Ismeretlen méretnél a képernyőszélesség.
  int _decodeWidth(BuildContext context, BoxConstraints constraints) {
    final media = MediaQuery.of(context);
    final logical =
        widget.width ??
        (constraints.hasBoundedWidth ? constraints.maxWidth : media.size.width);
    return (logical * media.devicePixelRatio * widget.decodeScale)
        .round()
        .clamp(1, 4096);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cacheWidth = _decodeWidth(context, constraints);
        if (_inlineBytes != null) {
          return Image.memory(
            _inlineBytes!,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            cacheWidth: cacheWidth,
            errorBuilder: widget.errorBuilder,
          );
        }

        if (_cachedFile != null) {
          return Image.file(
            _cachedFile!,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            cacheWidth: cacheWidth,
            errorBuilder: widget.errorBuilder,
          );
        }

        return Image.network(
          _normalizedUrl,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          cacheWidth: cacheWidth,
          errorBuilder: widget.errorBuilder,
        );
      },
    );
  }
}
