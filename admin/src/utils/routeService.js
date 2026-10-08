import { httpsCallable } from "firebase/functions";
import { functions } from "../firebaseConfig";

// Az útvonaltervezés SZERVEROLDALON fut (hikingRoute Cloud Function), mert a
// böngészőből a Valhalla nem hívható megbízhatóan (CORS / hálózati korlátok).
// Így az admin panel PONTOSAN ugyanazt a föld- és erdeiút-preferáló útvonalat
// kapja, mint a mobilalkalmazás (use_tracks), OSRM tartalékkal.
//
// A válasz alakja: { coords: [[lat, lon], ...], distanceMeters,
// durationSeconds, source } — a `source` mutatja, melyik ág adta
// ("valhalla-pedestrian", "osrm-foot" vagy "fallback" = egyenes szakaszok).

/** Gyalogos túraútvonal a megadott [lat, lon] pontok között. Hiba esetén
 *  egyenes összekötést ad vissza, hogy a térkép sose maradjon üresen. */
export async function getRouteData(coordinates) {
  if (!Array.isArray(coordinates) || coordinates.length < 2) {
    return { coords: [], distanceMeters: 0, durationSeconds: 0, source: "none" };
  }

  try {
    const call = httpsCallable(functions, "hikingRoute");
    const res = await call({ coordinates });
    const data = res?.data;
    if (Array.isArray(data?.coords) && data.coords.length >= 2) {
      return data;
    }
  } catch {
    // A függvény nem elérhető / hiba – marad az egyenes összekötés.
  }

  return {
    coords: coordinates,
    distanceMeters: 0,
    durationSeconds: 0,
    source: "fallback",
  };
}

export const formatDistance = (meters) => {
  if (!meters || meters <= 0) return "N/A";
  return `${(meters / 1000).toFixed(1)} km`;
};

export const formatDuration = (seconds) => {
  if (!seconds || seconds <= 0) return "N/A";
  const totalMinutes = Math.max(1, Math.round(seconds / 60));
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours > 0) return `${hours} o ${minutes} p`;
  return `${minutes} p`;
};

/** Egy koordinátapár normalizálása [lat, lng] számpárrá. Elfogadja az
 *  [a, b] tömböt (a `reverse` a GeoJSON [lng, lat] sorrendet fordítja) és a
 *  Firestore-ban tárolt { lat, lng } objektumot is. */
export const normalizeCoordinatePair = (pair, reverse = false) => {
  if (pair && !Array.isArray(pair) && typeof pair === "object") {
    const rawLat = pair.lat ?? pair.latitude;
    const rawLng = pair.lng ?? pair.lon ?? pair.longitude;
    if (rawLat == null || rawLng == null) return null;
    const lat = Number(rawLat);
    const lng = Number(rawLng);
    return Number.isFinite(lat) && Number.isFinite(lng) ? [lat, lng] : null;
  }
  if (!Array.isArray(pair) || pair.length < 2) return null;
  // Hiányzó érték ne váljon 0-vá (az Atlanti-óceánba kerülő pont).
  if (pair[0] == null || pair[1] == null || pair[0] === "" || pair[1] === "") return null;

  const first = Number(pair[0]);
  const second = Number(pair[1]);

  if (!Number.isFinite(first) || !Number.isFinite(second)) return null;

  return reverse ? [second, first] : [first, second];
};

/** A túrához KORÁBBAN ELMENTETT útvonal pontjai (a Túrák oldal menti el a
 *  Valhalla-lekérés eredményét). Ha van, ezt kell használni: azonnali, és a
 *  valódi turistaút — nem légvonal. Több régi mezőnevet is elfogad. */
/** Az útvonal Firestore-ba írható alakja: a Firestore nem enged egymásba
 *  ágyazott tömböt, ezért a pontok { lat, lng } objektumként tárolódnak
 *  (a mobil decodeStoredRoute-ja mindkét alakot olvassa). */
export const toStoredRouteCoordinates = (coords) =>
  (coords ?? [])
    .map((pair) => normalizeCoordinatePair(pair))
    .filter(Boolean)
    .map(([lat, lng]) => ({ lat, lng }));

export const getStoredRouteCoordinates = (trip) => {
  const routeFields = [
    trip?.routeCoordinates,
    trip?.routePoints,
    trip?.path,
    trip?.waypoints,
  ];

  for (const field of routeFields) {
    if (!Array.isArray(field) || field.length === 0) continue;
    const coords = field.map((pair) => normalizeCoordinatePair(pair)).filter(Boolean);
    if (coords.length > 0) return coords;
  }

  const geometryCoordinates = trip?.geometry?.coordinates;
  if (!Array.isArray(geometryCoordinates) || geometryCoordinates.length === 0) {
    return [];
  }

  return geometryCoordinates
    .map((pair) => normalizeCoordinatePair(pair, true))
    .filter(Boolean);
};
