import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class OfflineImageService {
  static const String _imageRootFolder = 'offline_images';

  static Future<Directory> get _rootDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}$_imageRootFolder');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _fileNameForUrl(String url) {
    final encoded = base64Url.encode(utf8.encode(url)).replaceAll('=', '');
    return '$encoded.img';
  }

  static Future<File?> getCachedFile(String url) async {
    final normalized = url.trim();
    if (kIsWeb || normalized.isEmpty) return null;
    final root = await _rootDir;
    final file = File('${root.path}${Platform.pathSeparator}${_fileNameForUrl(normalized)}');
    return await file.exists() ? file : null;
  }

  static Future<File?> cacheImage(String url) async {
    final normalized = url.trim();
    if (kIsWeb || normalized.isEmpty) return null;

    final existing = await getCachedFile(normalized);
    if (existing != null) return existing;

    final root = await _rootDir;
    final file = File('${root.path}${Platform.pathSeparator}${_fileNameForUrl(normalized)}');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.getUrl(Uri.parse(normalized));
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk)).timeout(const Duration(seconds: 15));
      await file.writeAsBytes(bytes, flush: false);
      return file;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<int> cacheImages(
    Iterable<String> urls, {
    Future<void> Function(int done, int total)? onProgress,
  }) async {
    if (kIsWeb) return 0;

    final uniqueUrls = urls.map((url) => url.trim()).where((url) => url.isNotEmpty).toSet().toList(growable: false);
    var done = 0;
    var cached = 0;

    for (final url in uniqueUrls) {
      final file = await cacheImage(url);
      done += 1;
      if (file != null) {
        cached += 1;
      }
      if (onProgress != null) {
        await onProgress(done, uniqueUrls.length);
      }
    }

    return cached;
  }
}
