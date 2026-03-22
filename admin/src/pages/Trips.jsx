import React, { useState, useEffect } from "react";
import { db } from "../firebaseConfig";
import {
  collection,
  getDocs,
  addDoc,
  updateDoc,
  deleteDoc,
  doc,
} from "firebase/firestore";
import {
  GoogleMap,
  Marker,
  Polyline,
  InfoWindow,
  useLoadScript,
} from "@react-google-maps/api";
import { jsPDF } from "jspdf";
import "../styles/Trips.css";
import ConfirmDialog from "../components/ConfirmDialog";
import Snackbar from "@mui/material/Snackbar";
import Alert from "@mui/material/Alert";

const DEFAULT_CENTER = { lat: 47.06, lng: 17.715 };

const formatDuration = (seconds) => {
  if (!seconds || seconds <= 0) return "N/A";
  const totalMinutes = Math.max(1, Math.round(seconds / 60));
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours > 0) return `${hours} ó ${minutes} p`;
  return `${minutes} p`;
};

const formatDistance = (meters) => {
  if (!meters || meters <= 0) return "N/A";
  const km = meters / 1000;
  return `${km.toFixed(1)} km`;
};

const normalizeCoordinatePair = (pair, reverse = false) => {
  if (!Array.isArray(pair) || pair.length < 2) return null;

  const first = Number(pair[0]);
  const second = Number(pair[1]);

  if (!Number.isFinite(first) || !Number.isFinite(second)) return null;

  return reverse ? [second, first] : [first, second];
};

