import React, { useMemo, useState } from 'react';
import { storage } from '../firebaseConfig';
import { normalizePhotosFromDoc, buildPhotoFields } from '../utils/photoHelpers';
import { safeString } from '../utils/safeString';
import { useFirestoreCollection } from '../hooks/useFirestoreCollection';
import { usePhotoManager } from '../hooks/usePhotoManager';
import ConfirmDialog from '../components/ConfirmDialog';
import PhotoGrid from '../components/PhotoGrid';
import StateCard from '../components/StateCard';
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
  const [search, setSearch] = useState('');

  const subtitle = useMemo(
    () => `${restaurants.length} vendéglátóhely · képfeltöltés támogatással`,
    [restaurants.length],
  );

  const visibleItems = restaurants.filter((item) => {
    const q = search.trim().toLowerCase();
    if (!q) return true;
    return [item.name, item.type, item.cuisine, item.description]
      .some((field) => field?.toLowerCase().includes(q));
  });

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
        icon="🍽️"
        title="Vendéglátóhelyek betöltése..."
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

  return (
    <div className="content-page">
      <div className="page-header">
        <h1>Vendéglátóhelyek</h1>
        <p>{subtitle}</p>
      </div>

      {mutateError && <div className="error-message">{mutateError}</div>}

      <div className="content-toolbar">
        <button className="btn-primary" onClick={() => openEditor()}>
          + Új vendéglátóhely
        </button>
        {restaurants.length > 0 && (
          <>
            <input
              className="content-search"
              type="search"
              placeholder="🔍 Keresés név, kategória vagy leírás alapján..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
            <span className="content-search-count">{visibleItems.length} / {restaurants.length}</span>
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
                <p className="editor-kicker">Vendéglátóhely szerkesztő</p>
                <h2>{editingId ? 'Vendéglátóhely frissítése' : 'Új vendéglátóhely'}</h2>
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
                    <label>Kategória</label>
                    <select value={formData.type} onChange={setField('type')}>
                      <option value="hungarian">Magyar konyha</option>
                      <option value="fish">Halételek</option>
                      <option value="cafe">Kávézó</option>
                      <option value="pizzeria">Pizzéria</option>
                      <option value="icecream">Fagylaltozó</option>
                      <option value="bar">Bár</option>
                    </select>
                  </div>
                  <div className="editor-field">
                    <label>Árszint</label>
                    <input type="text" value={formData.priceRange} onChange={setField('priceRange')} />
                  </div>
                </div>
                <div className="editor-field">
                  <label>Konyha típusa</label>
                  <input type="text" value={formData.cuisine} onChange={setField('cuisine')} />
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
                <button type="button" className="btn-secondary" onClick={closeEditor}>Mégse</button>
                <button type="submit" className="btn-primary" disabled={isBusy}>
                  {isBusy ? 'Folyamatban...' : editingId ? 'Frissítés' : 'Mentés'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      <div className="cards-grid">
        {restaurants.length === 0 && (
          <div className="content-empty">
            <span className="empty-icon" aria-hidden="true">🍽️</span>
            <h3>Még nincs vendéglátóhely</h3>
            <p>Add hozzá az első helyet a fenti gombbal.</p>
          </div>
        )}
        {restaurants.length > 0 && visibleItems.length === 0 && (
          <div className="content-empty">
            <span className="empty-icon" aria-hidden="true">🔎</span>
            <h3>Nincs találat</h3>
            <p>Próbálj másik kulcsszót, vagy töröld a keresést.</p>
          </div>
        )}
        {visibleItems.map((rest) => (
          <div key={rest.id} className="card">
            <h3>{rest.name || 'Nincs név'}</h3>
            {rest.imageUrl && (
              <img src={rest.imageUrl} alt={rest.name} loading="lazy" className="content-cover" />
            )}
            {rest.type        && <p><strong>Kategória:</strong> {rest.type}</p>}
            {rest.cuisine     && <p><strong>Konyha:</strong> {rest.cuisine}</p>}
            {rest.priceRange  && <p><strong>Árszint:</strong> {rest.priceRange}</p>}
            {rest.description && <p>{rest.description}</p>}
            <div className="card-actions">
              <button className="btn-edit"   onClick={() => openEditor(rest)}>Szerkesztés</button>
              <button className="btn-delete" onClick={() => setDeleteDialog({ open: true, id: rest.id })}>Törlés</button>
            </div>
          </div>
        ))}
      </div>

      <ConfirmDialog
        open={deleteDialog.open}
        title="Vendéglátóhely törlése"
        message="Biztosan törlöd ezt a vendéglátóhelyet?"
        confirmText="Törlés"
        onClose={() => setDeleteDialog({ open: false, id: null })}
        onConfirm={confirmDelete}
      />
    </div>
  );
}

export default Restaurants;
