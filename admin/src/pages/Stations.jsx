import PropTypes from "prop-types";
import React, { useState, useEffect, useMemo } from 'react';
import { useSearchParams } from 'react-router-dom';
import { db, storage } from '../firebaseConfig';
import { collection, deleteField, doc, getDocs, writeBatch } from 'firebase/firestore';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { uploadImageWithFallback, fetchDataUrl } from '../utils/imageUpload';
import { useProject } from '../context/ProjectContext';
import { filterByProject } from '../utils/projects';
import { GoogleMap, Marker, useLoadScript } from '@react-google-maps/api';
import { jsPDF } from 'jspdf';
import Snackbar from '@mui/material/Snackbar';
import Alert from '@mui/material/Alert';
import '../styles/Stations.css';
import '../styles/About.css';
import ConfirmDialog from '../components/ConfirmDialog';
import StateCard from '../components/StateCard';
import { normalizePhotosFromDoc, buildPhotoFields } from '../utils/photoHelpers';
import { qrDataUrl } from '../utils/qrHelpers';
import QrImage from '../components/QrImage';
import {
  assertQrCodeAvailable,
  currentQrCode,
  customQrCodeProblem,
  generateQrCode,
  isWeakQrCode,
  loadQrCodesByTarget,
  QrCodeCollisionError,
  stageQrDelete,
  stageQrSave,
} from '../utils/qrMapping';
import { stationTripIds, buildTripOrderOnSave } from '../utils/stationTrips';

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
  requireLocation: false,
  tripIds: [],
  unlockContent: '',
  unlockContentImageUrl: '',
};

