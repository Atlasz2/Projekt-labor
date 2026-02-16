import React, { useState, useEffect } from "react";
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

const DEFAULT_CENTER = { lat: 47.06, lng: 17.715 };
const MAP_CONTAINER_STYLE = { height: "100vh", width: "100%" };

const TRIP_COLORS = [
  "#FF6B6B",
  "#4ECDC4",
  "#45B7D1",
  "#FFA07A",
  "#98D8C8",
  "#F7DC6F",
  "#BB8FCE",
  "#85C1E2",
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

const getRouteData = async (coordinates) => {
  if (coordinates.length < 2) {
    return { coords: [], distanceMeters: 0, durationSeconds: 0 };
  }

  try {
    const osmCoords = coordinates.map(([lat, lon]) => `${lon},${lat}`).join(";");
    const osrmUrl = `https://router.project-osrm.org/route/v1/foot/${osmCoords}?geometries=geojson`;

    const response = await fetch(osrmUrl);
    const data = await response.json();

    if (data.code === "Ok" && data.routes && data.routes.length > 0) {
      const route = data.routes[0];
      const distanceMeters = route.distance || 0;
      const durationSeconds = route.duration || 0;

      if (
        route.geometry &&
        route.geometry.coordinates &&
        route.geometry.coordinates.length > 0
      ) {
        const coords = route.geometry.coordinates.map(([lon, lat]) => [lat, lon]);
        return { coords, distanceMeters, durationSeconds };
      }
    }
  } catch (error) {
    console.error("Route error:", error);
  }

  return { coords: [], distanceMeters: 0, durationSeconds: 0 };
};

const formatDistance = (meters) => {
  if (!meters || meters <= 0) return "N/A";
  const km = meters / 1000;
  return `${km.toFixed(1)} km`;
};

const formatDuration = (seconds) => {
  if (!seconds || seconds <= 0) return "N/A";
  const totalMinutes = Math.max(1, Math.round(seconds / 60));
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours > 0) return `${hours} ó ${minutes} p`;
  return `${minutes} p`;
};

function Map() {
  const [stations, setStations] = useState([]);
  const [trips, setTrips] = useState([]);
  const [routeData, setRouteData] = useState({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [center, setCenter] = useState(DEFAULT_CENTER);
  const [selectedStation, setSelectedStation] = useState(null);

  const { isLoaded, loadError } = useLoadScript({
    googleMapsApiKey: import.meta.env.VITE_GOOGLE_MAPS_API_KEY,
  });

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      setLoading(true);
      setError(null);

      const tripsSnapshot = await getDocs(collection(db, "trips"));
      const tripsData = tripsSnapshot.docs.map((doc) => ({
        id: doc.id,
        ...doc.data(),
      }));

      const stationsSnapshot = await getDocs(collection(db, "stations"));
      const stationsData = stationsSnapshot.docs.map((doc) => ({
        id: doc.id,
        ...doc.data(),
      }));

      const stationsWithCoords = stationsData
        .map((station) => {
          const coords = getStationCoords(station);
          if (!coords) return null;
          return { ...station, _coords: coords };
        })
        .filter(Boolean);

      setTrips(tripsData);
      setStations(stationsWithCoords);

      // Fetch routes for all trips
      const routes = {};
      for (const trip of tripsData) {
        const tripStations = stationsWithCoords
          .filter((s) => s.tripId === trip.id)
          .sort((a, b) => (a.orderIndex || 0) - (b.orderIndex || 0));

        if (tripStations.length > 1) {
          const coords = tripStations.map((s) => s._coords);
          const routeResult = await getRouteData(coords);
          routes[trip.id] = {
            ...routeResult,
            stations: tripStations,
          };
        }
      }

      setRouteData(routes);

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
    } catch (err) {
      console.error("Hiba az adatok betöltésekor:", err);
      setError("Nem sikerült betölteni a térkép adatait");
    } finally {
      setLoading(false);
    }
  };

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
          <GoogleMap
            mapContainerStyle={MAP_CONTAINER_STYLE}
            center={center}
            zoom={13}
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

              return (
                <Polyline
                  key={trip.id}
                  path={path}
                  options={{
                    strokeColor: color,
                    strokeOpacity: 0.85,
                    strokeWeight: 4,
                    geodesic: true,
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
                    Állomás #{selectedStation.orderIndex || "?"}
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
                const tripStationCount =
                  stations.filter((s) => s.tripId === trip.id).length || 0;

                return (
                  <div key={trip.id} className="legend-item">
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
