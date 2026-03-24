import 'dart:io';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

class OfflineTilesService {
  static const String _tileRootFolder = 'offline_tiles';
  static const String _tileHost =
      'https://a.basemaps.cartocdn.com/rastertiles/voyager';
  static const String _tileReachabilityHost = 'a.basemaps.cartocdn.com';

  static const double minLat = 46.97;
  static const double maxLat = 47.04;
  static const double minLng = 17.65;
  static const double maxLng = 17.75;

  static Future<Directory> get _rootDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}$_tileRootFolder',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String> get tileTemplatePath async {
    final dir = await _rootDir;
    final sep = Platform.pathSeparator;
    return '${dir.path}$sep{z}$sep{x}$sep{y}.png';
  }

  static Future<bool> hasOfflineTiles() async {
    final dir = await _rootDir;
    if (!await dir.exists()) return false;
    final entities = dir.listSync(recursive: true, followLinks: false);
    return entities.any((e) => e is File && e.path.endsWith('.png'));
  }

  static Future<bool> isOnline() async {
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      final hasNetworkInterface = connectivityResults.any(
        (x) => x != ConnectivityResult.none,
      );
      if (!hasNetworkInterface) return false;

      final addresses = await InternetAddress.lookup(
        _tileReachabilityHost,
      ).timeout(const Duration(seconds: 3));

      return addresses.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<int> downloadNagyvazsonyTiles({
    List<LatLng> focusPoints = const <LatLng>[],
    int minZoom = 13,
    int maxZoom = 19,
    Future<void> Function(int downloaded, int total)? onProgress,
  }) async {
    final online = await isOnline();
    if (!online) return 0;

    final root = await _rootDir;
    final jobs = focusPoints.isNotEmpty
        ? _buildCorridorJobs(focusPoints, minZoom, maxZoom)
        : _buildFallbackBboxJobs(minZoom, maxZoom);

    var processed = 0;
    var successful = 0;
    final total = jobs.length;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..maxConnectionsPerHost = 8
      ..userAgent = 'NagyvazsonyMobile/1.0 (offline tiles)';

    Future<void> markProgress(bool ok) async {
      processed++;
      if (ok) successful++;
      if (onProgress != null) {
        await onProgress(processed, total);
      }
    }

    try {
      const batchSize = 8;
      for (var index = 0; index < jobs.length; index += batchSize) {
        final batch = jobs.skip(index).take(batchSize);
        await Future.wait(
          batch.map((job) async {
            final zDir = Directory(
              '${root.path}${Platform.pathSeparator}${job.z}${Platform.pathSeparator}${job.x}',
            );
            if (!await zDir.exists()) await zDir.create(recursive: true);
            final file = File(
              '${zDir.path}${Platform.pathSeparator}${job.y}.png',
            );

            if (await file.exists()) {
              await markProgress(true);
              return;
            }

            final url = Uri.parse('$_tileHost/${job.z}/${job.x}/${job.y}.png');
            try {
              final req = await client.getUrl(url);
              final resp = await req.close();
              if (resp.statusCode == 200) {
                final bytes = await resp.fold<List<int>>(
                  <int>[],
                  (a, b) => a..addAll(b),
                );
                await file.writeAsBytes(bytes, flush: false);
                await markProgress(true);
                return;
              }
            } catch (_) {}

            await markProgress(false);
          }),
        );
      }
    } finally {
      client.close(force: true);
    }

    return successful;
  }

  static List<({int z, int x, int y})> _buildCorridorJobs(
    List<LatLng> points,
    int minZoom,
    int maxZoom,
  ) {
    final dedup = <String>{};
    final jobs = <({int z, int x, int y})>[];

    for (int z = minZoom; z <= maxZoom; z++) {
      final stride = math.max(1, points.length ~/ 180);

      for (int index = 0; index < points.length; index += stride) {
        final point = points[index];
        final tileX = _lonToTileX(point.longitude, z);
        final tileY = _latToTileY(point.latitude, z);

        for (int dx = -1; dx <= 1; dx++) {
          for (int dy = -1; dy <= 1; dy++) {
            final x = tileX + dx;
            final y = tileY + dy;
            final key = '$z:$x:$y';
            if (dedup.add(key)) {
              jobs.add((z: z, x: x, y: y));
            }
          }
        }
      }

      final last = points.last;
      final lastX = _lonToTileX(last.longitude, z);
      final lastY = _latToTileY(last.latitude, z);
      for (int dx = -1; dx <= 1; dx++) {
        for (int dy = -1; dy <= 1; dy++) {
          final x = lastX + dx;
          final y = lastY + dy;
          final key = '$z:$x:$y';
          if (dedup.add(key)) {
            jobs.add((z: z, x: x, y: y));
          }
        }
      }
    }

    return jobs;
  }

  static List<({int z, int x, int y})> _buildFallbackBboxJobs(
    int minZoom,
    int maxZoom,
  ) {
    final jobs = <({int z, int x, int y})>[];
    for (int z = minZoom; z <= maxZoom; z++) {
      final xMin = _lonToTileX(minLng, z);
      final xMax = _lonToTileX(maxLng, z);
      final yMin = _latToTileY(maxLat, z);
      final yMax = _latToTileY(minLat, z);

      for (int x = xMin; x <= xMax; x++) {
        for (int y = yMin; y <= yMax; y++) {
          jobs.add((z: z, x: x, y: y));
        }
      }
    }
    return jobs;
  }

  static Future<void> clearTiles() async {
    final dir = await _rootDir;
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }
  }

  static int _lonToTileX(double lon, int zoom) {
    final n = math.pow(2.0, zoom).toDouble();
    return ((lon + 180.0) / 360.0 * n).floor();
  }

  static int _latToTileY(double lat, int zoom) {
    final n = math.pow(2.0, zoom).toDouble();
    final latRad = lat * math.pi / 180.0;
    return ((1.0 -
                math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) /
            2.0 *
            n)
        .floor();
  }
}
