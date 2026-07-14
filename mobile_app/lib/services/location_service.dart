import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// A beolvasás pillanatában rögzített eszközpozíció lekérése és
/// távolság-számítás. A pozíciót a QR-jóváíráskor küldjük be a szervernek
/// (redeemQr), amely az állomás koordinátáihoz méri — így a QR-kód nem
/// használható a helyszíntől távol (lásd docs/SERVER_VALIDATION.md).
class LocationService {
  const LocationService._();

  /// Az aktuális eszközpozíció `(lat, lng)`, vagy `null`, ha nem elérhető
  /// (a helyszolgáltatás ki van kapcsolva, az engedélyt megtagadták, vagy a
  /// lekérés időtúllépésbe futott). A hívó ilyenkor pozíció nélkül folytat:
  /// a szerver a pozíció hiányát átengedi (graceful), a helyszínt csak
  /// beküldött pozícióra ellenőrzi.
  static Future<({double lat, double lng})?> currentLatLng({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(timeout);

      return (lat: position.latitude, lng: position.longitude);
    } catch (e) {
      debugPrint('LocationService.currentLatLng hiba: $e');
      return null;
    }
  }

  /// Két WGS84 koordináta közti távolság méterben (Haversine). Ugyanaz a
  /// képlet, mint a szerveroldali functions/lib/redeem-core.js-ben.
  static double distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadius = 6371000.0; // méter
    double toRad(double d) => d * math.pi / 180.0;
    final dLat = toRad(lat2 - lat1);
    final dLng = toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(lat1)) *
            math.cos(toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * earthRadius * math.asin(math.min(1.0, math.sqrt(a)));
  }
}
