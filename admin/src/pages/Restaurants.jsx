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
  name:        '',
  type:        'hungarian',
  cuisine:     '',
  priceRange:  '',
  description: '',
};

const mapRestaurant = (docSnap) => {
  const d = docSnap.data();
  const normalized = normalizePhotosFromDoc(d);
  return {
    id:          docSnap.id,
    name:        safeString(d.name),
    type:        safeString(d.type) || 'hungarian',
    cuisine:     safeString(d.cuisine),
    priceRange:  safeString(d.priceRange),
    description: safeString(d.description),
    photos:      normalized,
    imageUrl:    normalized[0] || '',
  };
};

function Restaurants() {
  const { query, add, update, remove } = useFirestoreCollection(
    'restaurants',
    mapRestaurant,
  );

  const [showForm,     setShowForm]     = useState(false);
  const [editingId,    setEditingId]    = useState(null);
  const [mutateError,  setMutateError]  = useState(null);
  const [deleteDialog, setDeleteDialog] = useState({ open: false, id: null });
  const [formData,     setFormData]     = useState(EMPTY_FORM);

  const { photos, uploading, uploadFeedback, upload, remove: removePhoto,
          reset: resetPhotos, commitRemovals } =
    usePhotoManager({ storage, folder: 'content-images' });

  const restaurants = query.data ?? [];

  const subtitle = useMemo(
    () => `${restaurants.length} vendeglatohely - kepfeltoltes tamogatva`,
    [restaurants.length],
  );

  const openEditor = (item = null) => {
    if (item) {
      setEditingId(item.id);
      setFormData({
        name:        item.name        || '',
        type:        item.type        || 'hungarian',
        cuisine:     item.cuisine     || '',
        priceRange:  item.priceRange  || '',
        description: item.description || '',
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
      name:        safeString(formData.name),
      type:        safeString(formData.type),
      cuisine:     safeString(formData.cuisine),
      priceRange:  safeString(formData.priceRange),
      description: safeString(formData.description),
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
        <h1>Vendeglatohelyek</h1>
        <p>{subtitle}</p>
      </div>

      {mutateError && <div className="error-message">{mutateError}</div>}

      <button className="btn-primary" onClick={() => openEditor()}>
        + Uj vendeglatohely
      </button>

      {showForm && (
        <div
          className="editor-overlay"
          onClick={(e) => e.target === e.currentTarget && closeEditor()}
        >
          <div className="editor-modal">
            <div className="editor-header">
              <div>
                <p className="editor-kicker">Vendeglatohelyek szerkeszto</p>
                <h2>{editingId ? 'Vendeglatohely frissitese' : 'Uj vendeglatohely'}</h2>
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
                    <label>Kategoria</label>
                    <select value={formData.type} onChange={setField('type')}>
                      <option value="hungarian">Magyar konyha</option>
                      <option value="fish">Haleitelek</option>
                      <option value="cafe">Kavero</option>
                      <option value="pizzeria">Pizzeria</option>
                      <option value="icecream">Fagylaltozo</option>
                      <option value="bar">Bar</option>
                    </select>
                  </div>
                  <div className="editor-field">
                    <label>Arszint</label>
                    <input type="text" value={formData.priceRange} onChange={setField('priceRange')} />
                  </div>
                </div>
                <div className="editor-field">
                  <label>Konyha tipusa</label>
                  <input type="text" value={formData.cuisine} onChange={setField('cuisine')} />
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
        {restaurants.map((rest) => (
          <div key={rest.id} className="card">
            <h3>{rest.name || 'Nincs nev'}</h3>
            {rest.imageUrl && (
              <img src={rest.imageUrl} alt={rest.name} loading="lazy" className="content-cover" />
            )}
            {rest.type        && <p><strong>Kategoria:</strong> {rest.type}</p>}
            {rest.cuisine     && <p><strong>Konyha:</strong> {rest.cuisine}</p>}
            {rest.priceRange  && <p><strong>Arszint:</strong> {rest.priceRange}</p>}
            {rest.description && <p>{rest.description}</p>}
            <div className="card-actions">
              <button className="btn-edit"   onClick={() => openEditor(rest)}>Szerkesztes</button>
              <button className="btn-delete" onClick={() => setDeleteDialog({ open: true, id: rest.id })}>Torles</button>
            </div>
          </div>
        ))}
      </div>

      <ConfirmDialog
        open={deleteDialog.open}
        title="Vendeglatohely torlese"
        message="Biztosan torlod ezt a vendeglatohelyet?"
        confirmText="Torles"
        onClose={() => setDeleteDialog({ open: false, id: null })}
        onConfirm={confirmDelete}
      />
    </div>
  );
}

export default Restaurants;
