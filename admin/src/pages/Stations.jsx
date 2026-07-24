import PropTypes from "prop-types";
import React, { useState, useEffect, useMemo } from 'react';
import { useSearchParams } from 'react-router-dom';
import { db, storage } from '../firebaseConfig';
import { addDoc, collection, deleteDoc, doc, getDocs, updateDoc } from 'firebase/firestore';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { uploadImageWithFallback, fetchDataUrl } from '../utils/imageUpload';
import { GoogleMap, Marker, useLoadScript } from '@react-google-maps/api';
import { jsPDF } from 'jspdf';
import Snackbar from '@mui/material/Snackbar';
import Alert from '@mui/material/Alert';
import '../styles/Stations.css';
import '../styles/About.css';
import ConfirmDialog from '../components/ConfirmDialog';
import StateCard from '../components/StateCard';
import { normalizePhotosFromDoc, buildPhotoFields } from '../utils/photoHelpers';
import { getQrValue, getQrImageUrl } from '../utils/qrHelpers';
import { assertQrCodeAvailable, syncQrMapping, removeQrMapping, QrCodeCollisionError } from '../utils/qrMapping';

const DEFAULT_CENTER = { lat: 47.06, lng: 17.715 };
const MAP_CONTAINER_STYLE = { height: '220px', width: '100%' };

function MapPicker({ value, onChange }) {
  const markerPosition = value?.lat != null && value?.lon != null ? { lat: value.lat, lng: value.lon } : null;
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
      options={{ streetViewControl: false, mapTypeControl: false, fullscreenControl: false }}
    >
      {markerPosition ? <Marker position={markerPosition} /> : null}
    </GoogleMap>
  );
}

MapPicker.propTypes = {
  value: PropTypes.shape({
    lat: PropTypes.number,
    lon: PropTypes.number,
  }),
  onChange: PropTypes.func.isRequired,
};

MapPicker.defaultProps = {
  value: null,
};

const EMPTY_FORM = {
  name: '',
  latitude: null,
  longitude: null,
  description: '',
  points: 10,
  photos: [],
  qrCode: '',
  tripId: '',
  unlockContent: '',
  extraInfo: '',
  unlockContentImageUrl: '',
};

