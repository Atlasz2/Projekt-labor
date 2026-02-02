import React, { useState, useEffect } from 'react';
import { MapContainer, TileLayer, Marker, Popup, Polyline } from 'react-leaflet';
import { db } from '../firebaseConfig';
import { collection, getDocs } from 'firebase/firestore';
import 'leaflet/dist/leaflet.css';
import '../styles/Map.css';
import L from 'leaflet';

// Fix Leaflet default marker icons
delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
});

function Map() {
  const [stations, setStations] = useState([]);
  const [trips, setTrips] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [center, setCenter] = useState([47.0600, 17.7150]); // Nagyvázsony default

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      setLoading(true);
      setError(null);

      const stationsSnapshot = await getDocs(collection(db, 'stations'));
      const stationsData = stationsSnapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      })).filter(station => station.location); // Only stations with location

      const tripsSnapshot = await getDocs(collection(db, 'trips'));
      const tripsData = tripsSnapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      }));

      setStations(stationsData);
      setTrips(tripsData);

      // Calculate map center from stations
      if (stationsData.length > 0) {
        const avgLat = stationsData.reduce((sum, s) => sum + s.location.latitude, 0) / stationsData.length;
        const avgLng = stationsData.reduce((sum, s) => sum + s.location.longitude, 0) / stationsData.length;
        setCenter([avgLat, avgLng]);
      }
    } catch (err) {
      console.error('Hiba az adatok betöltésekor:', err);
      setError('Nem sikerült betölteni a térkép adatait');
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="map-page">
        <h1>Térkép</h1>
        <p>Betöltés...</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="map-page">
        <h1>Térkép</h1>
        <p className="error">{error}</p>
      </div>
    );
  }

  // Group stations by tripId for routes
  const routesByTrip = {};
  stations.forEach(station => {
    const tripId = station.tripId;
    if (!routesByTrip[tripId]) {
      routesByTrip[tripId] = [];
    }
    routesByTrip[tripId].push(station);
  });

  // Sort stations by orderIndex for each trip
  Object.keys(routesByTrip).forEach(tripId => {
    routesByTrip[tripId].sort((a, b) => (a.orderIndex || 0) - (b.orderIndex || 0));
  });

  return (
    <div className="map-page">
      <h1>Térkép</h1>

      {stations.length === 0 ? (
        <p>Még nincsenek állomások koordinátákkal az adatbázisban.</p>
      ) : (
        <div className="map-container">
          <MapContainer center={center} zoom={14} style={{ height: '600px', width: '100%' }}>
            <TileLayer
              attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
              url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
            />

            {/* Draw routes for each trip */}
            {Object.entries(routesByTrip).map(([tripId, tripStations], idx) => {
              const trip = trips.find(t => t.id === tripId);
              const color = ['#2E7D32', '#66BB6A', '#1B5E20', '#81C784'][idx % 4];
              const positions = tripStations.map(s => [s.location.latitude, s.location.longitude]);
              
              return positions.length > 1 ? (
                <Polyline 
                  key={tripId}
                  positions={positions}
                  color={color}
                  weight={3}
                  opacity={0.7}
                />
              ) : null;
            })}

            {/* Draw station markers */}
            {stations.map(station => (
              <Marker 
                key={station.id}
                position={[station.location.latitude, station.location.longitude]}
              >
                <Popup>
                  <strong>{station.name}</strong><br />
                  {station.description}<br />
                  <em>Állomás #{station.orderIndex || '?'}</em>
                </Popup>
              </Marker>
            ))}
          </MapContainer>

          <div className="map-legend">
            <h3>Jelmagyarázat</h3>
            {trips.map((trip, idx) => {
              const color = ['#2E7D32', '#66BB6A', '#1B5E20', '#81C784'][idx % 4];
              return (
                <div key={trip.id} className="legend-item">
                  <div className="legend-line" style={{ backgroundColor: color }}></div>
                  <span>{trip.name}</span>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

export default Map;
