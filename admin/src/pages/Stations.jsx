import React, { useState, useEffect } from 'react';
import { db, storage } from '../firebaseConfig';
import { collection, getDocs, updateDoc, deleteDoc, doc, addDoc } from 'firebase/firestore';
import { ref, uploadBytes, getDownloadURL } from 'firebase/storage';
import { GoogleMap, Marker, useLoadScript } from '@react-google-maps/api';
import { jsPDF } from 'jspdf';
import '../styles/Stations.css';

const DEFAULT_CENTER = { lat: 47.06, lng: 17.715 };
const MAP_CONTAINER_STYLE = { height: '220px', width: '100%' };

const getQrValue = (station) => station.qrCode || station.id;

const getQrImageUrl = (value, size = 140) => {
  const data = encodeURIComponent(value || '');
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

function MapPicker({ value, onChange }) {
  const markerPosition = value?.lat != null && value?.lon != null
    ? { lat: value.lat, lng: value.lon }
    : null;
  const center = markerPosition || DEFAULT_CENTER;

  return (
    <GoogleMap
      mapContainerStyle={MAP_CONTAINER_STYLE}
      center={center}
      zoom={13}
      onClick={(e) => {
        if (!e.latLng) return;
        onChange({ lat: e.latLng.lat(), lon: e.latLng.lng() });
      }}
      options={{
        streetViewControl: false,
        mapTypeControl: false,
        fullscreenControl: false
      }}
    >
      {markerPosition ? <Marker position={markerPosition} /> : null}
    </GoogleMap>
  );
}

export default function Stations() {
  const [stations, setStations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [editingId, setEditingId] = useState(null);
  const [showModal, setShowModal] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [formData, setFormData] = useState({
    name: '',
    latitude: null,
    longitude: null,
    description: '',
    points: 0,
    imageUrl: '',
    qrCode: ''
  });

  const { isLoaded, loadError } = useLoadScript({
    googleMapsApiKey: import.meta.env.VITE_GOOGLE_MAPS_API_KEY
  });

  useEffect(() => {
    fetchStations();
  }, []);

  const fetchStations = async () => {
    try {
      setLoading(true);
      const snapshot = await getDocs(collection(db, 'stations'));
      const data = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      }));
      setStations(data);
    } catch (error) {
      console.error('Allomasok betoltese sikertelen:', error);
      alert('Hiba az allomasok betoltese kozben');
    } finally {
      setLoading(false);
    }
  };

  const handleEdit = (station) => {
    setEditingId(station.id);
    setFormData({
      name: station.name || '',
      latitude: station.latitude ?? null,
      longitude: station.longitude ?? null,
      description: station.description || '',
      points: station.points || 0,
      imageUrl: station.imageUrl || '',
      qrCode: station.qrCode || ''
    });
    setShowModal(true);
  };

  const handleAdd = () => {
    setEditingId(null);
    setFormData({
      name: '',
      latitude: null,
      longitude: null,
      description: '',
      points: 0,
      imageUrl: '',
      qrCode: ''
    });
    setShowModal(true);
  };

  const handleImageUpload = async (file) => {
    if (!file) return;
    try {
      setUploading(true);
      const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_');
      const storageRef = ref(storage, `stations/${Date.now()}_${safeName}`);
      await uploadBytes(storageRef, file);
      const url = await getDownloadURL(storageRef);
      setFormData(prev => ({ ...prev, imageUrl: url }));
    } catch (error) {
      console.error('Kep feltoltes sikertelen:', error);
      alert('Hiba a kep feltoltese kozben');
    } finally {
      setUploading(false);
    }
  };

  const handleSave = async () => {
    if (!formData.name || formData.latitude == null || formData.longitude == null) {
      alert('Kerdek add nevet es jelolj ki koordinatat a terkepen!');
      return;
    }

    try {
      const payload = {
        name: formData.name,
        latitude: Number(formData.latitude),
        longitude: Number(formData.longitude),
        description: formData.description || '',
        points: parseInt(formData.points) || 0,
        imageUrl: formData.imageUrl || '',
        qrCode: formData.qrCode || ''
      };

      if (editingId) {
        const docRef = doc(db, 'stations', editingId);
        await updateDoc(docRef, payload);
      } else {
        await addDoc(collection(db, 'stations'), payload);
      }
      setShowModal(false);
      fetchStations();
    } catch (error) {
      console.error('Mentes sikertelen:', error);
      alert('Hiba a mentes kozben');
    }
  };

  const handleDelete = async (id) => {
    if (!window.confirm('Biztosan torolni szeretned ezt az allomast?')) return;
    try {
      await deleteDoc(doc(db, 'stations', id));
      fetchStations();
    } catch (error) {
      console.error('Torles sikertelen:', error);
      alert('Hiba a torles kozben');
    }
  };

  const handleMapPick = (coords) => {
    setFormData(prev => ({
      ...prev,
      latitude: coords.lat,
      longitude: coords.lon
    }));
  };

  const handleDownloadPdf = async (station) => {
    try {
      const docPdf = new jsPDF({ unit: 'mm', format: 'a4' });
      const qrValue = getQrValue(station);
      const qrUrl = getQrImageUrl(qrValue, 220);
      const qrData = await fetchDataUrl(qrUrl);

      docPdf.setFont('helvetica', 'bold');
      docPdf.setFontSize(18);
      docPdf.text(station.name || 'Allomas', 20, 20);

      docPdf.setFont('helvetica', 'normal');
      docPdf.setFontSize(12);
      const coordText = `Koordinata: ${station.latitude?.toFixed(5)}, ${station.longitude?.toFixed(5)}`;
      docPdf.text(coordText, 20, 30);

      if (station.description) {
        docPdf.setFontSize(11);
        const lines = docPdf.splitTextToSize(station.description, 170);
        docPdf.text(lines, 20, 40);
      }

      docPdf.addImage(qrData, 'PNG', 20, 70, 60, 60);
      docPdf.setFontSize(10);
      docPdf.text(`QR: ${qrValue}`, 20, 135);

      if (station.imageUrl) {
        try {
          const imageData = await fetchDataUrl(station.imageUrl);
          docPdf.addImage(imageData, 'JPEG', 100, 70, 90, 60);
        } catch (err) {
          console.error('Kep PDF-be tetele sikertelen:', err);
        }
      }

      const fileName = `${(station.name || 'allomas').replace(/\s+/g, '_')}_QR.pdf`;
      docPdf.save(fileName);
    } catch (error) {
      console.error('PDF letoltes hiba:', error);
      alert('Hiba a PDF letoltese kozben');
    }
  };

  if (loading) return <div className="stations-shell"><p className="empty-state">Betoltes...</p></div>;

  return (
    <div className="stations-shell">
      <div className="stations-hero">
        <div className="hero-copy">
          <p className="hero-kicker">Allomas studio</p>
          <h1>Allomasok</h1>
          <p className="hero-subtitle">Helyszinek, leirasok es QR kodok egy helyen.</p>
        </div>
        <div className="hero-actions">
          <button onClick={handleAdd} className="btn-primary">+ Uj allomas</button>
        </div>
      </div>

      <div className="stations-grid">
        {stations.map(station => {
          const qrValue = getQrValue(station);
          const qrUrl = getQrImageUrl(qrValue);
          return (
            <div key={station.id} className="station-card">
              <div className="station-media">
                {station.imageUrl ? (
                  <img src={station.imageUrl} alt={station.name} />
                ) : (
                  <div className="station-placeholder">Nincs kep</div>
                )}
                <span className="station-points">⭐ {station.points} pont</span>
              </div>
              <div className="station-body">
                <div className="station-title">
                  <h3>{station.name}</h3>
                  <span className="station-coords">📍 {station.latitude?.toFixed(4)}, {station.longitude?.toFixed(4)}</span>
                </div>
                <p className="station-desc">{station.description || 'Nincs leiras megadva.'}</p>
                <div className="station-qr">
                  <div className="qr-meta">
                    <span className="qr-label">QR: {qrValue}</span>
                    <button className="qr-print" type="button" onClick={() => handleDownloadPdf(station)}>Nyomtatas</button>
                  </div>
                  <img src={qrUrl} alt={`QR ${station.name}`} />
                </div>
                <div className="station-actions">
                  <button onClick={() => handleEdit(station)} className="btn-edit">Szerkesztes</button>
                  <button onClick={() => handleDelete(station.id)} className="btn-delete">Torles</button>
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {showModal && (
        <div className="modal-overlay">
          <div className="modal">
            <h2>{editingId ? 'Allomas szerkesztese' : 'Uj allomas'}</h2>
            <div className="form-group">
              <label>Nev *</label>
              <input
                type="text"
                value={formData.name}
                onChange={(e) => setFormData({ ...formData, name: e.target.value })}
              />
            </div>
            <div className="form-group">
              <label>Leiras</label>
              <textarea
                value={formData.description}
                onChange={(e) => setFormData({ ...formData, description: e.target.value })}
              />
            </div>
            <div className="form-group">
              <label>Koordinata (terkepen valaszd ki)</label>
              <div className="map-picker">
                {loadError ? (
                  <div className="map-hint">Google Maps hiba. Ellenorizd az API kulcsot.</div>
                ) : !isLoaded ? (
                  <div className="map-hint">Terkep betoltese...</div>
                ) : (
                  <MapPicker value={{ lat: formData.latitude, lon: formData.longitude }} onChange={handleMapPick} />
                )}
              </div>
              <p className="map-hint">
                {formData.latitude && formData.longitude
                  ? `Kivalasztva: ${formData.latitude.toFixed(5)}, ${formData.longitude.toFixed(5)}`
                  : 'Kattints a terkepre a koordinata beallitashoz.'}
              </p>
            </div>
            <div className="form-group">
              <label>Pontok</label>
              <input
                type="number"
                value={formData.points}
                onChange={(e) => setFormData({ ...formData, points: e.target.value })}
              />
            </div>
            <div className="form-group">
              <label>Kep feltoltese (opcionalis)</label>
              <input
                type="file"
                accept="image/*"
                onChange={(e) => handleImageUpload(e.target.files?.[0])}
              />
              {uploading && <p className="upload-note">Feltoltes...</p>}
              {formData.imageUrl && !uploading && (
                <img className="image-preview" src={formData.imageUrl} alt="Elonezet" />
              )}
            </div>
            <div className="form-group">
              <label>QR kod (opcionalis)</label>
              <input
                type="text"
                value={formData.qrCode}
                onChange={(e) => setFormData({ ...formData, qrCode: e.target.value })}
                placeholder="Ha ures, az allomas ID lesz hasznalva"
              />
            </div>
            <div className="modal-actions">
              <button onClick={handleSave} className="btn-save">Mentes</button>
              <button onClick={() => setShowModal(false)} className="btn-cancel">Megsem</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
