import React, { useEffect, useState } from 'react';
import { db, storage } from '../firebaseConfig';
import { addDoc, collection, deleteDoc, doc, getDocs, updateDoc } from 'firebase/firestore';
import { getDownloadURL, ref, uploadBytes } from 'firebase/storage';
import { GoogleMap, Marker, useLoadScript } from '@react-google-maps/api';
import { jsPDF } from 'jspdf';
import Snackbar from '@mui/material/Snackbar';
import Alert from '@mui/material/Alert';
import '../styles/Stations.css';
import ConfirmDialog from '../components/ConfirmDialog';

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
  const markerPosition =
    value?.lat != null && value?.lon != null
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
        fullscreenControl: false,
      }}
    >
      {markerPosition ? <Marker position={markerPosition} /> : null}
    </GoogleMap>
  );
}

export default function Stations() {
  const [stations, setStations] = useState([]);
  const [trips, setTrips] = useState([]);
  const [loading, setLoading] = useState(true);
  const [editingId, setEditingId] = useState(null);
  const [showModal, setShowModal] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [deleteDialog, setDeleteDialog] = useState({ open: false, id: null });
  const [snack, setSnack] = useState({ open: false, msg: '', severity: 'error' });

  const showMsg = (msg, severity = 'error') =>
    setSnack({ open: true, msg, severity });

  const [formData, setFormData] = useState({
    name: '',
    latitude: null,
    longitude: null,
    description: '',
    points: 0,
    imageUrl: '',
    qrCode: '',
    tripId: '',
  });

  const { isLoaded, loadError } = useLoadScript({
    googleMapsApiKey: import.meta.env.VITE_GOOGLE_MAPS_API_KEY,
  });

  useEffect(() => {
    fetchStations();
    fetchTrips();
  }, []);

  const fetchStations = async () => {
    try {
      setLoading(true);
      const snapshot = await getDocs(collection(db, 'stations'));
      const data = snapshot.docs.map((item) => ({
        id: item.id,
        ...item.data(),
      }));
      setStations(data);
    } catch (error) {
      console.error('Allomasok betoltese sikertelen:', error);
      showMsg('Hiba az allomasok betoltese kozben');
    } finally {
      setLoading(false);
    }
  };

  const fetchTrips = async () => {
    try {
      const snapshot = await getDocs(collection(db, 'trips'));
      const data = snapshot.docs.map((item) => ({ id: item.id, ...item.data() }));
      setTrips(data);
    } catch (error) {
      console.error('Turak betoltese sikertelen:', error);
    }
  };

  const getTripName = (tripId) => {
    if (!tripId) return 'Nincs turahoz rendelve';
    const trip = trips.find((item) => item.id === tripId);
    return trip?.name || 'Ismeretlen tura';
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
      qrCode: station.qrCode || '',
      tripId: station.tripId || '',
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
      qrCode: '',
      tripId: '',
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
      setFormData((prev) => ({ ...prev, imageUrl: url }));
    } catch (error) {
      console.error('Kep feltoltes sikertelen:', error);
      showMsg('Hiba a kep feltoltese kozben');
    } finally {
      setUploading(false);
    }
  };

  const handleSave = async () => {
    if (!formData.name || formData.latitude == null || formData.longitude == null) {
      showMsg('Kerdek add nevet es jelolj ki koordinatat a terkepen!', 'warning');
      return;
    }

    try {
      const payload = {
        name: formData.name,
        latitude: Number(formData.latitude),
        longitude: Number(formData.longitude),
        description: formData.description || '',
        points: parseInt(formData.points, 10) || 0,
        imageUrl: formData.imageUrl || '',
        qrCode: formData.qrCode || '',
        tripId: formData.tripId || '',
      };

      if (editingId) {
        await updateDoc(doc(db, 'stations', editingId), payload);
      } else {
        await addDoc(collection(db, 'stations'), payload);
      }

      setShowModal(false);
      fetchStations();
    } catch (error) {
      console.error('Mentes sikertelen:', error);
      showMsg('Hiba a mentes kozben');
    }
  };

  const handleDelete = (id) => {
    setDeleteDialog({ open: true, id });
  };

  const confirmDelete = async () => {
    if (!deleteDialog.id) return;
    try {
      await deleteDoc(doc(db, 'stations', deleteDialog.id));
      setDeleteDialog({ open: false, id: null });
      fetchStations();
    } catch (error) {
      console.error('Torles sikertelen:', error);
      showMsg('Hiba a torles kozben');
      setDeleteDialog({ open: false, id: null });
    }
  };

  const handleMapPick = (coords) => {
    setFormData((prev) => ({
      ...prev,
      latitude: coords.lat,
      longitude: coords.lon,
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
      docPdf.text(`Tura: ${getTripName(station.tripId)}`, 20, 38);

      if (station.description) {
        docPdf.setFontSize(11);
        const lines = docPdf.splitTextToSize(station.description, 170);
        docPdf.text(lines, 20, 48);
      }

      docPdf.addImage(qrData, 'PNG', 20, 78, 60, 60);
      docPdf.setFontSize(10);
      docPdf.text(`QR: ${qrValue}`, 20, 143);

      if (station.imageUrl) {
        try {
          const imageData = await fetchDataUrl(station.imageUrl);
          docPdf.addImage(imageData, 'JPEG', 100, 78, 90, 60);
        } catch (err) {
          console.error('Kep PDF-be tetele sikertelen:', err);
        }
      }

      const fileName = `${(station.name || 'allomas').replace(/\s+/g, '_')}_QR.pdf`;
      docPdf.save(fileName);
    } catch (error) {
      console.error('PDF letoltes hiba:', error);
      showMsg('Hiba a PDF letoltese kozben');
    }
  };

  if (loading) {
    return (
      <div className="stations-shell">
        <p className="empty-state">Betoltes...</p>
      </div>
    );
  }

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
        {stations.map((station) => {
          const qrValue = getQrValue(station);
          const qrUrl = getQrImageUrl(qrValue);
          return (
            <div key={station.id} className="station-card">
              <div className="station-media">
                {station.imageUrl ? (
                  <img src={station.imageUrl} alt={station.name} loading="lazy" />
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
                <p className="station-desc"><strong>Tura:</strong> {getTripName(station.tripId)}</p>
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
              <input type="text" value={formData.name} onChange={(e) => setFormData({ ...formData, name: e.target.value })} />
            </div>

            <div className="form-group">
              <label>Leiras</label>
              <textarea value={formData.description} onChange={(e) => setFormData({ ...formData, description: e.target.value })} />
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
              <label>Turahoz rendeles</label>
              <select
                value={formData.tripId || ''}
                onChange={(e) => setFormData({ ...formData, tripId: e.target.value })}
              >
                <option value="">Nincs turahoz rendelve</option>
                {trips.map((trip) => (
                  <option key={trip.id} value={trip.id}>{trip.name || trip.id}</option>
                ))}
              </select>
            </div>

            <div className="form-group">
              <label>Pontok</label>
              <input type="number" value={formData.points} onChange={(e) => setFormData({ ...formData, points: e.target.value })} />
            </div>

            <div className="form-group">
              <label>Kep feltoltese (opcionalis)</label>
              <input type="file" accept="image/*" onChange={(e) => handleImageUpload(e.target.files?.[0])} />
              {uploading && <p className="upload-note">Feltoltes...</p>}
              {formData.imageUrl && !uploading && <img className="image-preview" src={formData.imageUrl} alt="Elonezet" loading="lazy" />}
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

      <ConfirmDialog
        open={deleteDialog.open}
        title="Allomas torlese"
        message="Biztosan torold ezt az allomast?"
        confirmText="Torles"
        onClose={() => setDeleteDialog({ open: false, id: null })}
        onConfirm={confirmDelete}
      />

      <Snackbar
        open={snack.open}
        autoHideDuration={4000}
        onClose={() => setSnack((s) => ({ ...s, open: false }))}
        anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}
      >
        <Alert severity={snack.severity} onClose={() => setSnack((s) => ({ ...s, open: false }))}>
          {snack.msg}
        </Alert>
      </Snackbar>
    </div>
  );
}
