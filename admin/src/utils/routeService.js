import { safeString } from "./safeString";

const VALHALLA_URL = "https://valhalla1.openstreetmap.de/route";

function decodePolyline6(encoded) {
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

function appendRoutePoints(target, segment) {
  if (!segment.length) return;
  if (!target.length) {
    target.push(...segment);
    return;
  }

  const [lastLat, lastLon] = target[target.length - 1];
  const [firstLat, firstLon] = segment[0];
  const sameStart =
    Math.abs(lastLat - firstLat) <= 0.00002 &&
    Math.abs(lastLon - firstLon) <= 0.00002;

  target.push(...(sameStart ? segment.slice(1) : segment));
}

export async function getValhallaRouteData(coordinates) {
  if (!Array.isArray(coordinates) || coordinates.length < 2) {
    return { coords: [], distanceMeters: 0, durationSeconds: 0, source: "none" };
  }

  try {
    const payload = {
      locations: coordinates.map(([lat, lon]) => ({ lat, lon, type: "break" })),
      costing: "pedestrian",
      costing_options: {
        pedestrian: {
          use_tracks: 1.0,
          use_hills: 0.6,
          walking_speed: 3.5,
        },
      },
      directions_type: "none",
    };

    const response = await fetch(VALHALLA_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    if (!response.ok) throw new Error(`Valhalla HTTP ${response.status}`);

    const data = await response.json();
    const trip = data?.trip;
    const legs = Array.isArray(trip?.legs) ? trip.legs : [];
    const summary = trip?.summary || {};

    const coords = [];
    for (const leg of legs) {
      const shape = safeString(leg?.shape);
      if (!shape) continue;
      appendRoutePoints(coords, decodePolyline6(shape));
    }

    if (coords.length >= 2) {
      return {
        coords,
        distanceMeters: Number(summary.length || 0) * 1000,
        durationSeconds: Number(summary.time || 0),
        source: "valhalla-pedestrian",
      };
    }
  } catch (error) {
    console.error("Valhalla route error:", error);
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