export default function Stations() {
  const queryClient = useQueryClient();
  const { activeProjectId } = useProject();
  const [searchParams, setSearchParams] = useSearchParams();
  const [paramsHandled, setParamsHandled] = useState(false);
  // A listák az aktív településre (projectId) szűrve – a hiányzó projectId az
  // alapértelmezett projektet jelenti, így a régi adat is látszik.
  const { data: stations = [], isLoading } = useQuery({
    queryKey: ['stations', activeProjectId],
    queryFn: async () => {
      const snapshot = await getDocs(collection(db, 'stations'));
      const all = snapshot.docs.map((item) => ({ id: item.id, ...item.data() }));
      return filterByProject(all, activeProjectId);
    },
  });
  const { data: trips = [] } = useQuery({
    queryKey: ['trips', activeProjectId],
    queryFn: async () => {
      const snapshot = await getDocs(collection(db, 'trips'));
      const all = snapshot.docs.map((item) => ({ id: item.id, ...item.data() }));
      return filterByProject(all, activeProjectId);
    },
  });
  // A QR-kódok értéke csak a privát leképezésben él (a nyilvános dokumentum
  // a lenyomatot tárolja), ezért a megjelenítéshez innen olvassuk.
  const { data: qrCodes = new Map() } = useQuery({
    queryKey: ['qr_codes', activeProjectId],
    queryFn: () => loadQrCodesByTarget(db, activeProjectId),
  });
  const stationCode = (station) => currentQrCode(qrCodes, 'station', station);
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
      qrCode: stationCode(station),
      requireLocation: station.requireLocation === true,
      tripIds: stationTripIds(station),
      unlockContent: station.unlockContent || '',
      unlockContentImageUrl: station.unlockContentImageUrl || '',
    });
    setShowModal(true);
  };

  const handleAdd = (prefillTripId = '') => {
    setEditingId(null);
    setFormData({ ...EMPTY_FORM, tripIds: prefillTripId ? [prefillTripId] : [] });
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
    // Egy állomás több túrának is megállója lehet – ütközésnek azt tekintjük,
    // ha ugyanaz a név ugyanabban a (legalább egy közös) túrában már létezik.
    // A "nincs túrához rendelve" állomásokat egy üres '' pszeudo-túraként kezeljük.
    const targetTripIds = formData.tripIds.length ? formData.tripIds : [''];
    const duplicate = stations.find((station) => {
      if (station.id === editingId) return false;
      if (station.name?.trim().toLowerCase() !== dupName) return false;
      const stationTrips = stationTripIds(station);
      const compareTripIds = stationTrips.length ? stationTrips : [''];
      return targetTripIds.some((tid) => compareTripIds.includes(tid));
    });

    if (duplicate) {
      showMsg('Már létezik ilyen nevű állomás ebben a túrában!', 'warning');
      return;
    }

    try {
      const editingStation = editingId ? stations.find((s) => s.id === editingId) : null;
      const payload = {
        name: formData.name.trim(),
        latitude: Number(formData.latitude),
        longitude: Number(formData.longitude),
        description: formData.description.trim(),
        points: parseInt(formData.points, 10) || 10,
        ...buildPhotoFields(formData.photos),
        requireLocation: !!formData.requireLocation,
        tripIds: formData.tripIds,
        tripOrder: buildTripOrderOnSave({
          station: editingStation,
          allStations: stations,
          selectedTripIds: formData.tripIds,
        }),
        unlockContent: formData.unlockContent.trim(),
        unlockContentImageUrl: formData.unlockContentImageUrl || '',
        // White-label: az állomás az aktív településhez tartozik.
        projectId: activeProjectId,
      };
      // A régi egyszeres tripId/orderIndex mezők eltávolítása, hogy ne
      // éledjenek fel visszamenőleges kompatibilitásként egy jövőbeli
      // olvasásnál. FieldValue.delete() csak update()-nél megengedett, új
      // dokumentumnál (addDoc) nincs mit törölni.
      if (editingId) {
        payload.tripId = deleteField();
        payload.orderIndex = deleteField();
      }

      // A kód: a megadott (vagy a meglévő) érték, üresen hagyva biztonságos,
      // véletlen kód. Új vagy megváltoztatott kódnál a gyenge érték tiltott.
      const previousCode = editingStation ? stationCode(editingStation) : null;
      const code = formData.qrCode.trim() || generateQrCode();
      if (code !== previousCode) {
        const problem = customQrCodeProblem(code);
        if (problem) {
          showMsg(problem, 'warning');
          return;
        }
      }
      await assertQrCodeAvailable(db, { code, kind: 'station', targetId: editingId });

      // Az állomás és a QR-leképezése egy kötegben íródik (atomi).
      const targetRef = editingId
        ? doc(db, 'stations', editingId)
        : doc(collection(db, 'stations'));
      const batch = writeBatch(db);
      await stageQrSave(db, {
        batch,
        ops: { deleteField },
        kind: 'station',
        targetRef,
        isNew: !editingId,
        payload,
        code,
        previousCode,
        projectId: activeProjectId,
      });
      await batch.commit();
      queryClient.invalidateQueries({ queryKey: ['qr_codes'] });

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
      // Az állomás és a QR-leképezése együtt törlődik (nem marad árva kód).
      const batch = writeBatch(db);
      stageQrDelete(db, {
        batch,
        targetRef: doc(db, 'stations', deleteDialog.id),
        code: deleted ? stationCode(deleted) : null,
      });
      await batch.commit();
      setDeleteDialog({ open: false, id: null });
      queryClient.invalidateQueries({ queryKey: ['stations'] });
      queryClient.invalidateQueries({ queryKey: ['qr_codes'] });
    } catch {
      showMsg('Hiba törlés közben');
      setDeleteDialog({ open: false, id: null });
    }
  };

  const handleDownloadPdf = async (station) => {
    try {
      const docPdf = new jsPDF({ unit: 'mm', format: 'a4' });
      const qrValue = stationCode(station);
      const qrData = await qrDataUrl(qrValue, 440);

      docPdf.setFont('helvetica', 'bold');
      docPdf.setFontSize(18);
      docPdf.text(station.name || 'Állomás', 20, 20);
      docPdf.setFont('helvetica', 'normal');
      docPdf.setFontSize(12);
      docPdf.text(`Koordináta: ${station.latitude?.toFixed(5)}, ${station.longitude?.toFixed(5)}`, 20, 30);
      const tripNames = stationTripIds(station).map(getTripName).filter(Boolean);
      docPdf.text(`Túra: ${tripNames.join(', ') || 'Nincs'}`, 20, 38);

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
          setTripFilter(stationTripIds(station)[0] || 'all');
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


  const unassignedCount = stations.filter((station) => stationTripIds(station).length === 0).length;

  const filtered = stations.filter((station) => {
    const tripIds = stationTripIds(station);
    if (tripFilter === 'none' && tripIds.length > 0) return false;
    if (tripFilter !== 'all' && tripFilter !== 'none' && !tripIds.includes(tripFilter)) return false;

    const query = search.toLowerCase();
    return !query
      || station.name?.toLowerCase().includes(query)
      || station.description?.toLowerCase().includes(query)
      || tripIds.some((tid) => getTripName(tid)?.toLowerCase().includes(query));
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
                  const qrValue = stationCode(station);
                  // A kulcs a túra azonosítója (két ismeretlen túra neve azonos lenne),
                  // és amíg a túrák nem töltődtek be, nem mutatunk „Ismeretlen túrát”.
                  const tripChips = trips.length
                    ? stationTripIds(station).map((tid) => ({ id: tid, name: getTripName(tid) }))
                    : [];
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
                          {tripChips.length > 0
                            ? tripChips.map((trip) => <span key={trip.id} className="trip-badge">🗺️ {trip.name}</span>)
                            : trips.length > 0 && <span className="trip-badge unassigned">🚩 Nincs túrához rendelve</span>}
                        </div>
                        <p className="station-desc">{station.description || 'Nincs leírás megadva.'}</p>
                        <div className="station-qr">
                          <div className="qr-meta">
                            <span className="qr-label">QR: {qrValue.substring(0, 16)}{qrValue.length > 16 ? '…' : ''}</span>
                            <button className="qr-print" type="button" onClick={() => handleDownloadPdf(station)}>🖨️ Nyomtatás</button>
                          </div>
                          <QrImage value={qrValue} alt={`QR ${station.name}`} />
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
                  <div className="field-group">
                    <label>Pont érték</label>
                    <input type="number" min="1" max="100" value={formData.points} onChange={(e) => setFormData({ ...formData, points: e.target.value })} />
                    <span className="field-hint">Az állomás beolvasásával szerzett pontok</span>
                  </div>
                  <div className="field-group">
                    <label>Túrákhoz rendelés</label>
                    {trips.length === 0 ? (
                      <p className="field-hint">Még nincs túra létrehozva.</p>
                    ) : (
                      <div className="trip-membership-list">
                        {trips.map((trip) => {
                          const checked = formData.tripIds.includes(trip.id);
                          return (
                            <label key={trip.id} className="trip-membership-item">
                              <input
                                type="checkbox"
                                checked={checked}
                                onChange={(e) => setFormData((prev) => ({
                                  ...prev,
                                  tripIds: e.target.checked
                                    ? [...prev.tripIds, trip.id]
                                    : prev.tripIds.filter((id) => id !== trip.id),
                                }))}
                              />
                              {trip.name || trip.id}
                            </label>
                          );
                        })}
                      </div>
                    )}
                    <span className="field-hint">Egy állomás akár több túrának is megállója lehet (vagy egynek sem).</span>
                  </div>
                  <div className="field-group">
                    <label htmlFor="station-qr">QR-kód</label>
                    <div className="qr-code-row">
                      <input id="station-qr" type="text" value={formData.qrCode} onChange={(e) => setFormData({ ...formData, qrCode: e.target.value })} placeholder="Üresen hagyva biztonságos, véletlen kód készül" />
                      <button type="button" className="btn-secondary" onClick={() => setFormData({ ...formData, qrCode: generateQrCode() })}>Új véletlen kód</button>
                    </div>
                    {editingId && formData.qrCode && isWeakQrCode(formData.qrCode, editingId) ? (
                      <span className="field-hint field-warning">⚠️ Ez a kód kitalálható (rövid, vagy egyezik az állomás azonosítójával). Generálj újat, és nyomtasd újra a matricát.</span>
                    ) : (
                      <span className="field-hint">A kód csak az admin felületen és a kinyomtatott matricán látszik; a mobil kliensek nem tudják kigyűjteni. Kódváltás után a matricát újra kell nyomtatni.</span>
                    )}
                  </div>
                  <div className="field-group">
                    <label className="checkbox-label">
                      <input type="checkbox" checked={!!formData.requireLocation} onChange={(e) => setFormData({ ...formData, requireLocation: e.target.checked })} />
                      Helymeghatározás kötelező a beolvasáshoz
                    </label>
                    <span className="field-hint">Bekapcsolva csak a helyszínen lévő, bekapcsolt helymeghatározású telefon kap pontot (a lefényképezett kód távolról nem váltható be). Kikapcsolva a GPS nélküli eszközök is gyűjthetnek.</span>
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
                </section>

                <div className="form-actions about-editor-actions">
                  <button onClick={() => setShowModal(false)} className="btn-secondary" type="button">Mégse</button>
                  <button onClick={handleSave} className="btn-primary" type="button">Mentés</button>
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


