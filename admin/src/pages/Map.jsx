import React, { useState, useEffect, useCallback, useMemo, useRef } from "react";
import {
  GoogleMap,
  Marker,
  Polyline,
  InfoWindow,
  useLoadScript,
} from "@react-google-maps/api";
import { db } from "../firebaseConfig";
import { collection, getDocs } from "firebase/firestore";
import "../styles/Map.css";
import {
  getRouteData,
  formatDistance,
  formatDuration,
  getStoredRouteCoordinates,
} from "../utils/routeService";
import { useProject } from "../context/ProjectContext";
import { filterByProject } from "../utils/projects";
import { stationTripIds, stationsForTrip } from "../utils/stationTrips";

const DEFAULT_CENTER = { lat: 47.06, lng: 17.715 };
const MAP_CONTAINER_STYLE = { height: "100vh", width: "100%" };

// Jól elkülöníthető, telített színek (kerülve az egymás mellett hasonló
// árnyalatokat), hogy több túraútvonal is egyértelműen megkülönböztethető
// legyen egyszerre a térképen.
const TRIP_COLORS = [
  "#E6194B", // piros
  "#3CB44B", // zöld
  "#4363D8", // kék
  "#F58231", // narancs
  "#911EB4", // lila
  "#008080", // sötétcián
  "#F032E6", // magenta
  "#9A6324", // barna
  "#800000", // bordó
  "#000075", // sötétkék
  "#808000", // olajzöld
  "#E91E9C", // pink
];

const getStationCoords = (station) => {
  const lat =
    typeof station.latitude === "number"
      ? station.latitude
      : station.location?.latitude;
  const lon =
    typeof station.longitude === "number"
      ? station.longitude
      : station.location?.longitude;
  if (typeof lat !== "number" || typeof lon !== "number") return null;
  return [lat, lon];
};

