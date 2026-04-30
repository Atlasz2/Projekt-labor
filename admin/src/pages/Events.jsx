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

  const { photos, uploading, uploadFeedback, upload, remove: removePhoto,
          reset: resetPhotos, commitRemovals } =
    usePhotoManager({ storage, folder: 'content-images' });

  const events = query.data ?? [];

  const subtitle = useMemo(
    () => `${events.length} rendezveny - QR pecset es foto tamogatas`,
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
      setMutateError('Hiba a menteskor');
    }
  };

  const confirmDelete = async () => {
    if (!deleteDialog.id) return;
    try {
      await remove.mutateAsync(deleteDialog.id);
      setDeleteDialog({ open: false, id: null });
    } catch {
      setMutateError('Hiba a torleskor');
      setDeleteDialog({ open: false, id: null });
    }
  };

  if (query.isLoading) return <p>Betoltes...</p>;
  if (query.isError)   return <p className="error-message">Hiba az adatok betoltesekor.</p>;

  const isBusy = uploading || add.isPending || update.isPending;

  return (
    <div className="content-page">
      <div className="page-header">
        <h1>Rendezvenyek</h1>
        <p>{subtitle}</p>
      </div>

      {mutateError && <div className="error-message">{mutateError}</div>}

      <button className="btn-primary" onClick={() => openEditor()}>
        + Uj rendezveny
      </button>

      {showForm && (
        <div
          className="editor-overlay"
          onClick={(e) => e.target === e.currentTarget && closeEditor()}
        >
          <div className="editor-modal">
            <div className="editor-header">
              <div>
                <p className="editor-kicker">Rendezveny szerkeszto</p>
                <h2>{editingId ? 'Rendezveny frissitese' : 'Uj rendezveny'}</h2>
              </div>
              <button className="editor-close" onClick={closeEditor}>x</button>
            </div>

            <form onSubmit={handleSubmit} className="editor-grid">
              {mutateError && <div className="error-message editor-error">{mutateError}</div>}

              <div className="editor-main">
                <div className="editor-field">
                  <label>Nev *</label>
                  <input type="text" value={formData.name} onChange={setField('name')} required />
                </div>
                <div className="editor-row">
                  <div className="editor-field">
                    <label>Datum *</label>
                    <input type="date" value={formData.date} onChange={setField('date')} required />
                  </div>
                  <div className="editor-field">
                    <label>Pont</label>
                    <input type="number" min="0" value={formData.points} onChange={setField('points')} />
                  </div>
                </div>
                <div className="editor-field">
                  <label>Helyszin</label>
                  <input type="text" value={formData.location} onChange={setField('location')} />
                </div>
                <div className="editor-field">
                  <label>QR kod</label>
                  <input
                    type="text"
                    value={formData.qrCode}
                    onChange={setField('qrCode')}
                    placeholder="ha ures, doc ID lesz"
                  />
                </div>
                <div className="editor-field">
                  <label>Leiras</label>
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
                  Megse
                </button>
                <button type="submit" className="btn-primary" disabled={isBusy}>
                  {isBusy ? 'Folyamatban...' : editingId ? 'Frissites' : 'Mentes'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      <div className="cards-grid">
        {events.map((event) => {
          const qrValue = getQrValue(event);
          return (
            <div key={event.id} className="card">
              <h3>{event.name || 'Nincs nev'}</h3>
              {event.date     && <p><strong>Datum:</strong> {event.date}</p>}
              {event.location && <p><strong>Helyszin:</strong> {event.location}</p>}
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
                <button className="btn-edit"   onClick={() => openEditor(event)}>Szerkesztes</button>
                <button className="btn-delete" onClick={() => setDeleteDialog({ open: true, id: event.id })}>Torles</button>
              </div>
            </div>
          );
        })}
      </div>

      <ConfirmDialog
        open={deleteDialog.open}
        title="Rendezveny torlese"
        message="Biztosan torlod ezt a rendezvenyt?"
        confirmText="Torles"
        onClose={() => setDeleteDialog({ open: false, id: null })}
        onConfirm={confirmDelete}
      />
    </div>
  );
}

export default Events;
