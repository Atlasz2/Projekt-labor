import React, { useMemo, useState } from 'react';
import { db, storage } from '../firebaseConfig';
import { updateDoc, doc } from 'firebase/firestore';
import { normalizePhotosFromDoc, buildPhotoFields } from '../utils/photoHelpers';
import { getQrValue, getQrImageUrl } from '../utils/qrHelpers';
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

function Events() {
  const { query, add, update, remove } = useFirestoreCollection(
    'events',
    mapEvent,
    {
      afterAdd: async (id, data) => {
        if (!data.qrCode) {
          await updateDoc(doc(db, 'events', id), { qrCode: id });
        }
      },
    },
  );

  const [showForm,     setShowForm]     = useState(false);
  const [editingId,    setEditingId]    = useState(null);
  const [mutateError,  setMutateError]  = useState(null);
  const [deleteDialog, setDeleteDialog] = useState({ open: false, id: null });
  const [formData,     setFormData]     = useState(EMPTY_FORM);
  const [search,       setSearch]       = useState('');

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
        qrCode:      event.qrCode      || '',
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
      qrCode:      safeString(formData.qrCode),
      points:      Number(formData.points || 20),
    };
    try {
      if (editingId) {
        await update.mutateAsync({
          id: editingId,
          data: { ...cleanData, qrCode: cleanData.qrCode || editingId },
        });
      } else {
        await add.mutateAsync(cleanData);
      }
      await commitRemovals();
      closeEditor();
    } catch {
      setMutateError('Hiba a mentéskor');
    }
  };

  const confirmDelete = async () => {
    if (!deleteDialog.id) return;
    try {
      await remove.mutateAsync(deleteDialog.id);
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

  const isBusy = uploading || add.isPending || update.isPending;

  const visibleEvents = events.filter((event) => {
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
              <button className="editor-close" onClick={closeEditor}>x</button>
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
                  <label>QR-kód</label>
                  <input
                    type="text"
                    value={formData.qrCode}
                    onChange={setField('qrCode')}
                    placeholder="ha üres, a dokumentum azonosítója lesz"
                  />
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
          const qrValue = getQrValue(event);
          return (
            <div key={event.id} className="card">
              <h3>{event.name || 'Nincs név'}</h3>
              {event.date     && <p><strong>Dátum:</strong> {event.date}</p>}
              {event.location && <p><strong>Helyszín:</strong> {event.location}</p>}
              <p><strong>Pont:</strong> {event.points}</p>
              {event.imageUrl && (
                <img src={event.imageUrl} alt={event.name} loading="lazy" className="content-cover" />
              )}
              <img
                src={getQrImageUrl(qrValue)}
                alt={`QR ${event.name}`}
                loading="lazy"
                className="content-qr"
              />
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
