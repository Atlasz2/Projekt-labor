// Egy állomás túra-tagságai: mostantól egy állomás 0, 1 vagy TÖBB
// túrának is megállója lehet (pl. egy közös várbeli állomás egy rövid és
// egy hosszú túrán is szerepelhet).
//
// Adatmodell (lásd docs/DATA_MODEL.md):
//   station.tripIds  : string[]              — melyik túráknak megállója
//   station.tripOrder: { [tripId]: number }  — sorrend AZ ADOTT túrán belül
//
// Miért nem egy `[{tripId, orderIndex}]` tömb? A Firestore `array-contains`
// csak primitív/egzakt elem-egyezésre indexel jól, objektumra nem – a külön
// `tripIds` tömb + `tripOrder` map viszont hatékonyan lekérdezhető
// (`where('tripIds', 'array-contains', tripId)`) ÉS soronként frissíthető
// (`tripOrder.<tripId>` pont-jelöléssel), anélkül hogy a többi túra
// sorrendjét érintené.
//
// Visszamenőleges kompatibilitás: a migráció előtti (vagy még le nem
// futtatott) dokumentumokon csak a régi egyszeres `tripId`/`orderIndex` mező
// van – ezt egyelemű tagságként kezeljük, hogy semmi ne törjön el, amíg a
// `scripts/migrate-station-trip-memberships.mjs` le nem fut.

/** Egy állomás túra-azonosítóinak listája (üres tömb, ha egyikhez sem tartozik). */
export function stationTripIds(station) {
  const raw = station?.tripIds;
  if (Array.isArray(raw) && raw.length > 0) {
    return [...new Set(raw.map(String).map((s) => s.trim()).filter(Boolean))];
  }
  const legacy = String(station?.tripId ?? '').trim();
  return legacy ? [legacy] : [];
}

/** Az állomás megállója-e az adott túrának. */
export function stationBelongsToTrip(station, tripId) {
  return stationTripIds(station).includes(String(tripId));
}

/** Az állomás sorrend-indexe EZEN a túrán belül (0, ha nincs megadva). */
export function stationOrderIndexForTrip(station, tripId) {
  const fromMap = station?.tripOrder?.[tripId];
  if (fromMap != null && Number.isFinite(Number(fromMap))) return Number(fromMap);
  // Régi, egyetlen-túrás dokumentum: az egyetlen `orderIndex` mező vonatkozik rá.
  const ids = stationTripIds(station);
  if (ids.length === 1 && ids[0] === String(tripId)) {
    return Number(station?.orderIndex) || 0;
  }
  return 0;
}

/** Egy túra állomásai, sorrendben (csak az adott túrához tartozók). */
export function stationsForTrip(stations, tripId) {
  return (Array.isArray(stations) ? stations : [])
    .filter((s) => stationBelongsToTrip(s, tripId))
    .sort(
      (a, b) =>
        stationOrderIndexForTrip(a, tripId) - stationOrderIndexForTrip(b, tripId),
    );
}
