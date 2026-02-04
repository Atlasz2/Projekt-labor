import React, { useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { doc, getDoc, collection, query, where, getDocs, orderBy } from 'firebase/firestore';
import { db } from '../firebase';
import { MapContainer, TileLayer, Marker, Popup, Polyline } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import L from 'leaflet';
import { Toast } from '../components/Toast';
import { Skeleton } from '../components/Skeleton';
import '../styles/TrailDetailsPage.css';

// Fix Leaflet default marker icons
delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
});

// Custom marker icons
const defaultIcon = new L.Icon({
  iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
  iconSize: [25, 41],
  iconAnchor: [12, 41],
  popupAnchor: [1, -34],
  shadowSize: [41, 41]
});

const completedIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-green.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
  iconSize: [25, 41],
  iconAnchor: [12, 41],
  popupAnchor: [1, -34],
  shadowSize: [41, 41]
});

export default function TrailDetailsPage() {
  const { id } = useParams();
  const navigate = useNavigate();
  const [trail, setTrail] = useState(null);
  const [stations, setStations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [toast, setToast] = useState(null);
  const [mapCenter, setMapCenter] = useState([47.0982, 19.0402]); // Default: Hungary

  useEffect(() => {
    const fetchData = async () => {
      try {
        setLoading(true);
        
        // Túra betöltése
        const trailDoc = await getDoc(doc(db, 'trips', id));
        if (!trailDoc.exists()) {
          setToast({ type: 'error', message: 'Túra nem található' });
          setTimeout(() => navigate('/'), 2000);
          return;
        }
        
        const trailData = { id: trailDoc.id, ...trailDoc.data() };
        setTrail(trailData);

        // Állomások betöltése - EGYSZERŰ getDocs, NINCS where/orderBy
        const stationsSnapshot = await getDocs(collection(db, 'stations'));
        
        // Manuális szűrés és rendezés JavaScriptben
        const stationsData = stationsSnapshot.docs
          .map(doc => ({
            id: doc.id,
            ...doc.data()
          }))
          .filter(s => s.tripId === id) // Szűrés tripId szerint
          .sort((a, b) => a.orderIndex - b.orderIndex); // Rendezés orderIndex szerint

        console.log('✅ Állomások betöltve és szűrve:', stationsData.length);
        setStations(stationsData);

        // Térkép középpont beállítása az első állomásra
        if (stationsData.length > 0 && stationsData[0].location) {
          const firstLocation = stationsData[0].location;
          setMapCenter([
            firstLocation._lat || firstLocation.latitude,
            firstLocation._long || firstLocation.longitude
          ]);
        }

      } catch (error) {
        console.error('Hiba az adatok betöltésekor:', error);
        setToast({ type: 'error', message: 'Hiba az adatok betöltésekor' });
      } finally {
        setLoading(false);
      }
    };

    fetchData();
  }, [id, navigate]);

  if (loading) {
    return (
      <div className="trail-details">
        <Skeleton type="hero" />
        <div className="container">
          <Skeleton type="card" />
        </div>
      </div>
    );
  }

  if (!trail) return null;

  // Útvonal vonal koordinátái (állomások között)
  const routePath = stations
    .filter(s => s.location)
    .map(s => [
      s.location._lat || s.location.latitude,
      s.location._long || s.location.longitude
    ]);

  return (
    <div className="trail-details">
      {/* HEADER */}
      <div className="trail-header-simple">
        <button className="back-btn" onClick={() => navigate('/')}>
          ← Vissza
        </button>
        <h1>{trail.name}</h1>
        <p>{trail.description}</p>
      </div>

      <div className="container">
        {/* TÉRKÉP */}
        <div className="map-section">
          <h2>🗺️ Térkép és állomások</h2>
          <div className="map-container">
            <MapContainer
              center={mapCenter}
              zoom={14}
              style={{ height: '500px', width: '100%', borderRadius: '12px' }}
            >
              <TileLayer
                url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
              />

              {/* Útvonal vonal */}
              {routePath.length > 1 && (
                <Polyline
                  positions={routePath}
                  color="#667eea"
                  weight={4}
                  opacity={0.7}
                />
              )}

              {/* Állomás marker-ek */}
              {stations.map((station, index) => {
                if (!station.location) return null;
                
                const lat = station.location._lat || station.location.latitude;
                const lng = station.location._long || station.location.longitude;
                
                return (
                  <Marker
                    key={station.id}
                    position={[lat, lng]}
                    icon={defaultIcon}
                  >
                    <Popup>
                      <div className="marker-popup">
                        <h3>#{station.orderIndex} - {station.name}</h3>
                        <p>{station.description}</p>
                        {station.qrCode && (
                          <p className="qr-info">🔲 QR kód: {station.qrCode}</p>
                        )}
                      </div>
                    </Popup>
                  </Marker>
                );
              })}
            </MapContainer>
          </div>
        </div>

        {/* ÁLLOMÁSOK LISTA */}
        <div className="stations-list-section">
          <h2>📍 Állomások ({stations.length})</h2>
          
          {stations.length === 0 ? (
            <p className="no-stations">Ehhez a túrához még nincsenek állomások.</p>
          ) : (
            <div className="stations-list-simple">
              {stations.map((station) => (
                <div key={station.id} className="station-card-simple">
                  <div className="station-number">#{station.orderIndex}</div>
                  <div className="station-content-simple">
                    <h3>{station.name}</h3>
                    <p>{station.description}</p>
                    {station.location && (
                      <div className="station-coords">
                        📍 {(station.location._lat || station.location.latitude)?.toFixed(6)}, {(station.location._long || station.location.longitude)?.toFixed(6)}
                      </div>
                    )}
                    {station.qrCode && (
                      <div className="station-qr">
                        🔲 QR kód: <strong>{station.qrCode}</strong>
                      </div>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {toast && (
        <Toast
          type={toast.type}
          message={toast.message}
          onClose={() => setToast(null)}
        />
      )}
    </div>
  );
}
