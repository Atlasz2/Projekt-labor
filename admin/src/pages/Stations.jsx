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
  const markerPosition = value?.lat != null && value?.lon != null ? { lat: value.lat, lng: value.lon } : null;
  const center = markerPosition || DEFAULT_CENTER;
  return (
    <GoogleMap
      mapContainerStyle={MAP_CONTAINER_STYLE}
      center={center}
      zoom={13}
      onClick={(e) => { if (!e.latLng) return; onChange({ lat: e.latLng.lat(), lon: e.latLng.lng() }); }}
      options={{ streetViewControl: false, mapTypeControl: false, fullscreenControl: false }}
    >
      {markerPosition ? <Marker position={markerPosition} /> : null}
    </GoogleMap>
  );
}

const EMPTY_FORM = {
  name: '', latitude: null, longitude: null, description: '',
  points: 10, imageUrl: '', qrCode: '', tripId: '',
  funFact: '', unlockContent: '', extraInfo: '',
};

export default function Stations() {
  const [stations, setStations] = useState([]);
  const [trips, setTrips] = useState([]);
  const [loading, setLoading] = useState(true);
  const [editingId, setEditingId] = useState(null);
  const [showModal, setShowModal] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [deleteDialog, setDeleteDialog] = useState({ open: false, id: null });
  const [snack, setSnack] = useState({ open: false, msg: '', severity: 'error' });
  const [formData, setFormData] = useState(EMPTY_FORM);
  const [activeSection, setActiveSection] = useState(0);

  const showMsg = (msg, severity = 'error') => setSnack({ open: true, msg, severity });

  const { isLoaded, loadError } = useLoadScript({ googleMapsApiKey: import.meta.env.VITE_GOOGLE_MAPS_API_KEY });

  useEffect(() => { fetchStations(); fetchTrips(); }, []);

  const fetchStations = async () => {
    try {
      setLoading(true);
      const snapshot = await getDocs(collection(db, 'stations'));
      setStations(snapshot.docs.map((d) => ({ id: d.id, ...d.data() })));
    } catch { showMsg('Hiba az állomások betöltésekor'); }
    finally { setLoading(false); }
  };

  const fetchTrips = async () => {
    try {
      const snapshot = await getDocs(collection(db, 'trips'));
      setTrips(snapshot.docs.map((d) => ({ id: d.id, ...d.data() })));
    } catch { /* silent */ }
  };

  const getTripName = (tripId) => {
    if (!tripId) return null;
    return trips.find((t) => t.id === tripId)?.name || 'Ismeretlen túra';
  };

  const handleEdit = (station) => {
    setEditingId(station.id);
    setFormData({
      name: station.name || '', latitude: station.latitude ?? null, longitude: station.longitude ?? null,
      description: station.description || '', points: station.points || 10,
      imageUrl: station.imageUrl || '', qrCode: station.qrCode || '', tripId: station.tripId || '',
      funFact: station.funFact || '', unlockContent: station.unlockContent || '', extraInfo: station.extraInfo || '',
    });
    setActiveSection(0);
    setShowModal(true);
  };

  const handleAdd = () => {
    setEditingId(null);
    setFormData(EMPTY_FORM);
    setActiveSection(0);
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
    } catch { showMsg('Hiba a kép feltöltésekor'); }
    finally { setUploading(false); }
  };

  const handleSave = async () => {
    if (!formData.name.trim()) { showMsg('Add meg az állomás nevét!', 'warning'); return; }
    if (formData.latitude == null || formData.longitude == null) { showMsg('Jelöld ki a helyszínt a térképen!', 'warning'); return; }
    try {
      const payload = {
        name: formData.name.trim(), latitude: Number(formData.latitude), longitude: Number(formData.longitude),
        description: formData.description.trim(), points: parseInt(formData.points, 10) || 10,
        imageUrl: formData.imageUrl || '', qrCode: formData.qrCode.trim() || '',
        tripId: formData.tripId || '', funFact: formData.funFact.trim(),
        unlockContent: formData.unlockContent.trim(), extraInfo: formData.extraInfo.trim(),
      };
      if (editingId) { await updateDoc(doc(db, 'stations', editingId), payload); }
      else { await addDoc(collection(db, 'stations'), payload); }
      setShowModal(false);
      showMsg('Állomás mentve!', 'success');
      fetchStations();
    } catch { showMsg('Hiba mentés közben'); }
  };

  const confirmDelete = async () => {
    if (!deleteDialog.id) return;
    try {
      await deleteDoc(doc(db, 'stations', deleteDialog.id));
      setDeleteDialog({ open: false, id: null });
      fetchStations();
    } catch { showMsg('Hiba törlés közben'); setDeleteDialog({ open: false, id: null }); }
  };

  const handleDownloadPdf = async (station) => {
    try {
      const docPdf = new jsPDF({ unit: 'mm', format: 'a4' });
      const qrValue = getQrValue(station);
      const qrData = await fetchDataUrl(getQrImageUrl(qrValue, 220));
      docPdf.setFont('helvetica', 'bold');
      docPdf.setFontSize(18);
      docPdf.text(station.name || 'Állomás', 20, 20);
      docPdf.setFont('helvetica', 'normal');
      docPdf.setFontSize(12);
      docPdf.text(`Koordináta: ${station.latitude?.toFixed(5)}, ${station.longitude?.toFixed(5)}`, 20, 30);
      docPdf.text(`Túra: ${getTripName(station.tripId) || 'Nincs'}`, 20, 38);
      if (station.description) { const lines = docPdf.splitTextToSize(station.description, 170); docPdf.text(lines, 20, 48); }
      docPdf.addImage(qrData, 'PNG', 20, 78, 60, 60);
      docPdf.setFontSize(10);
      docPdf.text(`QR: ${qrValue}`, 20, 143);
      if (station.imageUrl) {
        try { const imgData = await fetchDataUrl(station.imageUrl); docPdf.addImage(imgData, 'JPEG', 100, 78, 90, 60); } catch {}
      }
      docPdf.save(`${(station.name || 'allomas').replace(/\s+/g, '_')}_QR.pdf`);
    } catch { showMsg('Hiba PDF letöltésekor'); }
  };

  const sections = ['🏷️ Alap adatok', '📍 Helyszín', '📖 Tartalom', '🔓 Feloldható info', '🖼️ Média'];

  if (loading) return <div className="stations-shell"><p className="empty-state">Betöltés...</p></div>;

  return (
    <div className="stations-shell">
      <div className="stations-hero">
        <div className="hero-copy">
          <p className="hero-kicker">Állomás studio</p>
          <h1>Állomások</h1>
          <p className="hero-subtitle">Helyszínek, leírások és QR kódok egy helyen.</p>
        </div>
        <div className="hero-actions">
          <button onClick={handleAdd} className="btn-primary">+ Új állomás</button>
        </div>
      </div>

      <div className="stations-grid">
        {stations.map((station) => {
          const qrValue = getQrValue(station);
          const tripName = getTripName(station.tripId);
          return (
            <div key={station.id} className="station-card">
              <div className="station-media">
                {station.imageUrl ? <img src={station.imageUrl} alt={station.name} loading="lazy" /> : <div className="station-placeholder">📷</div>}
                <span className="station-points">⭐ {station.points} pont</span>
              </div>
              <div className="station-body">
                <div className="station-title">
                  <h3>{station.name}</h3>
                  {tripName && <span className="trip-badge">🗺️ {tripName}</span>}
                </div>
                <p className="station-desc">{station.description || 'Nincs leírás megadva.'}</p>
                {station.funFact && <p className="station-fun-fact">💡 {station.funFact}</p>}
                <div className="station-qr">
                  <div className="qr-meta">
                    <span className="qr-label">QR: {qrValue.substring(0, 16)}{qrValue.length > 16 ? '…' : ''}</span>
                    <button className="qr-print" type="button" onClick={() => handleDownloadPdf(station)}>🖨️ Nyomtatás</button>
                  </div>
                  <img src={getQrImageUrl(qrValue)} alt={`QR ${station.name}`} />
                </div>
                <div className="station-actions">
                  <button onClick={() => handleEdit(station)} className="btn-edit">✏️ Szerkesztés</button>
                  <button onClick={() => setDeleteDialog({ open: true, id: station.id })} className="btn-delete">🗑️ Törlés</button>
                </div>
              </div>
            </div>
          );
        })}
        {stations.length === 0 && <p className="empty-state">Még nincsenek állomások. Adj hozzá egyet!</p>}
      </div>

      {showModal && (
        <div className="modal-overlay" onClick={(e) => e.target === e.currentTarget && setShowModal(false)}>
          <div className="modal station-modal">
            <div className="modal-header">
              <h2>{editingId ? '✏️ Állomás szerkesztése' : '➕ Új állomás'}</h2>
              <button className="modal-close" onClick={() => setShowModal(false)}>✕</button>
            </div>

            <div className="section-tabs">
              {sections.map((sec, i) => (
                <button key={i} className={`section-tab${activeSection === i ? ' active' : ''}`} onClick={() => setActiveSection(i)}>{sec}</button>
              ))}
            </div>

            <div className="modal-body">
              {activeSection === 0 && (
                <div className="form-section">
                  <div className="field-group">
                    <label>📌 Állomás neve <span className="required">*</span></label>
                    <input type="text" value={formData.name} onChange={(e) => setFormData({ ...formData, name: e.target.value })} placeholder="pl. Kinizsi vár kapuja" />
                  </div>
                  <div className="field-row">
                    <div className="field-group">
                      <label>⭐ Pont érték</label>
                      <input type="number" min="1" max="100" value={formData.points} onChange={(e) => setFormData({ ...formData, points: e.target.value })} />
                      <span className="field-hint">Az állomás beolvasásával szerzett pontok</span>
                    </div>
                    <div className="field-group">
                      <label>🗺️ Túrához rendelés</label>
                      <select value={formData.tripId || ''} onChange={(e) => setFormData({ ...formData, tripId: e.target.value })}>
                        <option value="">— Nincs túrához rendelve —</option>
                        {trips.map((trip) => <option key={trip.id} value={trip.id}>{trip.name || trip.id}</option>)}
                      </select>
                    </div>
                  </div>
                  <div className="field-group">
                    <label>🔑 QR kód (egyedi azonosító)</label>
                    <input type="text" value={formData.qrCode} onChange={(e) => setFormData({ ...formData, qrCode: e.target.value })} placeholder="Ha üres, az állomás ID lesz használva" />
                    <span className="field-hint">Az állomásnál kihelyezett QR kódon lévő szöveg</span>
                  </div>
                </div>
              )}

              {activeSection === 1 && (
                <div className="form-section">
                  <div className="field-group">
                    <label>🗺️ Helyszín kijelölése <span className="required">*</span></label>
                    <p className="field-hint map-hint-top">Kattints a térképen az állomás pontos helyére</p>
                    {loadError ? <div className="map-error">Google Maps hiba – ellenőrizd az API kulcsot.</div>
                      : !isLoaded ? <div className="map-loading">Térkép betöltése...</div>
                      : <MapPicker value={{ lat: formData.latitude, lon: formData.longitude }} onChange={(c) => setFormData({ ...formData, latitude: c.lat, longitude: c.lon })} />}
                    {formData.latitude && formData.longitude
                      ? <p className="coords-display">✅ Kiválasztva: {formData.latitude.toFixed(5)}, {formData.longitude.toFixed(5)}</p>
                      : <p className="coords-display warn">⚠️ Még nincs koordináta kiválasztva</p>}
                  </div>
                </div>
              )}

              {activeSection === 2 && (
                <div className="form-section">
                  <div className="field-group">
                    <label>📝 Rövid leírás</label>
                    <textarea rows="3" value={formData.description} onChange={(e) => setFormData({ ...formData, description: e.target.value })} placeholder="Rövid bemutatás az állomásról..." />
                    <span className="field-hint">Ez jelenik meg az állomást listázó nézetekben</span>
                  </div>
                  <div className="field-group">
                    <label>💡 Érdekesség</label>
                    <textarea rows="2" value={formData.funFact} onChange={(e) => setFormData({ ...formData, funFact: e.target.value })} placeholder="Egy érdekes ténye az állomásról..." />
                    <span className="field-hint">Egy soros "did you know" jellegű mondat</span>
                  </div>
                </div>
              )}

              {activeSection === 3 && (
                <div className="form-section">
                  <div className="unlock-info-box">
                    <span className="unlock-icon">🔓</span>
                    <div>
                      <strong>Feloldható tartalom</strong>
                      <p>Ezt az információt a látogató csak akkor látja, ha beolvassa az állomás QR kódját!</p>
                    </div>
                  </div>
                  <div className="field-group">
                    <label>📖 Feloldott szöveg / történet</label>
                    <textarea rows="5" value={formData.unlockContent} onChange={(e) => setFormData({ ...formData, unlockContent: e.target.value })} placeholder="Az állomás részletes leírása, helytörténet, érdekességek – ami beolvasáskor jelenik meg..." />
                    <span className="field-hint">Hosszabb szöveg, ami a QR beolvasása után jelenik meg a telefonon</span>
                  </div>
                  <div className="field-group">
                    <label>ℹ️ Extra információ</label>
                    <textarea rows="2" value={formData.extraInfo} onChange={(e) => setFormData({ ...formData, extraInfo: e.target.value })} placeholder="Nyitvatartás, belépési díj, megközelítés..." />
                  </div>
                </div>
              )}

              {activeSection === 4 && (
                <div className="form-section">
                  <div className="field-group">
                    <label>🖼️ Borítókép feltöltése</label>
                    <div className="upload-zone">
                      <input type="file" id="img-upload" accept="image/*" onChange={(e) => handleImageUpload(e.target.files?.[0])} style={{ display: 'none' }} />
                      <label htmlFor="img-upload" className="upload-btn">{uploading ? '⏳ Feltöltés...' : '📁 Kép kiválasztása'}</label>
                      {formData.imageUrl && !uploading && <img className="image-preview" src={formData.imageUrl} alt="Előnézet" loading="lazy" />}
                    </div>
                  </div>
                </div>
              )}
            </div>

            <div className="modal-footer">
              <div className="section-nav">
                {activeSection > 0 && <button className="btn-nav" onClick={() => setActiveSection(activeSection - 1)}>← Előző</button>}
                {activeSection < sections.length - 1 && <button className="btn-nav primary" onClick={() => setActiveSection(activeSection + 1)}>Következő →</button>}
              </div>
              <div className="footer-actions">
                <button onClick={() => setShowModal(false)} className="btn-cancel">Mégse</button>
                <button onClick={handleSave} className="btn-save">💾 Mentés</button>
              </div>
            </div>
          </div>
        </div>
      )}

      <ConfirmDialog open={deleteDialog.open} title="Állomás törlése" message="Biztosan törlöd ezt az állomást?" confirmText="Törlés"
        onClose={() => setDeleteDialog({ open: false, id: null })} onConfirm={confirmDelete} />
      <Snackbar open={snack.open} autoHideDuration={4000} onClose={() => setSnack((s) => ({ ...s, open: false }))} anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}>
        <Alert severity={snack.severity} onClose={() => setSnack((s) => ({ ...s, open: false }))}>{snack.msg}</Alert>
      </Snackbar>
    </div>
  );
}
