import React, { useMemo, useState } from 'react';
import { db, storage } from '../firebaseConfig';
import { collection, deleteField, doc, writeBatch } from 'firebase/firestore';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { normalizePhotosFromDoc, buildPhotoFields } from '../utils/photoHelpers';
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
import { useProject } from '../context/ProjectContext';
import { safeString } from '../utils/safeString';
import { useFirestoreCollection } from '../hooks/useFirestoreCollection';
import { usePhotoManager } from '../hooks/usePhotoManager';
import ConfirmDialog from '../components/ConfirmDialog';
import PhotoGrid from '../components/PhotoGrid';
import StateCard from '../components/StateCard';
import '../styles/Content.css';

const EMPTY_FORM = {
  name:        '',
  date:        '',
  description: '',
  location:    '',
  qrCode:      '',
  points:      20,
};

const mapEvent = (docSnap) => {
  const d = docSnap.data();
  const normalized = normalizePhotosFromDoc(d);
  return {
    id:          docSnap.id,
    name:        safeString(d.name),
    date:        safeString(d.date),
    description: safeString(d.description),
    location:    safeString(d.location),
    photos:      normalized,
    imageUrl:    normalized[0] || '',
    qrCode:      safeString(d.qrCode),
    points:      Number(d.points || 20),
  };
};

// Múltbeli-e az esemény (a napja korábbi, mint ma). Üres/érvénytelen dátumot
// nem tekintünk múltbelinek. A mai napon zajló esemény még aktuális.
export const isPastEvent = (event) => {
  const raw = (event.date || '').trim();
  if (!raw) return false;
  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) return false;
  const eventDay = new Date(parsed.getFullYear(), parsed.getMonth(), parsed.getDate());
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  return eventDay < today;
};

