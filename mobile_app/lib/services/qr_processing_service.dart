import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';

import 'location_service.dart';
import '../config/app_config.dart';

/// A beolvasás pillanatában rögzített eszközpozíció.
typedef ScanLocation = ({double lat, double lng});

/// Alapértelmezett megengedett távolság az állomástól (méter), ha az állomás
/// nem ad meg saját `radius` mezőt. Egyeznie kell a szerveroldali
/// DEFAULT_LOCATION_RADIUS_M értékkel (functions/lib/redeem-core.js).
const double kDefaultLocationRadiusM = 150;

/// Mit azonosított a beolvasott QR-kód: állomást vagy eseményt.
enum QrTargetKind { station, event }

class QrProcessResult {
  const QrProcessResult({
    required this.target,
    required this.kind,
    required this.alreadyDone,
    required this.newAchievements,
    required this.updatedPoints,
    required this.completedStationsCount,
    required this.completedEventsCount,
  });

  /// A beolvasott állomás vagy esemény dokumentuma (`kind` mondja meg, melyik).
  final Map<String, dynamic> target;
  final QrTargetKind kind;
  final bool alreadyDone;
  final List<Map<String, dynamic>> newAchievements;
  final int updatedPoints;
  final int completedStationsCount;
  final int completedEventsCount;
}

/// Végleges hiba: a beolvasott kód egyetlen állomáshoz vagy eseményhez sem
/// tartozik. Az offline várólista ezt eldobja (nem próbálja újra).
class QrCodeNotFoundException implements Exception {
  const QrCodeNotFoundException(this.code);

  final String code;

  @override
  String toString() => 'Ismeretlen QR-kód: $code';
}

/// Végleges hiba: a kód egy MÁSIK településhez tartozik, ezért ebben a
/// kiadásban nem írható jóvá (white-label védelem).
class QrWrongProjectException implements Exception {
  const QrWrongProjectException();

  @override
  String toString() => 'A QR-kód egy másik településhez tartozik.';
}

/// Átmeneti hiba: a szerveroldali jóváírás (redeemQr) nem érhető el. A pontot
/// kizárólag a szerver írhatja (lásd firestore.rules), ezért ilyenkor nincs
/// kliensoldali tartalék – az offline várólista később újrapróbálja.
class QrServerUnavailableException implements Exception {
  const QrServerUnavailableException();

  @override
  String toString() =>
      'A jóváírási szolgáltatás most nem érhető el, próbáld újra később.';
}

/// Végleges hiba (erre a beolvasásra): az eszköz túl messze van a helyhez
/// kötött céltól, a jóváírás elmaradt.
class QrOutOfRangeException implements Exception {
  const QrOutOfRangeException({
    required this.distance,
    required this.threshold,
  });

  /// Mért távolság az állomástól, méterben.
  final int distance;

  /// A megengedett maximális távolság, méterben.
  final int threshold;

  @override
  String toString() =>
      'Túl messze vagy az állomástól ($distance m, max $threshold m).';
}

/// Végleges hiba (erre a beolvasásra): az állomáshoz kötelező a
/// helymeghatározás, de a beolvasáskor nem volt pozíció.
class QrLocationRequiredException implements Exception {
  const QrLocationRequiredException();

  @override
  String toString() =>
      'Ennél az állomásnál a pontszerzéshez be kell kapcsolni a helymeghatározást.';
}

/// A szerveroldali jóváírás hívása — tesztekben lecserélhető.
typedef ServerRedeem =
    Future<Map<String, dynamic>> Function(String code, ScanLocation? location);

/// QR-beolvasás feldolgozása. A validáció, a pontszámítás, a jutalom-feloldás
/// és a ranglista-írás a `redeemQr` Cloud Functionben fut (Admin SDK-val); a
/// kliens csak a nyers kódot, a pozíciót és a kiadás települését küldi be.
class QrProcessingService {
  const QrProcessingService._();

  /// Tesztekben lecserélhető; élesben a redeemQr Cloud Functiont hívja.
  static ServerRedeem? serverRedeemOverride;

