// Egy állomás túra-tagságai: mostantól egy állomás 0, 1 vagy TÖBB
// túrának is megállója lehet (pl. egy közös várbeli állomás egy rövid és
// egy hosszú túrán is szerepelhet). Lásd docs/DATA_MODEL.md és a
// functions/lib/station-trips-core.js párja (ugyanez a logika, csak a
// szerveroldalon — a két csomag nem importálhat egymásból).
//
// Adatmodell:
//   station.tripIds  : string[]              — melyik túráknak megállója
//   station.tripOrder: { [tripId]: number }  — sorrend AZ ADOTT túrán belül
//
// Visszamenőleges kompatibilitás: a migráció előtti (vagy még le nem
// futtatott) dokumentumokon csak a régi egyszeres `tripId`/`orderIndex` mező
// van – ezt egyelemű tagságként kezeljük.

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

/** Mentéskor építi a `tripOrder` map-et a kiválasztott túrákhoz: a MEGLÉVŐ
 *  tagságok sorrendjét megtartja, az ÚJAKAT a túra végére fűzi (a testvér-
 *  állomások legnagyobb sorrend-indexe + 1), a megszűnt tagságok kimaradnak. */
export function buildTripOrderOnSave({ station, allStations, selectedTripIds }) {
  const result = {};
  for (const tripId of selectedTripIds) {
    if (stationBelongsToTrip(station, tripId)) {
      result[tripId] = stationOrderIndexForTrip(station, tripId);
      continue;
    }
    const siblingMax = (allStations ?? [])
      .filter((s) => s.id !== station?.id && stationBelongsToTrip(s, tripId))
      .reduce((max, s) => Math.max(max, stationOrderIndexForTrip(s, tripId)), -1);
    result[tripId] = siblingMax + 1;
  }
  return result;
}