function Events() {
  // A listázás a generikus hookkal megy; a mentés és a törlés viszont a
  // QR-leképezéssel együtt, egy kötegben történik (lásd stageQrSave).
  const { query } = useFirestoreCollection('events', mapEvent);
  const queryClient = useQueryClient();
  const { activeProjectId } = useProject();
  const { data: qrCodes = new Map() } = useQuery({
    queryKey: ['qr_codes', activeProjectId],
    queryFn: () => loadQrCodesByTarget(db, activeProjectId),
  });
  const eventCode = (event) => currentQrCode(qrCodes, 'event', event);

  const [showForm,     setShowForm]     = useState(false);
  const [editingId,    setEditingId]    = useState(null);
  const [mutateError,  setMutateError]  = useState(null);
  const [deleteDialog, setDeleteDialog] = useState({ open: false, id: null });
  const [formData,     setFormData]     = useState(EMPTY_FORM);
  const [search,       setSearch]       = useState('');
  const [showPast,     setShowPast]     = useState(false);
  const [saving,       setSaving]       = useState(false);

  const { photos, uploading, uploadFeedback, upload, remove: removePhoto,
          reset: resetPhotos, commitRemovals } =
    usePhotoManager({ storage, folder: 'content-images' });

  const events = query.data ?? [];

  const subtitle = useMemo(
    () => `${events.length} rendezvény · QR-kód és fotó támogatással`,
    [events.length],
  );

  const openEditor = (event = null) => {
    if (event) {
      setEditingId(event.id);
      setFormData({
        name:        event.name        || '',
        date:        event.date        || '',
        description: event.description || '',
        location:    event.location    || '',
        qrCode:      eventCode(event),
        points:      event.points      || 20,
      });
      resetPhotos(event.photos || (event.imageUrl ? [event.imageUrl] : []));
    } else {
      setEditingId(null);
      setFormData(EMPTY_FORM);
      resetPhotos();
    }
    setMutateError(null);
    setShowForm(true);
  };

  const closeEditor = () => {
    setShowForm(false);
    setEditingId(null);
    setFormData(EMPTY_FORM);
    resetPhotos();
    setMutateError(null);
  };

  const setField = (field) => (e) =>
    setFormData((prev) => ({ ...prev, [field]: e.target.value }));

  const handleSubmit = async (e) => {
    e.preventDefault();
    setMutateError(null);
    const cleanData = {
      name:        safeString(formData.name),
      date:        safeString(formData.date),
      description: safeString(formData.description),
      location:    safeString(formData.location),
      ...buildPhotoFields(photos),
      points:      Number(formData.points || 20),
      projectId:   activeProjectId,
    };
    setSaving(true);
    try {
      const previous = editingId ? events.find((event) => event.id === editingId) : null;
      const previousCode = previous ? eventCode(previous) : null;
      const code = safeString(formData.qrCode).trim() || generateQrCode();
      if (code !== previousCode) {
        const problem = customQrCodeProblem(code);
        if (problem) {
          setMutateError(problem);
          return;
        }
      }
      await assertQrCodeAvailable(db, { code, kind: 'event', targetId: editingId });

      const targetRef = editingId ? doc(db, 'events', editingId) : doc(collection(db, 'events'));
      const batch = writeBatch(db);
      await stageQrSave(db, {
        batch,
        ops: { deleteField },
        kind: 'event',
        targetRef,
        isNew: !editingId,
        payload: cleanData,
        code,
        previousCode,
        projectId: activeProjectId,
      });
      await batch.commit();
      queryClient.invalidateQueries({ queryKey: ['events'] });
      queryClient.invalidateQueries({ queryKey: ['qr_codes'] });

      await commitRemovals();
      closeEditor();
    } catch (err) {
      if (err instanceof QrCodeCollisionError) {
        setMutateError('Ez a QR-kód már egy másik elemhez tartozik!');
      } else {
        setMutateError('Hiba a mentéskor');
      }
    } finally {
      setSaving(false);
    }
  };

  const confirmDelete = async () => {
    if (!deleteDialog.id) return;
    try {
      const deleted = events.find((event) => event.id === deleteDialog.id);
      const batch = writeBatch(db);
      stageQrDelete(db, {
        batch,
        targetRef: doc(db, 'events', deleteDialog.id),
        code: deleted ? eventCode(deleted) : null,
      });
      await batch.commit();
      queryClient.invalidateQueries({ queryKey: ['events'] });
      queryClient.invalidateQueries({ queryKey: ['qr_codes'] });
      setDeleteDialog({ open: false, id: null });
    } catch {
      setMutateError('Hiba a törléskor');
      setDeleteDialog({ open: false, id: null });
    }
  };

  if (query.isLoading) {
    return (
      <StateCard
        variant="loading"
        icon="📅"
        title="Rendezvények betöltése..."
        description="Kérlek várj, az adatok betöltése folyamatban van."
      />
    );
  }
  if (query.isError) {
    return (
      <StateCard
        variant="empty"
        icon="⚠️"
        title="Nem sikerült betölteni"
        description="Hiba történt az adatok betöltésekor. Próbáld újra később."
      />
    );
  }

  const isBusy = uploading || saving;

  const pastCount = events.filter(isPastEvent).length;

  const visibleEvents = events.filter((event) => {
    if (!showPast && isPastEvent(event)) return false;
    const q = search.trim().toLowerCase();
    if (!q) return true;
    return [event.name, event.location, event.description]
      .some((field) => field?.toLowerCase().includes(q));
  });

  return (
    <div className="content-page">
      <div className="page-header">
        <h1>Rendezvények</h1>
        <p>{subtitle}</p>
      </div>

      {mutateError && <div className="error-message">{mutateError}</div>}

      <div className="content-toolbar">
        <button className="btn-primary" onClick={() => openEditor()}>
          + Új rendezvény
        </button>
        {events.length > 0 && (
          <>
            <input
              className="content-search"
              type="search"
              placeholder="🔍 Keresés név, helyszín vagy leírás alapján..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
            <span className="content-search-count">{visibleEvents.length} / {events.length}</span>
          </>
        )}
        {pastCount > 0 && (
          <label className="past-toggle">
            <input
              type="checkbox"
              checked={showPast}
              onChange={(e) => setShowPast(e.target.checked)}
            />
            Múltbeli rendezvények megjelenítése ({pastCount})
          </label>
        )}
      </div>

      {showForm && (
        <div
          className="editor-overlay"
          onClick={(e) => e.target === e.currentTarget && closeEditor()}
        >
          <div className="editor-modal">
            <div className="editor-header">
              <div>
                <p className="editor-kicker">Rendezvény szerkesztő</p>
                <h2>{editingId ? 'Rendezvény frissítése' : 'Új rendezvény'}</h2>
              </div>
              <button type="button" className="editor-close" onClick={closeEditor} aria-label="Bezárás" title="Bezárás">×</button>
            </div>

            <form onSubmit={handleSubmit} className="editor-grid">
              {mutateError && <div className="error-message editor-error">{mutateError}</div>}

              <div className="editor-main">
                <div className="editor-field">
                  <label>Név *</label>
                  <input type="text" value={formData.name} onChange={setField('name')} required />
                </div>
                <div className="editor-row">
                  <div className="editor-field">
                    <label>Dátum *</label>
                    <input type="date" value={formData.date} onChange={setField('date')} required />
                  </div>
                  <div className="editor-field">
                    <label>Pont</label>
                    <input type="number" min="0" value={formData.points} onChange={setField('points')} />
                  </div>
                </div>
                <div className="editor-field">
                  <label>Helyszín</label>
                  <input type="text" value={formData.location} onChange={setField('location')} />
                </div>
                <div className="editor-field">
                  <label htmlFor="event-qr">QR-kód</label>
                  <div className="qr-code-row">
                    <input
                      id="event-qr"
                      type="text"
                      value={formData.qrCode}
                      onChange={setField('qrCode')}
                      placeholder="Üresen hagyva biztonságos, véletlen kód készül"
                    />
                    <button type="button" className="btn-secondary" onClick={() => setFormData((prev) => ({ ...prev, qrCode: generateQrCode() }))}>
                      Új véletlen kód
                    </button>
                  </div>
                  {editingId && formData.qrCode && isWeakQrCode(formData.qrCode, editingId) && (
                    <span className="field-hint field-warning">⚠️ Ez a kód kitalálható. Generálj újat, és nyomtasd újra a matricát.</span>
                  )}
                </div>
                <div className="editor-field">
                  <label>Leírás</label>
                  <textarea rows="4" value={formData.description} onChange={setField('description')} />
                </div>
              </div>

              <div className="editor-side">
                <PhotoGrid
                  photos={photos}
                  uploading={uploading}
                  feedback={uploadFeedback}
                  onUpload={upload}
                  onRemove={removePhoto}
                />
              </div>

              <div className="editor-actions">
                <button type="button" className="btn-secondary" onClick={closeEditor}>
                  Mégse
                </button>
                <button type="submit" className="btn-primary" disabled={isBusy}>
                  {isBusy ? 'Folyamatban...' : editingId ? 'Frissítés' : 'Mentés'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      <div className="cards-grid">
        {events.length === 0 && (
          <div className="content-empty">
            <span className="empty-icon" aria-hidden="true">📅</span>
            <h3>Még nincs rendezvény</h3>
            <p>Hozd létre az elsőt a „+ Új rendezvény” gombbal.</p>
          </div>
        )}
        {events.length > 0 && visibleEvents.length === 0 && (
          <div className="content-empty">
            <span className="empty-icon" aria-hidden="true">🔎</span>
            <h3>Nincs találat</h3>
            <p>Próbálj másik kulcsszót, vagy töröld a keresést.</p>
          </div>
        )}
        {visibleEvents.map((event) => {
          const qrValue = eventCode(event);
          return (
            <div key={event.id} className={`card${isPastEvent(event) ? ' card-past' : ''}`}>
              <h3>
                {event.name || 'Nincs név'}
                {isPastEvent(event) && <span className="past-badge">Múltbeli</span>}
              </h3>
              {event.date     && <p><strong>Dátum:</strong> {event.date}</p>}
              {event.location && <p><strong>Helyszín:</strong> {event.location}</p>}
              <p><strong>Pont:</strong> {event.points}</p>
              {event.imageUrl && (
                <img src={event.imageUrl} alt={event.name} loading="lazy" className="content-cover" />
              )}
              <QrImage value={qrValue} alt={`QR ${event.name}`} className="content-qr" />
              {event.description && <p>{event.description}</p>}
              <div className="card-actions">
                <button className="btn-edit"   onClick={() => openEditor(event)}>Szerkesztés</button>
                <button className="btn-delete" onClick={() => setDeleteDialog({ open: true, id: event.id })}>Törlés</button>
              </div>
            </div>
          );
        })}
      </div>

      <ConfirmDialog
        open={deleteDialog.open}
        title="Rendezvény törlése"
        message="Biztosan törlöd ezt a rendezvényt?"
        confirmText="Törlés"
        onClose={() => setDeleteDialog({ open: false, id: null })}
        onConfirm={confirmDelete}
      />
    </div>
  );
}

export default Events;
