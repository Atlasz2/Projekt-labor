import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

class OfflineImageService {
  static const String _imageRootFolder = 'offline_images';

  /// A gyökérkönyvtár egyszer kerül feloldásra (nem minden képnél újra).
  static Future<Directory>? _rootDirFuture;

  /// A folyamatban lévő letöltések URL szerint: ugyanaz a kép (pl. lista és
  /// részletező egyszerre) csak egyszer töltődik le.
  static final Map<String, Future<File?>> _inFlight = {};

  static Future<Directory> get _rootDir => _rootDirFuture ??= () async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}$_imageRootFolder',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }();

  static String _fileNameForUrl(String url) {
    final encoded = base64Url.encode(utf8.encode(url)).replaceAll('=', '');
    return '$encoded.img';
  }

  static Future<File?> getCachedFile(String url) async {
    final normalized = url.trim();
    if (kIsWeb || normalized.isEmpty) return null;
    final root = await _rootDir;
    final file = File(
      '${root.path}${Platform.pathSeparator}${_fileNameForUrl(normalized)}',
    );
    return await file.exists() ? file : null;
  }

  static Future<File?> cacheImage(String url) async {
    final normalized = url.trim();
    if (kIsWeb || normalized.isEmpty) return null;

    final pending = _inFlight[normalized];
    if (pending != null) return pending;
    final future = _download(normalized);
    _inFlight[normalized] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(normalized);
    }
  }

  static Future<File?> _download(String url) async {
    final existing = await getCachedFile(url);
    if (existing != null) return existing;

    final root = await _rootDir;
    final file = File(
      '${root.path}${Platform.pathSeparator}${_fileNameForUrl(url)}',
    );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) return null;
      // BytesBuilder: a darabok másolás nélkül fűződnek össze (egy List<int>
      // elemenkénti bővítése egy 2 MB-os képnél érezhetően lassú).
      final bytes = await response
          .fold<BytesBuilder>(
            BytesBuilder(copy: false),
            (b, chunk) => b..add(chunk),
          )
          .timeout(const Duration(seconds: 30));
      // Ideiglenes fájlba írás, majd átnevezés: megszakadt letöltésből nem
      // marad félkész, „gyorsítótárazottnak” látszó kép.
      final temp = File('${file.path}.part');
      await temp.writeAsBytes(bytes.takeBytes(), flush: true);
      return await temp.rename(file.path);
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

    final uniqueUrls = urls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toSet()
        .toList(growable: false);
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
