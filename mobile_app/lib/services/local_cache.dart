import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:latlong2/latlong.dart';

class LocalCache {
  static const _kTrips = 'trips_v1';
  static const _kStations = 'stations_v1';
  static const _kAchievements = 'achievements_v1';
  static const _kPendingQr = 'pending_qr_v1';
  static const _kRoutes = 'routes_v1';
  static const _kMeta = 'meta_v1';

  static Future<void> init() async {
    await Future.wait([
      Hive.openBox<dynamic>(_kTrips),
      Hive.openBox<dynamic>(_kStations),
      Hive.openBox<dynamic>(_kAchievements),
      Hive.openBox<dynamic>(_kPendingQr),
      Hive.openBox<dynamic>(_kRoutes),
      Hive.openBox<dynamic>(_kMeta),
    ]);
  }

  static Box<dynamic> get _trips => Hive.box(_kTrips);
  static Box<dynamic> get _stations => Hive.box(_kStations);
  static Box<dynamic> get _achievements => Hive.box(_kAchievements);
  static Box<dynamic> get _pendingQr => Hive.box(_kPendingQr);
  static Box<dynamic> get _routes => Hive.box(_kRoutes);
  static Box<dynamic> get _meta => Hive.box(_kMeta);

  static Future<void> saveTrips(List<Map<String, dynamic>> trips) async {
    await _trips.clear();
    for (final t in trips) {
      await _trips.put(t['id'] as String, _sanitize(t));
    }
    await _meta.put('tripsAt', DateTime.now().millisecondsSinceEpoch);
  }

  static List<Map<String, dynamic>> getTrips() =>
      _trips.values.map(_castMap).where((m) => m.isNotEmpty).toList();

  static Future<void> saveStations(List<Map<String, dynamic>> stations) async {
    await _stations.clear();
    for (final s in stations) {
      await _stations.put(s['id'] as String, _sanitize(s));
    }
  }

  static List<Map<String, dynamic>> getStations() =>
      _stations.values.map(_castMap).where((m) => m.isNotEmpty).toList();

  static Future<void> saveAchievements(
    List<Map<String, dynamic>> achievements,
  ) async {
    await _achievements.clear();
    for (final a in achievements) {
      await _achievements.put(a['id'] as String, _sanitize(a));
    }
  }

  static List<Map<String, dynamic>> getAchievements() =>
      _achievements.values.map(_castMap).where((m) => m.isNotEmpty).toList();

  static Future<void> saveRoute(
    String tripId,
    List<LatLng> points,
    Map<String, String> metrics,
  ) async {
    await _routes.put(tripId, {
      'points': points
          .map((p) => <String, double>{'lat': p.latitude, 'lng': p.longitude})
          .toList(),
      'metrics': Map<String, String>.from(metrics),
    });
  }

  static Map<String, dynamic>? getRoute(String tripId) {
    final value = _routes.get(tripId);
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  static Future<bool> enqueuePendingQr(String qrCode) async {
    final normalized = qrCode.trim();
    if (normalized.isEmpty) return false;

    for (final value in _pendingQr.values) {
      if ((value ?? '').toString().trim() == normalized) {
        return false;
      }
    }

    final key = DateTime.now().microsecondsSinceEpoch.toString();
    await _pendingQr.put(key, normalized);
    return true;
  }

  static bool hasPendingQrCode(String qrCode) {
    final normalized = qrCode.trim();
    if (normalized.isEmpty) return false;
    for (final value in _pendingQr.values) {
      if ((value ?? '').toString().trim() == normalized) {
        return true;
      }
    }
    return false;
  }

  static Map<String, String> getPendingQrQueue() => {
    for (final k in List<dynamic>.from(_pendingQr.keys))
      k.toString(): (_pendingQr.get(k) ?? '').toString(),
  };

  static Future<void> removePendingQr(String key) => _pendingQr.delete(key);

  static bool get hasPendingQr => _pendingQr.isNotEmpty;

  static bool get hasData => _trips.isNotEmpty && _stations.isNotEmpty;

  static bool get isCacheStale {
    final ts = _meta.get('tripsAt') as int?;
    if (ts == null) return true;
    return DateTime.now().millisecondsSinceEpoch - ts >
        const Duration(hours: 12).inMilliseconds;
  }

  static Map<String, dynamic> _castMap(dynamic v) {
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    return {};
  }

  static dynamic _sanitizeValue(dynamic value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is GeoPoint) {
      return <String, dynamic>{'lat': value.latitude, 'lng': value.longitude};
    }
    if (value is DocumentReference) return value.path;
    if (value is Map) {
      return Map<String, dynamic>.fromEntries(
        value.entries.map(
          (e) => MapEntry(e.key.toString(), _sanitizeValue(e.value)),
        ),
      );
    }
    if (value is List) return value.map(_sanitizeValue).toList();
    return value;
  }

  static Map<String, dynamic> _sanitize(Map<String, dynamic> m) =>
      _sanitizeValue(m) as Map<String, dynamic>;
}