  static Future<QrProcessResult> processByCode({
    required String code,
    ScanLocation? location,
  }) async {
    final payload = await (serverRedeemOverride ?? _callRedeemFunction)(
      code,
      location,
    );

    if (payload['found'] == false) throw QrCodeNotFoundException(code);
    if (payload['rejected'] == 'wrong_project') {
      throw const QrWrongProjectException();
    }
    if (payload['rejected'] == 'location_required') {
      throw const QrLocationRequiredException();
    }
    if (payload['rejected'] == 'out_of_range') {
      throw QrOutOfRangeException(
        distance: (payload['distance'] as num?)?.round() ?? 0,
        threshold:
            (payload['threshold'] as num?)?.round() ??
            kDefaultLocationRadiusM.round(),
      );
    }
    return _resultFromServerPayload(payload);
  }

  /// Átmeneti-e a hiba (hálózat, szerver-túlterhelés), vagyis érdemes-e a
  /// beolvasást az offline sorba tenni és később újrapróbálni. A szerver
  /// elutasítása (pl. hitelesítési hiba) NEM átmeneti: azt a felhasználónak
  /// a valódi okkal kell jelezni, nem „instabil kapcsolatként”.
  static bool isTransientError(Object error) {
    if (error is QrServerUnavailableException) return true;
    if (error is SocketException || error is TimeoutException) return true;
    if (error is FirebaseFunctionsException) {
      return const {
        'unavailable',
        'deadline-exceeded',
        'resource-exhausted',
        'aborted',
        'cancelled',
        'internal',
        'unknown',
      }.contains(error.code);
    }
    return false;
  }

