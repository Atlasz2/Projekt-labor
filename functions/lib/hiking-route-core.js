// Túraútvonal-tervezés magja (I/O nélkül, hogy egységteszttel fedhető legyen).
//
// MIÉRT SZERVEROLDALON: a böngészőből a Valhalla nem hívható megbízhatóan
// (CORS / hálózati korlátok), ezért az admin panel a saját Cloud Functionünkön
// keresztül kéri az útvonalat. Így az admin PONTOSAN ugyanazt a
// föld- és erdeiút-preferáló útvonalat kapja, mint a mobilalkalmazás.

/** Valhalla polyline6 dekódolása [lat, lon] párokká. */
export function decodePolyline6(encoded) {
  const points = [];
  const factor = 1e6;
  let index = 0;
  let lat = 0;
  let lon = 0;

  while (index < encoded.length) {
    let result = 0;
    let shift = 0;
    let b;

    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (result & 1) !== 0 ? ~(result >> 1) : result >> 1;

    result = 0;
    shift = 0;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lon += (result & 1) !== 0 ? ~(result >> 1) : result >> 1;

    points.push([lat / factor, lon / factor]);
  }

  return points;
}

/** Szakaszok összefűzése úgy, hogy az illesztési pont ne duplázódjon. */
export function appendRoutePoints(target, segment) {
  if (!segment.length) return target;
  if (!target.length) {
    target.push(...segment);
    return target;
  }

  const [lastLat, lastLon] = target[target.length - 1];
  const [firstLat, firstLon] = segment[0];
  const sameStart =
    Math.abs(lastLat - firstLat) <= 0.00002 &&
    Math.abs(lastLon - firstLon) <= 0.00002;

  target.push(...(sameStart ? segment.slice(1) : segment));
  return target;
}

/** A Valhalla kérés törzse. Megegyezik a mobilalkalmazáséval:
 *  `use_tracks: 1.0` → a földutakat/nyomvonalakat részesíti előnyben,
 *  `use_hills: 0.6` → a domborzatot is figyelembe veszi. */
export function buildValhallaPayload(coordinates) {
  return {
    locations: coordinates.map(([lat, lon]) => ({ lat, lon, type: 'break' })),
    costing: 'pedestrian',
    costing_options: {
      pedestrian: {
        use_tracks: 1.0,
        use_hills: 0.6,
        walking_speed: 3.5,
        transit_start_end_max_distance: 0,
      },
    },
    directions_type: 'none',
  };
}

/** Valhalla válasz → egységes útvonal-objektum (vagy null). */
export function parseValhallaResponse(data) {
  const trip = data?.trip;
  const legs = Array.isArray(trip?.legs) ? trip.legs : [];
  if (legs.length === 0) return null;

  const coords = [];
  for (const leg of legs) {
    const shape = typeof leg?.shape === 'string' ? leg.shape : '';
    if (!shape) continue;
    appendRoutePoints(coords, decodePolyline6(shape));
  }
  if (coords.length < 2) return null;

  const summary = trip?.summary ?? {};
  return {
    coords,
    // A Valhalla kilométerben adja a hosszt.
    distanceMeters: (Number(summary.length) || 0) * 1000,
    durationSeconds: Number(summary.time) || 0,
    source: 'valhalla-pedestrian',
  };
}

/** OSRM (gyalogos) válasz → egységes útvonal-objektum (vagy null).
 *  Az OSRM GeoJSON [lon, lat] sorrendet ad, ezt fordítjuk [lat, lon]-ra. */
export function parseOsrmResponse(data) {
  const route = Array.isArray(data?.routes) ? data.routes[0] : null;
  const raw = route?.geometry?.coordinates;
  if (!Array.isArray(raw)) return null;

  const coords = raw
    .map((pair) =>
      Array.isArray(pair) &&
      Number.isFinite(Number(pair[0])) &&
      Number.isFinite(Number(pair[1]))
        ? [Number(pair[1]), Number(pair[0])]
        : null,
    )
    .filter(Boolean);
  if (coords.length < 2) return null;

  return {
    coords,
    distanceMeters: Number(route.distance) || 0,
    durationSeconds: Number(route.duration) || 0,
    source: 'osrm-foot',
  };
}

/** Az OSRM lekérdezés útvonal-szegmense (`lon,lat;lon,lat…`). */
export function buildOsrmPath(coordinates) {
  return coordinates.map(([lat, lon]) => `${lon},${lat}`).join(';');
}

/** A bejövő koordináták ellenőrzése és normalizálása [lat, lon] párokká. */
export function normalizeCoordinates(input) {
  if (!Array.isArray(input)) return [];
  return input
    .map((pair) => {
      if (!Array.isArray(pair) || pair.length < 2) return null;
      const lat = Number(pair[0]);
      const lon = Number(pair[1]);
      if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
      if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
      return [lat, lon];
    })
    .filter(Boolean);
}

/** BRouter lekérdezés URL-je. A BRouter kifejezetten túrázásra készült:
 *  a `hiking-beta` profil a föld- és erdei utakat, ösvényeket részesíti
 *  előnyben a közutak helyett. Kulcs nélkül használható. */
export function buildBRouterUrl(coordinates, profile = 'hiking-beta') {
  const lonlats = coordinates.map(([lat, lon]) => `${lon},${lat}`).join('|');
  return (
    'https://brouter.de/brouter' +
    `?lonlats=${lonlats}&profile=${profile}&alternativeidx=0&format=geojson`
  );
}

/** BRouter GeoJSON válasz → egységes útvonal-objektum (vagy null).
 *  A koordináták [lon, lat] (esetleg magassággal) formában jönnek. */
export function parseBRouterResponse(data) {
  const feature = Array.isArray(data?.features) ? data.features[0] : null;
  const raw = feature?.geometry?.coordinates;
  if (!Array.isArray(raw)) return null;

  const coords = raw
    .map((pair) => {
      if (!Array.isArray(pair) || pair.length < 2) return null;
      const lon = Number(pair[0]);
      const lat = Number(pair[1]);
      if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
      return [lat, lon];
    })
    .filter(Boolean);
  if (coords.length < 2) return null;

  const props = feature?.properties ?? {};
  return {
    coords,
    distanceMeters: Number(props['track-length']) || 0,
    durationSeconds: Number(props['total-time']) || 0,
    source: 'brouter-hiking',
  };
}
