import React, { useState, useEffect } from 'react';
import { db } from '../firebaseConfig';
import { collection, getDocs, addDoc, updateDoc, deleteDoc, doc } from 'firebase/firestore';
import { MapContainer, TileLayer, Marker, Popup, Polyline } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import '../styles/Trips.css';

// Fix Leaflet default marker icons
delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
});

function Trips() {
  const [trips, setTrips] = useState([]);
  const [stations, setStations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [expandedTripId, setExpandedTripId] = useState(null);
  const [formData, setFormData] = useState({
    name: '',
    description: '',
    distance: '',
    duration: '',
    difficulty: 'Könnyű',
    isActive: true
  });

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      setLoading(true);
      setError(null);
      
      const tripsSnapshot = await getDocs(collection(db, 'trips'));
      const tripsData = tripsSnapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      }));
      setTrips(tripsData);

      const stationsSnapshot = await getDocs(collection(db, 'stations'));
      const stationsData = stationsSnapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      }));
      setStations(stationsData);
    } catch (err) {
      console.error('Hiba az adatok betöltésekor:', err);
      setError('Nem sikerült betölteni az adatokat');
    } finally {
      setLoading(false);
    }
  };

  const getTripsStations = (tripId) => {
    return stations
      .filter(s => s.tripId === tripId)
      .sort((a, b) => (a.orderIndex || 0) - (b.orderIndex || 0));
  };

  const getMapCenter = (tripId) => {
    const tripStations = getTripsStations(tripId);
    if (tripStations.length === 0) return [47.0600, 17.7150];
    const avgLat = tripStations.reduce((sum, s) => sum + (s.location?.latitude || 0), 0) / tripStations.length;
    const avgLng = tripStations.reduce((sum, s) => sum + (s.location?.longitude || 0), 0) / tripStations.length;
    return [avgLat, avgLng];
  };

  const handleInputChange = (e) => {
    const { name, value, type, checked } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: type === 'checkbox' ? checked : value
    }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!formData.name || !formData.description) {
      alert('Kérlek töltsd ki az összes mezőt!');
      return;
    }

    try {
      if (editingId) {
        const tripRef = doc(db, 'trips', editingId);
        await updateDoc(tripRef, formData);
      } else {
        await addDoc(collection(db, 'trips'), formData);
      }
      
      setFormData({
        name: '',
        description: '',
        distance: '',
        duration: '',
        difficulty: 'Könnyű',
        isActive: true
      });
      setShowForm(false);
      setEditingId(null);
      fetchData();
    } catch (err) {
      console.error('Hiba a túra mentésekor:', err);
      alert('Nem sikerült menteni a túrát');
    }
  };

  const handleEdit = (trip) => {
    setFormData(trip);
    setEditingId(trip.id);
    setShowForm(true);
  };

  const handleDelete = async (tripId) => {
    if (!window.confirm('Biztosan törölni szeretnéd ezt a túrát?')) return;
    
    try {
      await deleteDoc(doc(db, 'trips', tripId));
      fetchData();
    } catch (err) {
      console.error('Hiba a túra törlésekor:', err);
      alert('Nem sikerült törölni a túrát');
    }
  };

  const handleCancel = () => {
    setShowForm(false);
    setEditingId(null);
    setFormData({
      name: '',
      description: '',
      distance: '',
      duration: '',
      difficulty: 'Könnyű',
      isActive: true
    });
  };

  if (loading) {
    return (
      <div className="trips">
        <h1>Túrák kezelése</h1>
        <p>Betöltés...</p>
      </div>
    );
  }

  return (
    <div className="trips">
      <div className="trips-header">
        <h1>Túrák kezelése</h1>
        {!showForm && (
          <button className="btn-primary" onClick={() => setShowForm(true)}>
            ➕ Új túra
          </button>
        )}
      </div>

      {error && <p className="error">{error}</p>}

      {showForm && (
        <div className="form-container">
          <h2>{editingId ? 'Túra szerkesztése' : 'Új túra hozzáadása'}</h2>
          <form onSubmit={handleSubmit}>
            <div className="form-group">
              <label>Túra neve *</label>
              <input
                type="text"
                name="name"
                value={formData.name}
                onChange={handleInputChange}
                placeholder="pl. Történelmi séta"
                required
              />
            </div>

            <div className="form-group">
              <label>Leírás *</label>
              <textarea
                name="description"
                value={formData.description}
                onChange={handleInputChange}
                placeholder="A túra részletes leírása"
                rows="4"
                required
              ></textarea>
            </div>

            <div className="form-row">
              <div className="form-group">
                <label>Távolság (km)</label>
                <input
                  type="number"
                  name="distance"
                  value={formData.distance}
                  onChange={handleInputChange}
                  placeholder="5.2"
                  step="0.1"
                />
              </div>

              <div className="form-group">
                <label>Időtartam</label>
                <input
                  type="text"
                  name="duration"
                  value={formData.duration}
                  onChange={handleInputChange}
                  placeholder="2 óra"
                />
              </div>

              <div className="form-group">
                <label>Nehézség</label>
                <select name="difficulty" value={formData.difficulty} onChange={handleInputChange}>
                  <option value="Könnyű">Könnyű</option>
                  <option value="Közepes">Közepes</option>
                  <option value="Nehéz">Nehéz</option>
                </select>
              </div>
            </div>

            <div className="form-group checkbox">
              <label>
                <input
                  type="checkbox"
                  name="isActive"
                  checked={formData.isActive}
                  onChange={handleInputChange}
                />
                Aktív túra
              </label>
            </div>

            <div className="form-actions">
              <button type="submit" className="btn-primary">
                {editingId ? 'Frissítés' : 'Hozzáadás'}
              </button>
              <button type="button" className="btn-secondary" onClick={handleCancel}>
                Mégse
              </button>
            </div>
          </form>
        </div>
      )}

      {trips.length === 0 ? (
        <p className="no-data">Még nincsenek túrák. Hozz létre egy újat!</p>
      ) : (
        <div className="trips-container">
          {trips.map(trip => {
            const tripStations = getTripsStations(trip.id);
            const isExpanded = expandedTripId === trip.id;
            
            return (
              <div key={trip.id} className="trip-container">
                <div className="trip-header-bar">
                  <div className="trip-info">
                    <button 
                      className="expand-btn"
                      onClick={() => setExpandedTripId(isExpanded ? null : trip.id)}
                    >
                      {isExpanded ? '▼' : '▶'}
                    </button>
                    <div>
                      <h3>{trip.name}</h3>
                      <p className="trip-meta">
                        📏 {trip.distance || 'N/A'} km | ⏱️ {trip.duration || 'N/A'} | 🏔️ {trip.difficulty || 'N/A'}
                      </p>
                    </div>
                  </div>
                  <div className="trip-status-badge">
                    {trip.isActive ? '🟢 Aktív' : '🔴 Inaktív'}
                  </div>
                </div>

                <p className="trip-description">{trip.description}</p>

                {isExpanded && (
                  <div className="trip-expanded">
                    <div className="trip-map-container">
                      {tripStations.length > 0 ? (
                        <MapContainer 
                          center={getMapCenter(trip.id)} 
                          zoom={14} 
                          style={{ height: '350px', width: '100%', borderRadius: '8px' }}
                        >
                          <TileLayer
                            attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
                            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                          />
                          {tripStations.length > 1 && (
                            <Polyline
                              positions={tripStations.map(s => [s.location.latitude, s.location.longitude])}
                              color="#2E7D32"
                              weight={3}
                              opacity={0.7}
                            />
                          )}
                          {tripStations.map((station, idx) => (
                            <Marker 
                              key={station.id}
                              position={[station.location.latitude, station.location.longitude]}
                            >
                              <Popup>
                                <strong>#{idx + 1} {station.name}</strong><br />
                                {station.description}
                              </Popup>
                            </Marker>
                          ))}
                        </MapContainer>
                      ) : (
                        <div className="no-stations">Nincs még állomás ehhez a túrához</div>
                      )}
                    </div>

                    <div className="trip-stations">
                      <h4>Állomások ({tripStations.length})</h4>
                      {tripStations.length > 0 ? (
                        <ul className="stations-list">
                          {tripStations.map((station, idx) => (
                            <li key={station.id} className="station-item">
                              <span className="station-number">#{idx + 1}</span>
                              <div>
                                <strong>{station.name}</strong>
                                <p>{station.description}</p>
                                {station.qrCode && <span className="qr-badge">📱 {station.qrCode}</span>}
                              </div>
                            </li>
                          ))}
                        </ul>
                      ) : (
                        <p className="empty-stations">Nincs még állomás</p>
                      )}
                    </div>
                  </div>
                )}

                <div className="trip-actions">
                  <button className="btn-edit" onClick={() => handleEdit(trip)}>
                    ✏️ Szerkesztés
                  </button>
                  <button className="btn-delete" onClick={() => handleDelete(trip.id)}>
                    🗑️ Törlés
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

export default Trips;