  /// A nem átmeneti hiba felhasználónak szóló magyarázata.
  static String rejectionMessage(Object error) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'unauthenticated':
        case 'permission-denied':
          return 'A szerver nem fogadta el az alkalmazás hitelesítését. '
              'Frissítsd az alkalmazást a legújabb verzióra, vagy jelentkezz be újra.';
        case 'invalid-argument':
          return 'A beolvasott kód nem értelmezhető.';
      }
    }
    return 'A beolvasás feldolgozása nem sikerült. Próbáld újra.';
  }

  /// A kód SHA-256 lenyomata (kisbetűs hex) – ugyanaz, amit az admin felület
  /// a nyilvános dokumentum `qrHash` mezőjébe ír.
  static String qrHash(String code) =>
      sha256.convert(utf8.encode(code)).toString();

  /// Ehhez az (offline gyorsítótárban lévő) állomáshoz tartozik-e a kód.
  /// A QR-migráció után a nyilvános dokumentum csak a lenyomatot tárolja
  /// (`qrHash`); a migráció előtti adatnál a régi `qrCode` mező, illetve a
  /// dokumentum-azonosító dönt.
  static bool matchesStation(Map<String, dynamic> station, String code) {
    final normalized = code.trim();
    if (normalized.isEmpty) return false;
    final hash = station['qrHash']?.toString();
    if (hash != null && hash.isNotEmpty) return qrHash(normalized) == hash;
    return station['qrCode']?.toString().trim() == normalized ||
        station['id']?.toString().trim() == normalized;
  }

  /// Kell-e pozíció a beváltáshoz – a szerveroldali requiresLocation tükre:
  /// minden helyhez kötött (koordinátával rendelkező) célnál igen, hacsak az
  /// admin kifejezetten nem engedi a pozíció nélküli beváltást.
  static bool requiresLocation(Map<String, dynamic> station) =>
      _targetLatLng(station) != null && station['requireLocation'] != false;

  /// A cél koordinátája `(lat, lng)`, vagy null, ha nincs érvényes helye.
  static ScanLocation? _targetLatLng(Map<String, dynamic> data) {
    num? asNum(dynamic v) => v is num ? v : null;
    final loc = data['location'];
    final lat =
        asNum(data['latitude']) ?? (loc is Map ? asNum(loc['latitude']) : null);
    final lng =
        asNum(data['longitude']) ??
        (loc is Map ? asNum(loc['longitude']) : null);
    if (lat == null || lng == null) return null;
    if (lat == 0 && lng == 0) return null; // hiányzó koordináta jelzője
    return (lat: lat.toDouble(), lng: lng.toDouble());
  }

  /// Kliensoldali helyszín-ellenőrzés — a szerveroldali checkLocation tükre.
  /// Az offline beolvasás ezzel szűri ki a sorba állítás előtt azt, amit a
  /// szerver úgyis elutasítana. Kiutasításnál a részleteket adja vissza,
  /// egyébként (rendben van, vagy nincs mit ellenőrizni) null-t.
  static ({int distance, int threshold})? locationRejection(
    Map<String, dynamic> targetData,
    ScanLocation? location,
  ) {
    // A helyhez kötöttségből kivett állomásnál a távolság sem számít.
    if (targetData['requireLocation'] == false) return null;
    final target = _targetLatLng(targetData);
    if (target == null || location == null) return null;

    final distance = LocationService.distanceMeters(
      location.lat,
      location.lng,
      target.lat,
      target.lng,
    );
    final radius = targetData['radius'];
    final threshold = (radius is num && radius > 0)
        ? radius.toDouble()
        : kDefaultLocationRadiusM;

    if (distance > threshold) {
      return (distance: distance.round(), threshold: threshold.round());
    }
    return null;
  }

  static Future<Map<String, dynamic>> _callRedeemFunction(
    String code,
    ScanLocation? location,
  ) async {
    final callable = FirebaseFunctions.instanceFor(
      region: 'europe-west1',
    ).httpsCallable('redeemQr');
    try {
      final response = await callable.call<dynamic>({
        'code': code,
        // A kiadás települése: a szerver elutasítja a más településhez tartozó
        // QR-kódot (white-label védelem).
        'projectId': AppConfig.projectId,
        if (location != null) 'lat': location.lat,
        if (location != null) 'lng': location.lng,
      });
      return stringKeyedMap(response.data);
    } on FirebaseFunctionsException catch (e) {
      // 'not-found'/'unimplemented': maga a függvény nem létezik (ismeretlen
      // kódra a szerver nem hibát, hanem found:false-t ad).
      if (e.code == 'not-found' || e.code == 'unimplemented') {
        throw const QrServerUnavailableException();
      }
      // Minden más (unavailable, deadline-exceeded, internal, ...) átmeneti:
      // továbbdobjuk, a hívó / az offline várólista kezeli.
      rethrow;
    }
  }

  /// A callable válaszában a beágyazott map-ek `Map<Object?, Object?>`-ként
  /// érkeznek — rekurzívan String-kulcsos map-ekké alakítjuk.
  static Map<String, dynamic> stringKeyedMap(dynamic value) {
    final map = value as Map;
    return map.map((key, v) {
      dynamic converted = v;
      if (v is Map) {
        converted = stringKeyedMap(v);
      } else if (v is List) {
        converted = v.map((e) => e is Map ? stringKeyedMap(e) : e).toList();
      }
      return MapEntry(key.toString(), converted);
    });
  }

  static QrProcessResult _resultFromServerPayload(
    Map<String, dynamic> payload,
  ) {
    final rawAchievements = (payload['newAchievements'] as List?) ?? const [];
    return QrProcessResult(
      target: stringKeyedMap(payload['target'] ?? const <String, dynamic>{}),
      kind: payload['kind'] == 'event'
          ? QrTargetKind.event
          : QrTargetKind.station,
      alreadyDone: payload['alreadyDone'] == true,
      newAchievements: rawAchievements
          .whereType<Map>()
          .map(stringKeyedMap)
          .toList(),
      updatedPoints: (payload['updatedPoints'] as num?)?.toInt() ?? 0,
      completedStationsCount:
          (payload['completedStationsCount'] as num?)?.toInt() ?? 0,
      completedEventsCount:
          (payload['completedEventsCount'] as num?)?.toInt() ?? 0,
    );
  }
}
