import React, { useState, useEffect } from 'react';
import '../../styles/Modal.css';

export const TripModal = ({ trip, onClose, onSave }) => {
  const [formData, setFormData] = useState({
    name: '',
    description: '',
    isActive: true
  });

  useEffect(() => {
    if (trip) {
      setFormData({
        name: trip.name || '',
        description: trip.description || '',
        isActive: trip.isActive !== undefined ? trip.isActive : true
      });
    }
  }, [trip]);

  const handleSubmit = (e) => {
    e.preventDefault();
    onSave(formData);
  };

  return (
    <div className="modal-overlay">
      <div className="modal-dialog">
        <div className="modal-header">
          <h2>Túra szerkesztése</h2>
          <button className="modal-close" onClick={onClose}>✕</button>
        </div>

        <form onSubmit={handleSubmit} className="modal-form">
          <div className="form-group">
            <label>Túra neve *</label>
            <input
              type="text"
              value={formData.name}
              onChange={(e) => setFormData({ ...formData, name: e.target.value })}
              required
              placeholder="pl. Budai hegyek túra"
            />
          </div>

          <div className="form-group">
            <label>Leírás *</label>
            <textarea
              value={formData.description}
              onChange={(e) => setFormData({ ...formData, description: e.target.value })}
              required
              rows={4}
              placeholder="Rövid leírás a túráról..."
            />
          </div>

          <div className="form-group">
            <label className="checkbox-label">
              <input
                type="checkbox"
                checked={formData.isActive}
                onChange={(e) => setFormData({ ...formData, isActive: e.target.checked })}
              />
              <span>Aktív (látható a felhasználóknak)</span>
            </label>
          </div>

          <div className="modal-actions">
            <button type="button" onClick={onClose} className="btn btn-secondary">
              Mégse
            </button>
            <button type="submit" className="btn btn-primary">
              Mentés
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
