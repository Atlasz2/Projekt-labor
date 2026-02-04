import React, { useState, useEffect } from 'react';
import '../../styles/Modal.css';

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
              placeholder="pl. Kilátópont"
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

          <div className="form-row">
            <div className="form-group">
              <label>Szélesség (latitude) *</label>
              <input
                type="number"
                step="0.000001"
                value={formData.latitude}
                onChange={(e) => setFormData({ ...formData, latitude: e.target.value })}
                required
                placeholder="47.497912"
              />
            </div>

            <div className="form-group">
              <label>Hosszúság (longitude) *</label>
              <input
                type="number"
                step="0.000001"
                value={formData.longitude}
                onChange={(e) => setFormData({ ...formData, longitude: e.target.value })}
                required
                placeholder="19.040235"
              />
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

          <div className="map-preview">
            <p className="text-muted">
              📍 Térkép előnézet: 
              {formData.latitude && formData.longitude ? (
                <a
                  href={`https://www.google.com/maps?q=${formData.latitude},${formData.longitude}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="map-link"
                >
                  Megnyitás térképen →
                </a>
              ) : ' Add meg a koordinátákat'}
            </p>
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
