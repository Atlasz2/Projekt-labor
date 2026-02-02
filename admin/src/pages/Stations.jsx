import React, { useState, useEffect } from 'react';
import { db } from '../firebaseConfig';
import { collection, getDocs, addDoc, updateDoc, deleteDoc, doc, GeoPoint } from 'firebase/firestore';
import { MapContainer, TileLayer, Marker, Popup, useMapEvents } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import '../styles/Stations.css';

// Fix Leaflet default marker icons
delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
});

function MapClickHandler({ onLocationSelect }) {
  useMapEvents({
    click(e) {
      onLocationSelect(e.latlng.lat, e.latlng.lng);
    },
  });
  return null;
}

function Stations() {
  const [stations, setStations] = useState([]);
  const [trips, setTrips] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [mapCenter, setMapCenter] = useState([47.0600, 17.7150]); // Nagyvázsony default
  const [formData, setFormData] = useState({
    name: '',
    description: '',
    tripId: '',
    orderIndex: '',
    qrCode: '',
    latitude: '',
    longitude: ''
  });

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
      }));
      setStations(stationsData);

      const tripsSnapshot = await getDocs(collection(db, 'trips'));
      const tripsData = tripsSnapshot.docs.map(doc => ({
        id: doc.id,
        name: doc.data().name
      }));
      setTrips(tripsData);
    } catch (err) {
      console.error('Hiba az adatok betöltésekor:', err);
      setError('Nem sikerült betölteni az adatokat');
    } finally {
      setLoading(false);
    }
  };

  const handleInputChange = (e) => {
    const { name, value } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: value
    }));
  };

  const handleLocationSelect = (lat, lng) => {
    setFormData(prev => ({
      ...prev,
      latitude: lat.toFixed(6),
      longitude: lng.toFixed(6)
    }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!formData.name || !formData.tripId || !formData.latitude || !formData.longitude) {
      alert('Kérlek töltsd ki az összes kötelező mezőt!');
      return;
    }

    try {
      const stationData = {
        name: formData.name,
        description: formData.description,
        tripId: formData.tripId,
        orderIndex: parseInt(formData.orderIndex) || 0,
        qrCode: formData.qrCode,
        location: new GeoPoint(parseFloat(formData.latitude), parseFloat(formData.longitude))
      };

      if (editingId) {
        const stationRef = doc(db, 'stations', editingId);
        await updateDoc(stationRef, stationData);
      } else {
        await addDoc(collection(db, 'stations'), stationData);
      }

      setFormData({
        name: '',
        description: '',
        tripId: '',
        orderIndex: '',
        qrCode: '',
        latitude: '',
        longitude: ''
      });
      setShowForm(false);
      setEditingId(null);
      fetchData();
    } catch (err) {
      console.error('Hiba az állomás mentésekor:', err);
      alert('Nem sikerült menteni az állomást');
    }
  };

  const handleEdit = (station) => {
    setFormData({
      name: station.name,
      description: station.description,
      tripId: station.tripId,
      orderIndex: station.orderIndex || '',
      qrCode: station.qrCode,
      latitude: station.location?.latitude || '',
      longitude: station.location?.longitude || ''
    });
    setEditingId(station.id);
    setShowForm(true);
    if (station.location) {
      setMapCenter([station.location.latitude, station.location.longitude]);
    }
  };

  const handleDelete = async (stationId) => {
    if (!window.confirm('Biztosan törölni szeretnéd ezt az állomást?')) return;
    
    try {
      await deleteDoc(doc(db, 'stations', stationId));
      fetchData();
    } catch (err) {
      console.error('Hiba az állomás törlésekor:', err);
      alert('Nem sikerült törölni az állomást');
    }
  };

  const handleCancel = () => {
    setShowForm(false);
    setEditingId(null);
    setFormData({
      name: '',
      description: '',
      tripId: '',
      orderIndex: '',
      qrCode: '',
      latitude: '',
      longitude: ''
    });
    setMapCenter([47.0600, 17.7150]);
  };

  if (loading) {
    return (
      <div className="stations">
        <h1>Állomások kezelése</h1>
        <p>Betöltés...</p>
      </div>
    );
  }

  return (
    <div className="stations">
      <div className="stations-header">
        <h1>Állomások kezelése</h1>
        {!showForm && (
          <button className="btn-primary" onClick={() => setShowForm(true)}>
            ➕ Új állomás
          </button>
        )}
      </div>

      {error && <p className="error">{error}</p>}

      {showForm && (
        <div className="form-container">
          <h2>{editingId ? 'Állomás szerkesztése' : 'Új állomás hozzáadása'}</h2>
          <form onSubmit={handleSubmit}>
            <div className="form-row">
              <div className="form-section">
                <div className="form-group">
                  <label>Állomás neve *</label>
                  <input
                    type="text"
                    name="name"
                    value={formData.name}
                    onChange={handleInputChange}
                    placeholder="pl. Kinizsi Vár"
                    required
                  />
                </div>

                <div className="form-group">
                  <label>Leírás</label>
                  <textarea
                    name="description"
                    value={formData.description}
                    onChange={handleInputChange}
                    placeholder="Az állomás leírása"
                    rows="3"
                  ></textarea>
                </div>

                <div className="form-group">
                  <label>Túra *</label>
                  <select name="tripId" value={formData.tripId} onChange={handleInputChange} required>
                    <option value="">-- Válassz túrát --</option>
                    {trips.map(trip => (
                      <option key={trip.id} value={trip.id}>{trip.name}</option>
                    ))}
                  </select>
                </div>

                <div className="form-group">
                  <label>Sorrend</label>
                  <input
                    type="number"
                    name="orderIndex"
                    value={formData.orderIndex}
                    onChange={handleInputChange}
                    placeholder="1"
                  />
                </div>

                <div className="form-group">
                  <label>QR kód</label>
                  <input
                    type="text"
                    name="qrCode"
                    value={formData.qrCode}
                    onChange={handleInputChange}
                    placeholder="QR_VAR_001"
                  />
                </div>

                <div className="form-group coordinates">
                  <label>Koordináták *</label>
                  <div className="coord-inputs">
                    <input
                      type="number"
                      name="latitude"
                      value={formData.latitude}
                      onChange={handleInputChange}
                      placeholder="Szélesség"
                      step="0.0001"
                      required
                    />
                    <input
                      type="number"
                      name="longitude"
                      value={formData.longitude}
                      onChange={handleInputChange}
                      placeholder="Hosszúság"
                      step="0.0001"
                      required
                    />
                  </div>
                  <p className="hint">💡 Vagy kattints a térképre a pont kijelöléséhez</p>
                </div>
              </div>

              <div className="form-map">
                <label>Pont kijelölés a térképről</label>
                <MapContainer 
                  center={mapCenter} 
                  zoom={15} 
                  style={{ height: '400px', width: '100%', borderRadius: '8px' }}
                >
                  <TileLayer
                    attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
                    url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                  />
                  {formData.latitude && formData.longitude && (
                    <Marker position={[parseFloat(formData.latitude), parseFloat(formData.longitude)]}>
                      <Popup>
                        <strong>{formData.name || 'Új állomás'}</strong><br />
                        Lat: {formData.latitude}<br />
                        Lng: {formData.longitude}
                      </Popup>
                    </Marker>
                  )}
                  <MapClickHandler onLocationSelect={handleLocationSelect} />
                </MapContainer>
              </div>
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

      {stations.length === 0 ? (
        <p className="no-data">Még nincsenek állomások. Hozz létre egy újat!</p>
      ) : (
        <div className="stations-table">
          <table>
            <thead>
              <tr>
                <th>Név</th>
                <th>Túra</th>
                <th>Sorrend</th>
                <th>QR kód</th>
                <th>Koordináták</th>
                <th>Műveletek</th>
              </tr>
            </thead>
            <tbody>
              {stations.map(station => {
                const trip = trips.find(t => t.id === station.tripId);
                return (
                  <tr key={station.id}>
                    <td><strong>{station.name}</strong></td>
                    <td>{trip?.name || 'N/A'}</td>
                    <td>#{station.orderIndex || '-'}</td>
                    <td>{station.qrCode || '-'}</td>
                    <td>
                      {station.location ? 
                        `${station.location.latitude.toFixed(4)}, ${station.location.longitude.toFixed(4)}` 
                        : 'N/A'
                      }
                    </td>
                    <td className="actions">
                      <button className="btn-edit" onClick={() => handleEdit(station)}>
                        ✏️
                      </button>
                      <button className="btn-delete" onClick={() => handleDelete(station.id)}>
                        🗑️
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

export default Stations;
