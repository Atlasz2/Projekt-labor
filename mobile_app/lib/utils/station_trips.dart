// Egy állomás túra-tagságai: egy állomás 0, 1 vagy TÖBB túrának is
// megállója lehet (pl. egy közös várbeli állomás egy rövid és egy hosszú
// túrán is szerepelhet). Ugyanaz a logika, mint az admin
// (admin/src/utils/stationTrips.js) és a szerver
// (functions/lib/station-trips-core.js) oldalán — a három csomag nem
// importálhat egymásból, ezért párhuzamos, de azonos viselkedésű másolat.
//
// Adatmodell (lásd docs/DATA_MODEL.md):
//   station['tripIds']  : List<String>           — melyik túráknak megállója
//   station['tripOrder']: Map<String, num>        — sorrend AZ ADOTT túrán belül
//
// Visszamenőleges kompatibilitás: a migráció előtti (vagy még le nem
// futtatott) dokumentumokon csak a régi egyszeres `tripId`/`orderIndex` mező
// van – ezt egyelemű tagságként kezeljük.

/// Egy állomás túra-azonosítóinak listája (üres lista, ha egyikhez sem tartozik).
List<String> stationTripIds(Map<String, dynamic> station) {
  final raw = station['tripIds'];
  if (raw is List && raw.isNotEmpty) {
    final seen = <String>{};
    for (final v in raw) {
      final id = v?.toString().trim() ?? '';
      if (id.isNotEmpty) seen.add(id);
    }
    return seen.toList();
  }
  final legacy = station['tripId']?.toString().trim() ?? '';
  return legacy.isNotEmpty ? [legacy] : [];
}

/// Az állomás megállója-e az adott túrának.
bool stationBelongsToTrip(Map<String, dynamic> station, String tripId) {
  return stationTripIds(station).contains(tripId);
}

/// Az állomás sorrend-indexe EZEN a túrán belül (0, ha nincs megadva).
int stationOrderIndexForTrip(Map<String, dynamic> station, String tripId) {
  final tripOrder = station['tripOrder'];
  if (tripOrder is Map) {
    final fromMap = tripOrder[tripId];
    if (fromMap is num) return fromMap.toInt();
  }
  final ids = stationTripIds(station);
  if (ids.length == 1 && ids.first == tripId) {
    final legacy = station['orderIndex'];
    if (legacy is num) return legacy.toInt();
  }
  return 0;
}

/// Egy túra állomásai, sorrendben (csak az adott túrához tartozók).
List<Map<String, dynamic>> stationsForTrip(
  List<Map<String, dynamic>> stations,
  String tripId,
) {
  final items = stations
      .where((s) => stationBelongsToTrip(s, tripId))
      .toList();
  items.sort(
    (a, b) => stationOrderIndexForTrip(
      a,
      tripId,
    ).compareTo(stationOrderIndexForTrip(b, tripId)),
  );
  return items;
}