export default function Stations() {
  const queryClient = useQueryClient();
  const [searchParams, setSearchParams] = useSearchParams();
  const [paramsHandled, setParamsHandled] = useState(false);
  const { data: stations = [], isLoading } = useQuery({
    queryKey: ['stations'],
    queryFn: async () => {
      const snapshot = await getDocs(collection(db, 'stations'));
      return snapshot.docs.map((item) => ({ id: item.id, ...item.data() }));
    },
  });
  const { data: trips = [] } = useQuery({
    queryKey: ['trips'],
    queryFn: async () => {
      const snapshot = await getDocs(collection(db, 'trips'));
      return snapshot.docs.map((item) => ({ id: item.id, ...item.data() }));
    },
  });
  const [editingId, setEditingId] = useState(null);
  const [showModal, setShowModal] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [deleteDialog, setDeleteDialog] = useState({ open: false, id: null });
  const [snack, setSnack] = useState({ open: false, msg: '', severity: 'error' });
  const [formData, setFormData] = useState(EMPTY_FORM);
  const [search, setSearch] = useState('');
  const [tripFilter, setTripFilter] = useState('all');

  const showMsg = (msg, severity = 'error') => setSnack({ open: true, msg, severity });
  const { isLoaded, loadError } = useLoadScript({ googleMapsApiKey: import.meta.env.VITE_GOOGLE_MAPS_API_KEY });

  // Build the id→name lookup once per trips change instead of a linear find()
  // on every station, on every render / search keystroke.
  const tripNameById = useMemo(
    () => new Map(trips.map((trip) => [trip.id, trip.name || 'Ismeretlen túra'])),
    [trips],
  );
  const getTripName = (tripId) => (tripId ? tripNameById.get(tripId) || 'Ismeretlen túra' : null);

  const handleEdit = (station) => {
    setEditingId(station.id);
    setFormData({
      name: station.name || '',
      latitude: station.latitude ?? null,
      longitude: station.longitude ?? null,
      description: station.description || '',
      points: station.points || 10,
      photos: normalizePhotosFromDoc(station),
      qrCode: station.qrCode || '',
      tripId: station.tripId || '',
      unlockContent: station.unlockContent || '',
      extraInfo: station.extraInfo || '',
      unlockContentImageUrl: station.unlockContentImageUrl || '',
    });
    setShowModal(true);
  };

  const handleAdd = (prefillTripId = '') => {
    setEditingId(null);
    setFormData({ ...EMPTY_FORM, tripId: prefillTripId || '' });
    setShowModal(true);
  };

  const handleImageUpload = async (file) => {
    if (!file) return;
    if (formData.photos.length >= 6) { showMsg('Maximum 6 kép tölthető fel.', 'warning'); return; }
    try {
      setUploading(true);
      const result = await uploadImageWithFallback({ file, storage, folder: 'stations' });
      setFormData((current) => ({ ...current, photos: [...current.photos, result.url] }));
      showMsg(result.mode === 'inline' ? result.message : 'Kép sikeresen feltöltve! ✅', result.mode === 'inline' ? 'warning' : 'success');
    } catch (err) {
      showMsg(`Hiba a kép feltöltésekor: ${err?.message || 'ismeretlen hiba'}`);
    } finally {
      setUploading(false);
    }
  };

  const handleRemovePhoto = (index) => {
    setFormData((current) => ({ ...current, photos: current.photos.filter((_, i) => i !== index) }));
  };

  const handleUnlockImageUpload = async (file) => {
    if (!file) return;
    try {
      setUploading(true);
      const result = await uploadImageWithFallback({ file, storage, folder: 'stations' });
      setFormData((current) => ({ ...current, unlockContentImageUrl: result.url }));
      showMsg(result.mode === 'inline' ? result.message : 'Kép sikeresen feltöltve! ✅', result.mode === 'inline' ? 'warning' : 'success');
    } catch (err) {
      showMsg(`Hiba a kép feltöltésekor: ${err?.message || 'ismeretlen hiba'}`);
    } finally {
      setUploading(false);
    }
  };

  const handleSave = async () => {
    if (!formData.name.trim()) {
      showMsg('Add meg az állomás nevét!', 'warning');
      return;
    }
    if (formData.latitude == null || formData.longitude == null) {
      showMsg('Jelöld ki a helyszínt a térképen!', 'warning');
      return;
    }

    const dupName = formData.name.trim().toLowerCase();
    const dupTrip = formData.tripId || '';
    const duplicate = stations.find((station) =>
      station.id !== editingId
      && station.name?.trim().toLowerCase() === dupName
      && (station.tripId || '') === dupTrip
    );

    if (duplicate) {
      showMsg('Már létezik ilyen nevű állomás ebben a túrában!', 'warning');
      return;
    }

    try {
      const payload = {
        name: formData.name.trim(),
        latitude: Number(formData.latitude),
        longitude: Number(formData.longitude),
        description: formData.description.trim(),
        points: parseInt(formData.points, 10) || 10,
        ...buildPhotoFields(formData.photos),
        qrCode: formData.qrCode.trim() || '',
        tripId: formData.tripId || '',
        unlockContent: formData.unlockContent.trim(),
        extraInfo: formData.extraInfo.trim(),
        unlockContentImageUrl: formData.unlockContentImageUrl || '',
      };

      await assertQrCodeAvailable(db, {
        code: payload.qrCode,
        kind: 'station',
        targetId: editingId,
      });

      let savedId = editingId;
      if (editingId) {
        await updateDoc(doc(db, 'stations', editingId), payload);
      } else {
        const ref = await addDoc(collection(db, 'stations'), payload);
        savedId = ref.id;
      }

      // A privát qr_codes leképezés frissítése — best effort: ha elhasal,
      // a Cloud Function legacy fallbackje (qrCode mező) akkor is működik.
      const previous = editingId
        ? stations.find((station) => station.id === editingId)
        : null;
      try {
        await syncQrMapping(db, {
          kind: 'station',
          targetId: savedId,
          code: payload.qrCode,
          previousCode: previous ? getQrValue(previous) : null,
        });
      } catch {
        /* legacy fallback fedi */
      }

      setShowModal(false);
      showMsg('Állomás mentve!', 'success');
      queryClient.invalidateQueries({ queryKey: ['stations'] });
    } catch (err) {
      if (err instanceof QrCodeCollisionError) {
        showMsg('Ez a QR-kód már egy másik elemhez tartozik!', 'warning');
      } else {
        showMsg('Hiba mentés közben');
      }
    }
  };

  const confirmDelete = async () => {
    if (!deleteDialog.id) return;
    try {
      const deleted = stations.find((station) => station.id === deleteDialog.id);
      await deleteDoc(doc(db, 'stations', deleteDialog.id));
      try {
        await removeQrMapping(db, {
          code: deleted?.qrCode,
          targetId: deleteDialog.id,
        });
      } catch {
        /* árva leképezést a redeemQr found:false-ként kezel */
      }
      setDeleteDialog({ open: false, id: null });
      queryClient.invalidateQueries({ queryKey: ['stations'] });
    } catch {
      showMsg('Hiba törlés közben');
      setDeleteDialog({ open: false, id: null });
    }
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

      if (station.description) {
        const lines = docPdf.splitTextToSize(station.description, 170);
        docPdf.text(lines, 20, 48);
      }

      docPdf.addImage(qrData, 'PNG', 20, 78, 60, 60);
      docPdf.setFontSize(10);
      docPdf.text(`QR: ${qrValue}`, 20, 143);

      if (station.imageUrl) {
        try {
          const imgData = await fetchDataUrl(station.imageUrl);
          docPdf.addImage(imgData, 'JPEG', 100, 78, 90, 60);
        } catch {
          // silent
        }
      }

      docPdf.save(`${(station.name || 'allomas').replace(/\s+/g, '_')}_QR.pdf`);
    } catch {
      showMsg('Hiba PDF letöltésekor');
    }
  };

  // Deep-link support: open the editor pre-filled when navigated from the Trips page
  // (?addForTrip=<tripId> opens a blank station for that trip, ?edit=<stationId> edits one)
  useEffect(() => {
    if (paramsHandled || isLoading) return undefined;

    const addForTrip = searchParams.get('addForTrip');
    const editId = searchParams.get('edit');
    if (!addForTrip && !editId) return undefined;

    const timer = setTimeout(() => {
      if (editId) {
        const station = stations.find((item) => item.id === editId);
        if (station) {
          handleEdit(station);
          setTripFilter(station.tripId || 'all');
        }
      } else if (addForTrip) {
        handleAdd(addForTrip);
        setTripFilter(addForTrip);
      }
      setParamsHandled(true);
      setSearchParams({}, { replace: true });
    }, 0);

    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isLoading, stations, searchParams, paramsHandled]);


  const unassignedCount = stations.filter((station) => !station.tripId).length;

  const filtered = stations.filter((station) => {
    if (tripFilter === 'none' && station.tripId) return false;
    if (tripFilter !== 'all' && tripFilter !== 'none' && station.tripId !== tripFilter) return false;

    const query = search.toLowerCase();
    return !query
      || station.name?.toLowerCase().includes(query)
      || station.description?.toLowerCase().includes(query)
      || getTripName(station.tripId)?.toLowerCase().includes(query);
  });

  if (isLoading) {
    return <StateCard variant="loading" icon="📍" title="Állomások betöltése..." description="Kérjük várj, az adatok betöltése folyamatban van." />;
  }

  return (
    <div className="stations-shell">
      <div className="stations-hero">
        <div className="hero-copy">
          <h1>Állomások</h1>
          <p className="hero-subtitle">Helyszínek, leírások és QR kódok egy helyen.</p>
        </div>
        <div className="hero-actions">
          <button onClick={() => handleAdd()} className="btn-primary">+ Új állomás</button>
        </div>
      </div>

      <div className="stations-search">
        <input
          type="search"
          placeholder="🔍 Keresés neve, leírása vagy túrája alapján..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="search-input"
        />
        <select
          className="trip-filter-select"
          value={tripFilter}
          onChange={(e) => setTripFilter(e.target.value)}
          aria-label="Szűrés túra szerint"
        >
          <option value="all">🗺️ Összes túra</option>
          {trips.map((trip) => (
            <option key={trip.id} value={trip.id}>{trip.name || trip.id}</option>
          ))}
          <option value="none">🚩 Nincs túrához rendelve ({unassignedCount})</option>
        </select>
        <span className="search-count">{filtered.length} / {stations.length} állomás</span>
      </div>

      {stations.length === 0 ? (
        <StateCard
          variant="empty"
          icon="📍"
          title="Nincsenek még állomások"
          description="Adj hozzá egy új állomást a túráidhoz."
          actionLabel="Első állomás hozzáadása"
          onAction={() => handleAdd()}
        />
      ) : filtered.length === 0 ? (
        <StateCard
          variant="empty"
          icon="🔎"
          title="Nincs találat"
          description="Próbálj másik kulcsszót, vagy töröld a keresést."
          actionLabel="Keresés törlése"
          onAction={() => setSearch('')}
        />
      ) : (
        <div className="stations-grid">
                {filtered.map((station) => {
                  const qrValue = getQrValue(station);
                  const tripName = getTripName(station.tripId);
                  const coverPhoto = normalizePhotosFromDoc(station)[0] || '';

                  return (
                    <div key={station.id} className="station-card">
                      <div className="station-media">
                        {coverPhoto ? <img src={coverPhoto} alt={station.name} loading="lazy" /> : <div className="station-placeholder">📷</div>}
                        <span className="station-points">⭐ {station.points} pont</span>
                      </div>
                      <div className="station-body">
                        <div className="station-title">
                          <h3>{station.name}</h3>
                          {tripName
                            ? <span className="trip-badge">🗺️ {tripName}</span>
                            : <span className="trip-badge unassigned">🚩 Nincs túrához rendelve</span>}
                        </div>
                        <p className="station-desc">{station.description || 'Nincs leírás megadva.'}</p>
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
              </div>
            )}

      {showModal && (
        <div className="about-editor-backdrop" onClick={(e) => e.target === e.currentTarget && setShowModal(false)} role="presentation">
          <div className="about-editor-shell station-editor-shell" role="dialog" aria-modal="true" onClick={(e) => e.stopPropagation()}>
            <div className="about-editor-header">
              <div>
                <p className="about-editor-kicker">Állomás szerkesztő</p>
                <h2>{editingId ? 'Állomás szerkesztése' : 'Új állomás'}</h2>
                <p>Minden adat egy lapon — görgess végig a szekciókon. A csillaggal jelölt mezők kötelezők.</p>
              </div>
              <button className="about-editor-close" onClick={() => setShowModal(false)} type="button">Bezárás</button>
            </div>

            <div className="station-editor-body">
              <div className="about-editor-form">
                <section className="about-editor-section">
                  <div className="about-editor-section-head">
                    <span>1</span>
                    <div><h3>Alapadatok</h3><p>Az állomás neve, pontértéke, túrája és QR-kódja.</p></div>
                  </div>
                  <div className="field-group">
                    <label>Állomás neve <span className="required">*</span></label>
                    <input type="text" value={formData.name} onChange={(e) => setFormData({ ...formData, name: e.target.value })} placeholder="pl. Kinizsi vár kapuja" />
                  </div>
                  <div className="field-row">
                    <div className="field-group">
                      <label>Pont érték</label>
                      <input type="number" min="1" max="100" value={formData.points} onChange={(e) => setFormData({ ...formData, points: e.target.value })} />
                      <span className="field-hint">Az állomás beolvasásával szerzett pontok</span>
                    </div>
                    <div className="field-group">
                      <label>Túrához rendelés</label>
                      <select value={formData.tripId || ''} onChange={(e) => setFormData({ ...formData, tripId: e.target.value })}>
                        <option value="">— Nincs túrához rendelve —</option>
                        {trips.map((trip) => <option key={trip.id} value={trip.id}>{trip.name || trip.id}</option>)}
                      </select>
                    </div>
                  </div>
                  <div className="field-group">
                    <label>QR kód (egyedi azonosító)</label>
                    <input type="text" value={formData.qrCode} onChange={(e) => setFormData({ ...formData, qrCode: e.target.value })} placeholder="Ha üres, az állomás ID lesz használva" />
                    <span className="field-hint">Az állomásnál kihelyezett QR kódon lévő szöveg</span>
                  </div>
                </section>

                <section className="about-editor-section">
                  <div className="about-editor-section-head">
                    <span>2</span>
                    <div><h3>Borítókép</h3><p>Az első kép lesz a borítókép a listákban és a térképen.</p></div>
                  </div>
                  <div className="field-group">
                    <div className="photo-grid station-photo-grid">
                      {formData.photos.map((url, i) => (
                        <div key={i} className="photo-thumb">
                          {url ? <img src={url} alt="" /> : null}
                          <button type="button" className="photo-remove" onClick={() => handleRemovePhoto(i)}>✕</button>
                          {i === 0 && <span className="thumb-badge">Borítókép</span>}
                        </div>
                      ))}
                      {formData.photos.length < 6 && (
                        <label className="photo-add-btn">
                          <input type="file" accept="image/*" disabled={uploading} onChange={(e) => { if (e.target.files?.[0]) handleImageUpload(e.target.files[0]); e.target.value = ""; }} />
                          {uploading ? "Feltöltés..." : "+ Kép"}
                        </label>
                      )}
                    </div>
                    <span className="field-hint">{formData.photos.length}/6 kép • az első lesz a borítókép</span>
                  </div>
                </section>

                <section className="about-editor-section">
                  <div className="about-editor-section-head">
                    <span>3</span>
                    <div><h3>Helyszín</h3><p>Kattints a térképen az állomás pontos helyére.</p></div>
                  </div>
                  <div className="field-group">
                    <label>Helyszín kijelölése <span className="required">*</span></label>
                    {loadError ? <div className="map-error">Google Maps hiba – ellenőrizd az API kulcsot.</div>
                      : !isLoaded ? <div className="map-loading">Térkép betöltése...</div>
                      : <MapPicker value={{ lat: formData.latitude, lon: formData.longitude }} onChange={(coords) => setFormData({ ...formData, latitude: coords.lat, longitude: coords.lon })} />}
                    {formData.latitude && formData.longitude
                      ? <p className="coords-display">✅ Kiválasztva: {formData.latitude.toFixed(5)}, {formData.longitude.toFixed(5)}</p>
                      : <p className="coords-display warn">⚠️ Még nincs koordináta kiválasztva</p>}
                  </div>
                </section>

                <section className="about-editor-section">
                  <div className="about-editor-section-head">
                    <span>4</span>
                    <div><h3>Leírás</h3><p>Rövid bemutatás, ami a listázó nézetekben jelenik meg.</p></div>
                  </div>
                  <div className="field-group">
                    <label>Rövid leírás</label>
                    <textarea rows="3" value={formData.description} onChange={(e) => setFormData({ ...formData, description: e.target.value })} placeholder="Rövid bemutatás az állomásról..." />
                    <span className="field-hint">Ez jelenik meg az állomást listázó nézetekben</span>
                  </div>
                </section>

                <section className="about-editor-section">
                  <div className="about-editor-section-head">
                    <span>5</span>
                    <div><h3>Feloldható tartalom</h3><p>Ezt a látogató csak a QR-kód beolvasása után látja a telefonján.</p></div>
                  </div>
                  <div className="field-group">
                    <label>Feloldott szöveg / történet</label>
                    <textarea rows="5" value={formData.unlockContent} onChange={(e) => setFormData({ ...formData, unlockContent: e.target.value })} placeholder="Az állomás részletes leírása, helytörténet, érdekességek – ami beolvasáskor jelenik meg..." />
                    <span className="field-hint">Hosszabb szöveg, ami a QR beolvasása után jelenik meg</span>
                  </div>
                  <div className="field-group">
                    <label>Feloldott tartalom képe</label>
                    {formData.unlockContentImageUrl ? (
                      <div className="photo-grid station-photo-grid">
                        <div className="photo-thumb">
                          <img src={formData.unlockContentImageUrl} alt="Feloldott tartalom" />
                          <button type="button" className="photo-remove" onClick={() => setFormData({ ...formData, unlockContentImageUrl: '' })}>✕</button>
                        </div>
                      </div>
                    ) : (
                      <div className="photo-grid station-photo-grid">
                        <label className="photo-add-btn">
                          <input type="file" accept="image/*" disabled={uploading} onChange={(e) => { if (e.target.files?.[0]) handleUnlockImageUpload(e.target.files[0]); e.target.value = ""; }} />
                          {uploading ? "Feltöltés..." : "+ Kép"}
                        </label>
                      </div>
                    )}
                    <span className="field-hint">A beolvasás után a feloldott szöveggel együtt jelenik meg</span>
                  </div>
                  <div className="field-group">
                    <label>Extra információ</label>
                    <textarea rows="2" value={formData.extraInfo} onChange={(e) => setFormData({ ...formData, extraInfo: e.target.value })} placeholder="Nyitvatartás, belépési díj, megközelítés..." />
                  </div>
                </section>

                <div className="form-actions about-editor-actions">
                  <button onClick={handleSave} className="btn-primary">💾 Mentés</button>
                  <button onClick={() => setShowModal(false)} className="btn-secondary" type="button">Mégse</button>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      <ConfirmDialog
        open={deleteDialog.open}
        title="Állomás törlése"
        message="Biztosan törlöd ezt az állomást?"
        confirmText="Törlés"
        onClose={() => setDeleteDialog({ open: false, id: null })}
        onConfirm={confirmDelete}
      />
      <Snackbar open={snack.open} autoHideDuration={4000} onClose={() => setSnack((current) => ({ ...current, open: false }))} anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}>
        <Alert severity={snack.severity} onClose={() => setSnack((current) => ({ ...current, open: false }))}>{snack.msg}</Alert>
      </Snackbar>
    </div>
  );
}


