import React, { useState, useEffect } from 'react';
import { MapContainer, TileLayer, Marker, Popup, useMapEvents } from 'react-leaflet';
import L from 'leaflet';
import '../../styles/Modal.css';
import '../../styles/StationMapModal.css';

export const StationModal = ({ station, trips, onClose, onSave }) => {
  const [formData, setFormData] = useState({
    name: '',
    description: '',
    latitude: '',
    longitude: '',
    orderIndex: 1,
    qrCode: '',
    tripId: ''
  });
  const [showMap, setShowMap] = useState(false);
  const [mapCenter] = useState([46.9792, 17.6604]); // Nagyvázsony koordinátái

  useEffect(() => {
    if (station) {
      setFormData({
        name: station.name || '',
        description: station.description || '',
        latitude: station.location?._lat || station.location?.latitude || '',
        longitude: station.location?._long || station.location?.longitude || '',
        orderIndex: station.orderIndex || 1,
        qrCode: station.qrCode || '',
        tripId: station.tripId || ''
      });
    }
  }, [station]);

  const handleSubmit = (e) => {
    e.preventDefault();
    onSave(formData);
  };

  return (
    <div className="modal-overlay">
      <div className="modal-dialog modal-large">
        <div className="modal-header">
          <h2>{station ? 'Állomás szerkesztése' : 'Új állomás létrehozása'}</h2>
          <button className="modal-close" onClick={onClose}>✕</button>
        </div>

        <form onSubmit={handleSubmit} className="modal-form">
          <div className="form-group">
            <label>Állomás neve *</label>
            <input
              type="text"
              value={formData.name}
              onChange={(e) => setFormData({ ...formData, name: e.target.value })}
              required
              placeholder="pl. Kinizsi vár"
            />
          </div>

          <div className="form-group">
            <label>Leírás *</label>
            <textarea
              value={formData.description}
              onChange={(e) => setFormData({ ...formData, description: e.target.value })}
              required
              rows={5}
              placeholder="Részletes leírás az állomásról..."
            />
          </div>

          <div className="form-group">
            <label>Túra *</label>
            <select
              value={formData.tripId}
              onChange={(e) => setFormData({ ...formData, tripId: e.target.value })}
              required
            >
              <option value="">Válassz túrát</option>
              {trips.map(trip => (
                <option key={trip.id} value={trip.id}>{trip.name}</option>
              ))}
            </select>
          </div>

          {/* Térkép - mindig látható */}
          <div className="form-group">
            <label>📍 Hely kiválasztása a térképen *</label>
            <div className="map-selector-always">
              <MapContainer 
                center={mapCenter} 
                zoom={13} 
                style={{ height: '450px', width: '100%' }}
              >
                <TileLayer
                  url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                  attribution='&copy; OpenStreetMap contributors'
                />
                <MapClickHandler 
                  onMapClick={(lat, lng) => {
                    setFormData({ 
                      ...formData, 
                      latitude: lat.toFixed(6), 
                      longitude: lng.toFixed(6) 
                    });
                  }} 
                />
                {formData.latitude && formData.longitude && (
                  <Marker position={[parseFloat(formData.latitude), parseFloat(formData.longitude)]}>
                    <Popup>
                      <div>
                        <strong>Kiválasztott hely</strong><br />
                        Lat: {formData.latitude}<br />
                        Lng: {formData.longitude}
                      </div>
                    </Popup>
                  </Marker>
                )}
              </MapContainer>
              <p className="map-hint">💡 Kattints a térképre a hely kiválasztásához</p>
              {formData.latitude && formData.longitude && (
                <div className="coords-badge">
                  ✅ Hely kiválasztva: {formData.latitude}, {formData.longitude}
                </div>
              )}
            </div>
          </div>

          <div className="form-row">
            <div className="form-group">
              <label>Sorrend *</label>
              <input
                type="number"
                min="1"
                value={formData.orderIndex}
                onChange={(e) => setFormData({ ...formData, orderIndex: e.target.value })}
                required
              />
            </div>

            <div className="form-group">
              <label>QR kód azonosító</label>
              <input
                type="text"
                value={formData.qrCode}
                onChange={(e) => setFormData({ ...formData, qrCode: e.target.value })}
                placeholder="qr-station-01"
              />
            </div>
          </div>

          <div className="modal-actions">
            <button type="button" onClick={onClose} className="btn btn-secondary">
              Mégse
            </button>
            <button type="submit" className="btn btn-primary">
              {station ? 'Mentés' : 'Létrehozás'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

// Helper komponens térképkattintáshoz
function MapClickHandler({ onMapClick }) {
  useMapEvents({
    click(e) {
      onMapClick(e.latlng.lat, e.latlng.lng);
    },
  });
  return null;
}
