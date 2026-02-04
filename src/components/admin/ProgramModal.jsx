import React, { useState, useEffect } from 'react';
import { Timestamp } from 'firebase/firestore';
import '../../styles/Modal.css';

export const ProgramModal = ({ program, onClose, onSave }) => {
  const [formData, setFormData] = useState({
    title: '',
    description: '',
    date: '',
    location: '',
    imageUrl: '',
    isActive: true
  });

  useEffect(() => {
    if (program) {
      const dateValue = program.date 
        ? new Date(program.date.seconds * 1000).toISOString().slice(0, 16)
        : '';

      setFormData({
        title: program.title || '',
        description: program.description || '',
        date: dateValue,
        location: program.location || '',
        imageUrl: program.imageUrl || '',
        isActive: program.isActive !== undefined ? program.isActive : true
      });
    }
  }, [program]);

  const handleSubmit = (e) => {
    e.preventDefault();
    
    const dataToSave = {
      ...formData,
      date: formData.date ? Timestamp.fromDate(new Date(formData.date)) : null
    };

    onSave(dataToSave);
  };

  return (
    <div className="modal-overlay">
      <div className="modal-dialog modal-large">
        <div className="modal-header">
          <h2>{program ? 'Program szerkesztése' : 'Új program létrehozása'}</h2>
          <button className="modal-close" onClick={onClose}>✕</button>
        </div>

        <form onSubmit={handleSubmit} className="modal-form">
          <div className="form-group">
            <label>Program címe *</label>
            <input
              type="text"
              value={formData.title}
              onChange={(e) => setFormData({ ...formData, title: e.target.value })}
              required
              placeholder="pl. Falunapok 2024"
            />
          </div>

          <div className="form-group">
            <label>Leírás *</label>
            <textarea
              value={formData.description}
              onChange={(e) => setFormData({ ...formData, description: e.target.value })}
              required
              rows={5}
              placeholder="Részletes leírás a programról..."
            />
          </div>

          <div className="form-row">
            <div className="form-group">
              <label>Dátum és időpont *</label>
              <input
                type="datetime-local"
                value={formData.date}
                onChange={(e) => setFormData({ ...formData, date: e.target.value })}
                required
              />
            </div>

            <div className="form-group">
              <label>Helyszín *</label>
              <input
                type="text"
                value={formData.location}
                onChange={(e) => setFormData({ ...formData, location: e.target.value })}
                required
                placeholder="pl. Faluház, Fő út 12."
              />
            </div>
          </div>

          <div className="form-group">
            <label>Kép URL</label>
            <input
              type="url"
              value={formData.imageUrl}
              onChange={(e) => setFormData({ ...formData, imageUrl: e.target.value })}
              placeholder="https://example.com/image.jpg"
            />
            {formData.imageUrl && (
              <div className="image-preview">
                <img src={formData.imageUrl} alt="Előnézet" />
              </div>
            )}
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
              {program ? 'Mentés' : 'Létrehozás'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
