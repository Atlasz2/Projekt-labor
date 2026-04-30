import React, { useMemo, useState } from 'react';
import { storage } from '../firebaseConfig';
import { normalizePhotosFromDoc, buildPhotoFields } from '../utils/photoHelpers';
import { safeString } from '../utils/safeString';
import { useFirestoreCollection } from '../hooks/useFirestoreCollection';
import { usePhotoManager } from '../hooks/usePhotoManager';
import ConfirmDialog from '../components/ConfirmDialog';
import PhotoGrid from '../components/PhotoGrid';
import '../styles/Content.css';

const EMPTY_FORM = {
  name:          '',
  type:          'hotel',
  pricePerNight: '',
  capacity:      '',
  description:   '',
};

const mapAccommodation = (docSnap) => {
  const d = docSnap.data();
  const normalized = normalizePhotosFromDoc(d);
  return {
    id:            docSnap.id,
    name:          safeString(d.name),
    type:          safeString(d.type) || 'hotel',
    pricePerNight: safeString(d.pricePerNight),
    capacity:      safeString(d.capacity),
    description:   safeString(d.description),
    photos:        normalized,
    imageUrl:      normalized[0] || '',
  };
};

function Accommodations() {
  const { query, add, update, remove } = useFirestoreCollection(
    'accommodations',
    mapAccommodation,
  );

  const [showForm,     setShowForm]     = useState(false);
  const [editingId,    setEditingId]    = useState(null);
  const [mutateError,  setMutateError]  = useState(null);
  const [deleteDialog, setDeleteDialog] = useState({ open: false, id: null });
  const [formData,     setFormData]     = useState(EMPTY_FORM);

  const { photos, uploading, uploadFeedback, upload, remove: removePhoto,
          reset: resetPhotos, commitRemovals } =
    usePhotoManager({ storage, folder: 'content-images' });

  const accommodations = query.data ?? [];

  const subtitle = useMemo(
    () => `${accommodations.length} szallas - kepfeltoltes tamogatva`,
    [accommodations.length],
  );

  const openEditor = (item = null) => {
    if (item) {
      setEditingId(item.id);
      setFormData({
        name:          item.name          || '',
        type:          item.type          || 'hotel',
        pricePerNight: item.pricePerNight || '',
        capacity:      item.capacity      || '',
        description:   item.description   || '',
      });
      resetPhotos(item.photos || (item.imageUrl ? [item.imageUrl] : []));
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
      name:          safeString(formData.name),
      type:          safeString(formData.type),
      pricePerNight: safeString(formData.pricePerNight),
      capacity:      safeString(formData.capacity),
      description:   safeString(formData.description),
      ...buildPhotoFields(photos),
    };
    try {
      if (editingId) {
        await update.mutateAsync({ id: editingId, data: cleanData });
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
        <h1>Szallasok</h1>
        <p>{subtitle}</p>
      </div>

      {mutateError && <div className="error-message">{mutateError}</div>}

      <button className="btn-primary" onClick={() => openEditor()}>
        + Uj szallas
      </button>

      {showForm && (
        <div
          className="editor-overlay"
          onClick={(e) => e.target === e.currentTarget && closeEditor()}
        >
          <div className="editor-modal">
            <div className="editor-header">
              <div>
                <p className="editor-kicker">Szallas szerkeszto</p>
                <h2>{editingId ? 'Szallas frissitese' : 'Uj szallas'}</h2>
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
                    <label>Tipus</label>
                    <select value={formData.type} onChange={setField('type')}>
                      <option value="hotel">Hotel</option>
                      <option value="guesthouse">Vendeghaz</option>
                      <option value="apartment">Apartman</option>
                      <option value="campsite">Kemping</option>
                    </select>
                  </div>
                  <div className="editor-field">
                    <label>Kapacitas</label>
                    <input type="number" min="1" value={formData.capacity} onChange={setField('capacity')} />
                  </div>
                </div>
                <div className="editor-field">
                  <label>Ar / ejszaka</label>
                  <input type="text" value={formData.pricePerNight} onChange={setField('pricePerNight')} />
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
                <button type="button" className="btn-secondary" onClick={closeEditor}>Megse</button>
                <button type="submit" className="btn-primary" disabled={isBusy}>
                  {isBusy ? 'Folyamatban...' : editingId ? 'Frissites' : 'Mentes'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      <div className="cards-grid">
        {accommodations.map((acc) => (
          <div key={acc.id} className="card">
            <h3>{acc.name || 'Nincs nev'}</h3>
            {acc.imageUrl && (
              <img src={acc.imageUrl} alt={acc.name} loading="lazy" className="content-cover" />
            )}
            {acc.type          && <p><strong>Tipus:</strong> {acc.type}</p>}
            {acc.pricePerNight && <p><strong>Ar:</strong> {acc.pricePerNight}</p>}
            {acc.capacity      && <p><strong>Kapacitas:</strong> {acc.capacity}</p>}
            {acc.description   && <p>{acc.description}</p>}
            <div className="card-actions">
              <button className="btn-edit"   onClick={() => openEditor(acc)}>Szerkesztes</button>
              <button className="btn-delete" onClick={() => setDeleteDialog({ open: true, id: acc.id })}>Torles</button>
            </div>
          </div>
        ))}
      </div>

      <ConfirmDialog
        open={deleteDialog.open}
        title="Szallas torlese"
        message="Biztosan torlod ezt a szallast?"
        confirmText="Torles"
        onClose={() => setDeleteDialog({ open: false, id: null })}
        onConfirm={confirmDelete}
      />
    </div>
  );
}

export default Accommodations;