function Map() {
  const { activeProjectId } = useProject();
  const [stations, setStations] = useState([]);
  const [trips, setTrips] = useState([]);
  const [routeData, setRouteData] = useState({});
  const [loading, setLoading] = useState(true);
  const [routesLoading, setRoutesLoading] = useState(false);
  const [error, setError] = useState(null);
  const [center, setCenter] = useState(DEFAULT_CENTER);
  const [selectedStation, setSelectedStation] = useState(null);
  const [selectedTripId, setSelectedTripId] = useState(null);
  const mapRef = useRef(null);

  const { isLoaded, loadError } = useLoadScript({
    googleMapsApiKey: import.meta.env.VITE_GOOGLE_MAPS_API_KEY,
  });
  const handleMapLoad = useCallback((mapInstance) => {
    mapRef.current = mapInstance;
  }, []);
  // FIGYELEM: ebben a komponensben a `Map` név magát a komponenst jelenti,
  // ezért NEM használható a beépített `new Map()` (lásd fetchData lentebb is)
  // – sima objektumot használunk túra-azonosító -> név lookupként.
  const tripNameById = useMemo(
    () =>
      Object.fromEntries(
        trips.map((trip) => [trip.id, trip.name || "Ismeretlen túra"]),
      ),
    [trips],
  );
  const fetchData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      // Az aktív településre szűrve (a hiányzó projectId az alapértelmezett).
      const [tripsSnapshot, stationsSnapshot] = await Promise.all([
        getDocs(collection(db, "trips")),
        getDocs(collection(db, "stations")),
      ]);
      const tripsData = filterByProject(
        tripsSnapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
        activeProjectId,
      );
      const stationsData = filterByProject(
        stationsSnapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
        activeProjectId,
      );

      const stationsWithCoords = stationsData
        .map((station) => {
          const coords = getStationCoords(station);
          if (!coords) return null;
          return { ...station, _coords: coords };
        })
        .filter(Boolean);

      setTrips(tripsData);
      setStations(stationsWithCoords);

      // Az útvonalak a térkép megjelenése UTÁN töltődnek, hogy az oldal ne
      // várjon a külső útvonal-szolgáltatásra. Ahol a túrához már el van
      // mentve az útvonal (a Túrák oldal menti), azt használjuk – ez azonnali
      // és a valódi turistaút, nem légvonal.
      // FIGYELEM: ebben a komponensben a `Map` név magát a komponenst jelenti,
      // ezért NEM használható a beépített `new Map()` – sima objektumot
      // használunk túra-azonosító szerint.
      const stationsByTrip = {};
      for (const trip of tripsData) {
        stationsByTrip[trip.id] = stationsForTrip(stationsWithCoords, trip.id);
      }

      const storedRoutes = {};
      const needsFetch = [];
      for (const trip of tripsData) {
        const tripStations = stationsByTrip[trip.id] ?? [];
        if (tripStations.length < 2) continue;

        const stored = getStoredRouteCoordinates(trip);
        if (stored.length > 1) {
          storedRoutes[trip.id] = {
            coords: stored,
            distanceMeters: 0,
            durationSeconds: 0,
            source: "stored",
            stations: tripStations,
          };
        } else {
          needsFetch.push({ trip, tripStations });
        }
      }
      setRouteData(storedRoutes);

      if (stationsWithCoords.length > 0) {
        const avgLat =
          stationsWithCoords.reduce((sum, s) => sum + s._coords[0], 0) /
          stationsWithCoords.length;
        const avgLng =
          stationsWithCoords.reduce((sum, s) => sum + s._coords[1], 0) /
          stationsWithCoords.length;
        setCenter({ lat: avgLat, lng: avgLng });
      } else {
        setCenter(DEFAULT_CENTER);
      }
      // A térkép már látszik – a hiányzó útvonalakat párhuzamosan töltjük.
      if (needsFetch.length > 0) {
        setRoutesLoading(true);
        const fetched = await Promise.all(
          needsFetch.map(async ({ trip, tripStations }) => {
            const result = await getRouteData(
              tripStations.map((st) => st._coords),
            );
            return [trip.id, { ...result, stations: tripStations }];
          }),
        );
        setRouteData((prev) => ({ ...prev, ...Object.fromEntries(fetched) }));
        setRoutesLoading(false);
      }
    } catch (err) {
      // A konkrét ok is látszik – néma catch mellett nehéz diagnosztizálni.
      setError(
        `Nem sikerült betölteni a térkép adatait: ${err?.message ?? err}`,
      );
    } finally {
      setLoading(false);
    }
  }, [activeProjectId]);

  useEffect(() => {
    const timer = setTimeout(() => {
      void fetchData();
    }, 0);

    return () => clearTimeout(timer);
  }, [fetchData]);

  // Jelmagyarázatra kattintva a térkép ráközelít/ráugrik az adott túra
  // útvonalára (vagy állomásaira, ha még nincs mentett/lekért útvonal), és
  // az útvonal vonala kiemelten (vastagabban) jelenik meg. Újra kattintva
  // az adott túrára a kiemelés törlődik.
  const handleSelectTrip = useCallback(
    (tripId) => {
      setSelectedTripId((prev) => (prev === tripId ? null : tripId));

      const route = routeData[tripId];
      const points =
        route?.coords?.length > 1
          ? route.coords.map(([lat, lng]) => ({ lat, lng }))
          : stationsForTrip(stations, tripId).map((s) => ({
              lat: s._coords[0],
              lng: s._coords[1],
            }));

      if (points.length === 0 || !mapRef.current || !window.google) return;

      const bounds = new window.google.maps.LatLngBounds();
      points.forEach((p) => bounds.extend(p));
      mapRef.current.fitBounds(bounds, 60);
    },
    [routeData, stations],
  );

  if (loading) {
    return (
      <div className="map-page">
        <div className="map-loading">
          <div className="spinner"></div>
          <p>Térkép betöltése...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="map-page">
        <div className="map-error">
          <h2>Hiba</h2>
          <p>{error}</p>
        </div>
      </div>
    );
  }

  if (loadError) {
    return (
      <div className="map-page">
        <div className="map-error">
          <h2>Google Maps Hiba</h2>
          <p>Ellenőrizd az API kulcsot.</p>
        </div>
      </div>
    );
  }

  if (!isLoaded) {
    return (
      <div className="map-page">
        <div className="map-loading">
          <div className="spinner"></div>
          <p>Google Maps betöltése...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="map-page">
      {stations.length === 0 ? (
        <div className="map-empty">
          <p>Még nincsenek állomások a térképen.</p>
        </div>
      ) : (
        <>
      {routesLoading && (
        <div className="map-routes-loading">Útvonalak betöltése…</div>
      )}
          <GoogleMap
            mapContainerStyle={MAP_CONTAINER_STYLE}
            center={center}
            zoom={13}
            onLoad={handleMapLoad}
            options={{
              streetViewControl: false,
              mapTypeControl: true,
              fullscreenControl: true,
              zoomControl: true,
            }}
          >
            {trips.map((trip, idx) => {
              const route = routeData[trip.id];
              if (!route || !route.coords || route.coords.length === 0)
                return null;

              const color = TRIP_COLORS[idx % TRIP_COLORS.length];
              const path = route.coords.map(([lat, lng]) => ({ lat, lng }));
              const isSelected = selectedTripId === trip.id;
              // Ha ki van választva egy túra a jelmagyarázatban, a többi
              // elhalványul, hogy a kiválasztott jól kiemelkedjen.
              const isDimmed = selectedTripId != null && !isSelected;

              return (
                <Polyline
                  key={trip.id}
                  path={path}
                  options={{
                    strokeColor: color,
                    strokeOpacity: isDimmed ? 0.25 : 0.9,
                    strokeWeight: isSelected ? 7 : 4,
                    geodesic: true,
                    zIndex: isSelected ? 999 : idx,
                  }}
                />
              );
            })}

            {stations.map((station) => (
              <Marker
                key={station.id}
                position={{ lat: station._coords[0], lng: station._coords[1] }}
                onClick={() => setSelectedStation(station)}
                title={station.name}
              />
            ))}

            {selectedStation && (
              <InfoWindow
                position={{
                  lat: selectedStation._coords[0],
                  lng: selectedStation._coords[1],
                }}
                onCloseClick={() => setSelectedStation(null)}
              >
                <div className="infowindow-content">
                  <strong style={{ fontSize: "1.1em" }}>
                    {selectedStation.name}
                  </strong>
                  <p style={{ margin: "5px 0", fontSize: "0.9em" }}>
                    {selectedStation.description}
                  </p>
                  <em style={{ fontSize: "0.85em", color: "#666" }}>
                    {(() => {
                      const names = stationTripIds(selectedStation)
                        .map((tid) => tripNameById[tid])
                        .filter(Boolean);
                      return names.length > 0
                        ? `Túra: ${names.join(", ")}`
                        : "Nincs túrához rendelve";
                    })()}
                  </em>
                </div>
              </InfoWindow>
            )}
          </GoogleMap>

          <div className="map-legend">
            <div className="legend-header">
              <h3>📍 Túraútvonalak</h3>
            </div>
            <div className="legend-items">
              {trips.map((trip, idx) => {
                const route = routeData[trip.id];
                const color = TRIP_COLORS[idx % TRIP_COLORS.length];
                const tripStationCount = stationsForTrip(stations, trip.id).length;
                const isSelected = selectedTripId === trip.id;

                return (
                  <div
                    key={trip.id}
                    className={`legend-item${isSelected ? " legend-item-active" : ""}`}
                    style={{ "--legend-accent": color }}
                    role="button"
                    tabIndex={0}
                    onClick={() => handleSelectTrip(trip.id)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter" || e.key === " ") {
                        e.preventDefault();
                        handleSelectTrip(trip.id);
                      }
                    }}
                    title="Kattints: ráközelítés és kiemelés a térképen"
                  >
                    <div
                      className="legend-color"
                      style={{ backgroundColor: color }}
                    ></div>
                    <div className="legend-info">
                      <div className="legend-name">{trip.name}</div>
                      <div className="legend-details">
                        {route && (
                          <>
                            <span className="detail-badge">
                              📏 {formatDistance(route.distanceMeters)}
                            </span>
                            <span className="detail-badge">
                              ⏱️ {formatDuration(route.durationSeconds)}
                            </span>
                          </>
                        )}
                        <span className="detail-badge">
                          📍 {tripStationCount} állomás
                        </span>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </>
      )}
    </div>
  );
}

export default Map;