const getStoredRouteCoordinates = (trip) => {
  const routeFields = [
    trip?.routeCoordinates,
    trip?.routePoints,
    trip?.path,
    trip?.waypoints,
  ];

  for (const field of routeFields) {
    if (!Array.isArray(field) || field.length === 0) continue;

    const coords = field
      .map((pair) => normalizeCoordinatePair(pair))
      .filter(Boolean);

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

const getDistanceValue = (distance) => {
  if (typeof distance === "number" && Number.isFinite(distance) && distance > 0) {
    return Number(distance.toFixed(1));
  }

  if (typeof distance === "string") {
    const parsed = Number.parseFloat(distance.replace(",", "."));
    if (Number.isFinite(parsed) && parsed > 0) {
      return Number(parsed.toFixed(1));
    }
  }

  return null;
};

const getDurationLabel = (duration) => {
  if (typeof duration === "string" && duration.trim()) {
    return duration.trim();
  }

  if (typeof duration === "number" && Number.isFinite(duration) && duration > 0) {
    return formatDuration(duration);
  }

  return null;
};

const getStoredTripMetrics = (trip, currentMetrics) => {
  const distanceValue =
    currentMetrics?.distanceValue ?? getDistanceValue(trip?.distance);
  const durationLabel =
    currentMetrics?.durationLabel ?? getDurationLabel(trip?.duration);

  if (distanceValue == null && !durationLabel) return null;

  return {
    ...(distanceValue != null
      ? {
          distanceValue,
          distanceLabel: `${distanceValue.toFixed(1)} km`,
        }
      : {}),
    ...(durationLabel ? { durationLabel } : {}),
  };
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

const getStationCoords = (station) => {
  const lat = station?.location?.latitude ?? station?.latitude;
  const lon = station?.location?.longitude ?? station?.longitude;
  return typeof lat === "number" && typeof lon === "number" ? [lat, lon] : null;
};

const getStationLatLng = (station) => {
  const lat = station?.location?.latitude ?? station?.latitude;
  const lon = station?.location?.longitude ?? station?.longitude;
  return typeof lat === "number" && typeof lon === "number" ? { lat, lng: lon } : null;
};

const getQrValue = (station) => station.qrCode || station.id;

const getQrImageUrl = (value, size = 120) => {
  const data = encodeURIComponent(value || "");
  return `https://api.qrserver.com/v1/create-qr-code/?size=${size}x${size}&data=${data}`;
};

const fetchDataUrl = async (url) => {
  const response = await fetch(url);
  const blob = await response.blob();
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.onloadend = () => resolve(reader.result);
    reader.readAsDataURL(blob);
  });
};

function TripMap({ center, routePath, stations, isLoaded, loadError }) {
  const [selectedStation, setSelectedStation] = useState(null);
  const path = routePath ? routePath.map(([lat, lng]) => ({ lat, lng })) : [];

  if (loadError) {
    return <div className="no-stations">Google Maps hiba. Ellenorizd az API kulcsot.</div>;
  }

  if (!isLoaded) {
    return <div className="no-stations">Terkep betoltese...</div>;
  }

  if (stations.length === 0) {
    return <div className="no-stations">Nincs meg allomas ehhez a turahoz</div>;
  }

  return (
    <GoogleMap
      mapContainerStyle={{ height: "350px", width: "100%" }}
      center={center}
      zoom={14}
      options={{
        streetViewControl: false,
        mapTypeControl: false,
        fullscreenControl: false,
      }}
    >
      {path.length > 0 && (
        <Polyline
          path={path}
          options={{
            strokeColor: "#4f8cff",
            strokeOpacity: 0.8,
            strokeWeight: 4,
          }}
        />
      )}
      {stations.map((station) => {
        const coords = getStationLatLng(station);
        if (!coords) return null;
        return (
          <Marker
            key={station.id}
            position={coords}
            onClick={() => setSelectedStation(station)}
          />
        );
      })}
      {selectedStation && (
        <InfoWindow
          position={getStationLatLng(selectedStation)}
          onCloseClick={() => setSelectedStation(null)}
        >
          <div>
            <strong>{selectedStation.name}</strong>
            <br />
            {selectedStation.description}
          </div>
        </InfoWindow>
      )}
    </GoogleMap>
  );
}

function Trips() {
  const [trips, setTrips] = useState([]);
  const [stations, setStations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [expandedTripId, setExpandedTripId] = useState(null);
  const [routeCoordinates, setRouteCoordinates] = useState({});
  const [tripMetrics, setTripMetrics] = useState({});
  const [routeSavingId, setRouteSavingId] = useState(null);
  const [deleteDialog, setDeleteDialog] = useState({ open: false, id: null });
  const [snack, setSnack] = useState({ open: false, msg: "", severity: "error" });
  const showMsg = (msg, severity = "error") => setSnack({ open: true, msg, severity });
  const [formData, setFormData] = useState({
    name: "",
    description: "",
    isActive: true,
  });

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
      setTrips(tripsData);

      const hydratedRoutes = {};
      const hydratedMetrics = {};

      tripsData.forEach((trip) => {
        const storedRoute = getStoredRouteCoordinates(trip);
        if (storedRoute.length > 0) {
          hydratedRoutes[trip.id] = storedRoute;
        }

        const storedMetrics = getStoredTripMetrics(trip);
        if (storedMetrics) {
          hydratedMetrics[trip.id] = storedMetrics;
        }
      });

      setRouteCoordinates(hydratedRoutes);
      setTripMetrics(hydratedMetrics);

      const stationsSnapshot = await getDocs(collection(db, "stations"));
      const stationsData = stationsSnapshot.docs.map((doc) => ({
        id: doc.id,
        ...doc.data(),
      }));
      setStations(stationsData);
    } catch (err) {
      setError("Hiba az adatok betolteseinel");
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const getTripsStations = (tripId) => {
    return stations
      .filter((s) => s.tripId === tripId)
      .sort((a, b) => (a.orderIndex || 0) - (b.orderIndex || 0));
  };

  const getMapCenter = (tripId) => {
    const tripStations = getTripsStations(tripId);
    const coords = tripStations.map(getStationCoords).filter(Boolean);
    if (coords.length === 0) return DEFAULT_CENTER;

    const avgLat = coords.reduce((sum, c) => sum + c[0], 0) / coords.length;
    const avgLon = coords.reduce((sum, c) => sum + c[1], 0) / coords.length;
    return { lat: avgLat, lng: avgLon };
  };

  const handleExpandTrip = async (tripId) => {
    if (expandedTripId !== tripId) {
      setExpandedTripId(tripId);

      const selectedTrip = trips.find((trip) => trip.id === tripId);
      const storedRoute = getStoredRouteCoordinates(selectedTrip);
      const storedMetrics = getStoredTripMetrics(selectedTrip, tripMetrics[tripId]);

      if (storedRoute.length > 0) {
        setRouteCoordinates((prev) => ({
          ...prev,
          [tripId]: storedRoute,
        }));

        if (storedMetrics) {
          setTripMetrics((prev) => ({
            ...prev,
            [tripId]: {
              ...prev[tripId],
              ...storedMetrics,
            },
          }));
        }

        return;
      }

      const tripStations = getTripsStations(tripId);
      const coords = tripStations.map(getStationCoords).filter(Boolean);

      if (!routeCoordinates[tripId] && coords.length > 1) {
        const routeData = await getRouteData(coords);
        setRouteCoordinates((prev) => ({ ...prev, [tripId]: routeData.coords }));

        if (routeData.distanceMeters > 0) {
          const distanceLabel = formatDistance(routeData.distanceMeters);
          const durationLabel = formatDuration(routeData.durationSeconds);
          setTripMetrics((prev) => ({
            ...prev,
            [tripId]: {
              distanceLabel,
              durationLabel,
              distanceValue: Number((routeData.distanceMeters / 1000).toFixed(1)),
            },
          }));
        }
      }
    } else {
      setExpandedTripId(null);
    }
  };

  const handleInputChange = (e) => {
    const { name, value, type, checked } = e.target;
    setFormData((prev) => ({
      ...prev,
      [name]: type === "checkbox" ? checked : value,
    }));
  };

  const handleToggleStatus = () => {
    setFormData((prev) => ({
      ...prev,
      isActive: !prev.isActive,
    }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    try {
      const payload = {
        name: formData.name,
        description: formData.description || "",
        isActive: !!formData.isActive,
      };

      if (editingId) {
        await updateDoc(doc(db, "trips", editingId), payload);
      } else {
        await addDoc(collection(db, "trips"), payload);
      }
      fetchData();
      handleCancel();
    } catch (err) {
      setError("Hiba a menteskor");
      console.error(err);
    }
  };

  const handleEdit = (trip) => {
    setEditingId(trip.id);
    setFormData({
      name: trip.name || "",
      description: trip.description || "",
      isActive: trip.isActive !== false,
    });
    setShowForm(true);
  };

  const handleDelete = (tripId) => {
    setDeleteDialog({ open: true, id: tripId });
  };

  const confirmDelete = async () => {
    if (!deleteDialog.id) return;
    try {
      await deleteDoc(doc(db, "trips", deleteDialog.id));
      setDeleteDialog({ open: false, id: null });
      fetchData();
    } catch (err) {
      setError("Hiba a torleskor");
      console.error(err);
      setDeleteDialog({ open: false, id: null });
    }
  };

  const handleCancel = () => {
    setShowForm(false);
    setEditingId(null);
    setFormData({
      name: "",
      description: "",
      isActive: true,
    });
  };

  const handleMoveStation = async (station, tripStations, idx, dir) => {
    const swapWith = tripStations[idx + dir];
    if (!swapWith) return;
    try {
      // First normalise every station in this trip to sequential orderIndex values
      // so we always work with clean integers, not nulls
      const normUpdates = tripStations.map((s, i) =>
        updateDoc(doc(db, "stations", s.id), { orderIndex: i })
      );
      await Promise.all(normUpdates);
      // Now swap the two target stations
      await Promise.all([
        updateDoc(doc(db, "stations", station.id), { orderIndex: idx + dir }),
        updateDoc(doc(db, "stations", swapWith.id), { orderIndex: idx }),
      ]);
      showMsg("Sorrend frissítve!", "success");
      await fetchData();
    } catch (err) {
      showMsg("Hiba a sorrend mentésekor");
      console.error(err);
    }
  };

  const handleSaveRoute = async (trip) => {
    try {
      setRouteSavingId(trip.id);

      const tripStations = getTripsStations(trip.id);
      const coords = tripStations.map(getStationCoords).filter(Boolean);

      let nextRoute = routeCoordinates[trip.id];
      let distanceValue =
        tripMetrics[trip.id]?.distanceValue ?? getDistanceValue(trip.distance);
      let durationLabel =
        tripMetrics[trip.id]?.durationLabel ?? getDurationLabel(trip.duration);

      if ((!nextRoute || nextRoute.length === 0) && coords.length < 2) {
        showMsg("Legalább két állomás szükséges az útvonal mentéséhez");
        return;
      }

      if (!nextRoute || nextRoute.length === 0) {
        const routeData = await getRouteData(coords);

        if (!routeData.coords.length) {
          showMsg("Nem sikerült útvonalat számolni a túrához");
          return;
        }

        nextRoute = routeData.coords;

        if (routeData.distanceMeters > 0) {
          distanceValue = Number((routeData.distanceMeters / 1000).toFixed(1));
        }

        if (routeData.durationSeconds > 0) {
          durationLabel = formatDuration(routeData.durationSeconds);
        }
      }

      const payload = {
        routeCoordinates: nextRoute,
        routeSource: "osrm-foot",
      };

      if (distanceValue != null) {
        payload.distance = Number(distanceValue.toFixed(1));
      }

      if (durationLabel) {
        payload.duration = durationLabel;
      }

      await updateDoc(doc(db, "trips", trip.id), payload);

      setRouteCoordinates((prev) => ({
        ...prev,
        [trip.id]: nextRoute,
      }));

      setTripMetrics((prev) => ({
        ...prev,
        [trip.id]: {
          ...prev[trip.id],
          ...(distanceValue != null
            ? {
                distanceValue: Number(distanceValue.toFixed(1)),
                distanceLabel: `${Number(distanceValue.toFixed(1)).toFixed(1)} km`,
              }
            : {}),
          ...(durationLabel ? { durationLabel } : {}),
        },
      }));

      setTrips((prev) =>
        prev.map((item) =>
          item.id === trip.id
            ? {
                ...item,
                ...payload,
              }
            : item
        )
      );

      showMsg("Útvonal sikeresen mentve!", "success");
    } catch (err) {
      console.error(err);
      showMsg("Hiba az útvonal mentésekor");
    } finally {
      setRouteSavingId(null);
    }
  };

  const handleDownloadPdf = async (station, tripName) => {
    try {
      const docPdf = new jsPDF({ unit: "mm", format: "a4" });
      const qrValue = getQrValue(station);
      const qrUrl = getQrImageUrl(qrValue, 220);
      const qrData = await fetchDataUrl(qrUrl);

      docPdf.setFont("helvetica", "bold");
      docPdf.setFontSize(18);
      docPdf.text(station.name || "Allomas", 20, 20);

      docPdf.setFont("helvetica", "normal");
      docPdf.setFontSize(12);
      if (tripName) {
        docPdf.text(`Tura: ${tripName}`, 20, 30);
      }

      docPdf.setFontSize(10);
      docPdf.text(`QR: ${qrValue}`, 20, tripName ? 40 : 30);
      docPdf.addImage(qrData, "PNG", 20, tripName ? 50 : 40, 70, 70);

      const fileName = `${(station.name || "allomas").replace(/\s+/g, "_")}_QR.pdf`;
      docPdf.save(fileName);
    } catch (error) {
      console.error("PDF letoltes hiba:", error);
      showMsg("Hiba a PDF letoltese kozben");
    }
  };

  if (loading)
    return (
      <div className="trips-shell">
        <p className="no-data">Betoltes...</p>
      </div>
    );

  return (
    <div className="trips-shell">
      <div className="trips-hero">
        <div className="hero-content">
          <div className="hero-copy">
            <p className="hero-kicker">Tura Studio</p>
            <h1>Turak Kezelése</h1>
            <p className="hero-subtitle">
              Útvonalak, állomások és tervezés egy helyen. Hozz létre, szerkessz és kezelj túraként könnyedén.
            </p>
          </div>
        </div>

        <div className="hero-stats">
          <div className="stat">
            <div className="stat-number">{trips.length}</div>
            <div className="stat-label">Túra</div>
          </div>
          <div className="stat">
            <div className="stat-number">{stations.length}</div>
            <div className="stat-label">Állomás</div>
          </div>
        </div>
      </div>

      {error && <div className="error-banner">{error}</div>}

      <div className="trips-main">
        {!showForm ? (
          <button className="btn-create-trip" onClick={() => setShowForm(true)}>
            <span className="btn-icon">+</span>
            <span className="btn-text">Új túra létrehozása</span>
          </button>
        ) : (
          <div className="form-wrapper">
            <div className="form-header">
              <h2>{editingId ? "Túra szerkesztése" : "Új túra hozzáadása"}</h2>
              <button className="btn-close" onClick={handleCancel}>×</button>
            </div>

            <form onSubmit={handleSubmit} className="beautiful-form">
              <div className="form-group">
                <label htmlFor="name">Túra neve *</label>
                <input
                  id="name"
                  type="text"
                  name="name"
                  value={formData.name}
                  onChange={handleInputChange}
                  placeholder="pl. Nagyvázsony felfedezése"
                  required
                />
              </div>

              <div className="form-group">
                <label htmlFor="description">Leírás</label>
                <textarea
                  id="description"
                  name="description"
                  value={formData.description}
                  onChange={handleInputChange}
                  placeholder="Túra leírása, érdekesség, információ..."
                  rows="4"
                />
              </div>

              <div className="form-group toggle-group">
                <label>Státusz</label>
                <button
                  type="button"
                  className={`status-toggle ${formData.isActive ? "active" : "inactive"}`}
                  onClick={handleToggleStatus}
                >
                  <span className="toggle-dot"></span>
                  <span className="toggle-text">
                    {formData.isActive ? "Aktív" : "Inaktív"}
                  </span>
                </button>
              </div>

              <p className="form-note">
                Az útvonal távolságát és időtartamát a rendszer automatikusan számítja az állomások alapján.
              </p>

              <div className="form-actions">
                <button type="submit" className="btn-submit">
                  {editingId ? "Frissítés" : "Létrehozás"}
                </button>
                <button
                  type="button"
                  className="btn-cancel"
                  onClick={handleCancel}
                >
                  Cancel
                </button>
              </div>
            </form>
          </div>
        )}

        {trips.length === 0 && !showForm ? (
          <div className="empty-state">
            <div className="empty-icon">🗺️</div>
            <h3>Még nincsenek túrák</h3>
            <p>Hozz létre az első túrádat, hogy elkezdhesd a kezelést!</p>
          </div>
        ) : (
          <div className="trips-list">
            {trips.map((trip) => {
              const tripStations = getTripsStations(trip.id);
              const isExpanded = expandedTripId === trip.id;
              const routePath = routeCoordinates[trip.id];
              const metrics = tripMetrics[trip.id];
              const distanceLabel =
                metrics?.distanceLabel ||
                (trip.distance ? `${trip.distance} km` : "–");
              const durationLabel =
                metrics?.durationLabel || trip.duration || "–";

              return (
                <div key={trip.id} className="trip-card">
                  <div
                    className="trip-header"
                    onClick={() => handleExpandTrip(trip.id)}
                  >
                    <div className="trip-title-section">
                      <button className="expand-toggle">
                        {isExpanded ? "▼" : "▶"}
                      </button>
                      <div className="trip-title-content">
                        <h3>{trip.name}</h3>
                        {trip.description && (
                          <p className="trip-desc-preview">{trip.description.substring(0, 80)}...</p>
                        )}
                      </div>
                    </div>

                    <div className="trip-meta-info">
                      <div className="meta-item">
                        <span className="meta-icon">📏</span>
                        <span className="meta-value">{distanceLabel}</span>
                      </div>
                      <div className="meta-item">
                        <span className="meta-icon">⏱️</span>
                        <span className="meta-value">{durationLabel}</span>
                      </div>
                      <div className="meta-item">
                        <span className="meta-icon">📍</span>
                        <span className="meta-value">{tripStations.length}</span>
                      </div>
                      <span
                        className={`trip-badge ${trip.isActive ? "badge-active" : "badge-inactive"}`}
                      >
                        {trip.isActive ? "Aktív" : "Inaktív"}
                      </span>
                    </div>
                  </div>

                  {isExpanded && (
                    <div className="trip-details">
                      <div className="details-map">
                        <TripMap
                          center={getMapCenter(trip.id)}
                          routePath={routePath}
                          stations={tripStations}
                          isLoaded={isLoaded}
                          loadError={loadError}
                        />
                        <div className="route-save-panel">
                          <button
                            className="btn-submit"
                            type="button"
                            onClick={() => handleSaveRoute(trip)}
                            disabled={routeSavingId === trip.id}
                          >
                            {routeSavingId === trip.id
                              ? "Útvonal mentése..."
                              : "Útvonal mentése a túrához"}
                          </button>
                          <p className="form-note">
                            A mobilalkalmazás először a mentett útvonalat használja.
                          </p>
                        </div>
                      </div>

                      <div className="details-stations">
                        <h4>📍 Állomások ({tripStations.length})</h4>
                        {tripStations.length > 0 ? (
                          <ul className="stations-list">
                            {tripStations.map((station, idx) => {
                              const qrValue = getQrValue(station);
                              const qrUrl = getQrImageUrl(qrValue);
                              return (
                                <li key={station.id} className="station-item">
                                  <div className="station-order-btns">
                                    <button
                                      className="btn-order"
                                      disabled={idx === 0}
                                      onClick={() => handleMoveStation(station, tripStations, idx, -1)}
                                      title="Feljebb"
                                    >▲</button>
                                    <button
                                      className="btn-order"
                                      disabled={idx === tripStations.length - 1}
                                      onClick={() => handleMoveStation(station, tripStations, idx, 1)}
                                      title="Lejjebb"
                                    >▼</button>
                                  </div>
                                  <div className="station-number">{idx + 1}</div>
                                  <div className="station-info">
                                    <strong>{station.name}</strong>
                                    <p>{station.description}</p>
                                  </div>
                                  <div className="station-qr">
                                    <img src={qrUrl} alt={`QR ${station.name}`} loading="lazy" />
                                    <button
                                      className="btn-qr-download"
                                      onClick={() => handleDownloadPdf(station, trip.name)}
                                    >
                                      Download
                                    </button>
                                  </div>
                                </li>
                              );
                            })}
                          </ul>
                        ) : (
                          <p className="empty-stations">
                            Nincsenek még állomások ezhez a túrához
                          </p>
                        )}
                      </div>
                    </div>
                  )}

                  <div className="trip-footer">
                    <button
                      className="btn-edit"
                      onClick={() => handleEdit(trip)}
                    >
                      ✏️ Szerkesztés
                    </button>
                    <button
                      className="btn-delete"
                      onClick={() => handleDelete(trip.id)}
                    >
                      🗑️ Törlés
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
      <Snackbar
        open={snack.open}
        autoHideDuration={4000}
        onClose={() => setSnack((s) => ({ ...s, open: false }))}
        anchorOrigin={{ vertical: "bottom", horizontal: "center" }}
      >
        <Alert severity={snack.severity} onClose={() => setSnack((s) => ({ ...s, open: false }))}>
          {snack.msg}
        </Alert>
      </Snackbar>
      <ConfirmDialog
        open={deleteDialog.open}
        title="Túra törlése"
        message="Biztosan torolni szeretned ezt a turat?"
        confirmText="Törlés"
        onClose={() => setDeleteDialog({ open: false, id: null })}
        onConfirm={confirmDelete}
      />
    </div>
  );
}

export default Trips;
