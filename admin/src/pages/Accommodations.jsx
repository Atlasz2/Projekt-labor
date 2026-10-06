import React, { useMemo, useState } from 'react';
import { storage } from '../firebaseConfig';
import { normalizePhotosFromDoc, buildPhotoFields } from '../utils/photoHelpers';
import { safeString } from '../utils/safeString';
import { normalizeWebsite, websiteLabel } from '../utils/website';
import { useFirestoreCollection } from '../hooks/useFirestoreCollection';
import { usePhotoManager } from '../hooks/usePhotoManager';
import ConfirmDialog from '../components/ConfirmDialog';
import PhotoGrid from '../components/PhotoGrid';
import StateCard from '../components/StateCard';
import '../styles/Content.css';

const EMPTY_FORM = {
  name:          '',
  address:       '',
  type:          'hotel',
  pricePerNight: '',
  capacity:      '',
  description:   '',
  website:       '',
  phone:         '',
};

const TYPE_LABELS = {
  hotel: 'Hotel',
  guesthouse: 'Vendégház',
  apartment: 'Apartman',
  campsite: 'Kemping',
};

const mapAccommodation = (docSnap) => {
  const d = docSnap.data();
  const normalized = normalizePhotosFromDoc(d);
  return {
    id:            docSnap.id,
    name:          safeString(d.name),
    address:       safeString(d.address),
    type:          safeString(d.type) || 'hotel',
    pricePerNight: safeString(d.pricePerNight),
    capacity:      safeString(d.capacity),
    description:   safeString(d.description),
    website:       safeString(d.website),
    phone:         safeString(d.phone),
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
  const [search, setSearch] = useState('');

  const subtitle = useMemo(
    () => `${accommodations.length} szállás · képfeltöltés támogatással`,
    [accommodations.length],
  );

  const visibleItems = accommodations.filter((item) => {
    const q = search.trim().toLowerCase();
    if (!q) return true;
    return [item.name, item.address, item.type, item.description]
      .some((field) => field?.toLowerCase().includes(q));
  });

  const openEditor = (item = null) => {
    if (item) {
      setEditingId(item.id);
      setFormData({
        name:          item.name          || '',
        address:       item.address       || '',
        type:          item.type          || 'hotel',
        pricePerNight: item.pricePerNight || '',
        capacity:      item.capacity      || '',
        description:   item.description   || '',
        website:       item.website       || '',
        phone:         item.phone         || '',
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
    const website = normalizeWebsite(formData.website);
    if (website === null) {
      setMutateError('A weboldal címe érvénytelen (pl. www.pelda.hu).');
      return;
    }
    const cleanData = {
      name:          safeString(formData.name),
      address:       safeString(formData.address),
      type:          safeString(formData.type),
      pricePerNight: safeString(formData.pricePerNight),
      capacity:      safeString(formData.capacity),
      description:   safeString(formData.description),
      website,
      phone:         safeString(formData.phone),
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
        icon="🏠"
        title="Szállások betöltése..."
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
        <h1>Szállások</h1>
        <p>{subtitle}</p>
      </div>

      {mutateError && <div className="error-message">{mutateError}</div>}

      <div className="content-toolbar">
        <button className="btn-primary" onClick={() => openEditor()}>
          + Új szállás
        </button>
        {accommodations.length > 0 && (
          <>
            <input
              className="content-search"
              type="search"
              placeholder="🔍 Keresés név, típus vagy leírás alapján..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
            <span className="content-search-count">{visibleItems.length} / {accommodations.length}</span>
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
                <p className="editor-kicker">Szállás szerkesztő</p>
                <h2>{editingId ? 'Szállás frissítése' : 'Új szállás'}</h2>
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
                <div className="editor-field">
                  <label>Cím</label>
                  <input
                    type="text"
                    value={formData.address}
                    onChange={setField('address')}
                    placeholder="pl. Nagyvázsony, Kinizsi u. 12."
                  />
                </div>
                <div className="editor-row">
                  <div className="editor-field">
                    <label>Típus</label>
                    <select value={formData.type} onChange={setField('type')}>
                      <option value="hotel">Hotel</option>
                      <option value="guesthouse">Vendégház</option>
                      <option value="apartment">Apartman</option>
                      <option value="campsite">Kemping</option>
                    </select>
                  </div>
                  <div className="editor-field">
                    <label>Kapacitás</label>
                    <input type="number" min="1" value={formData.capacity} onChange={setField('capacity')} />
                  </div>
                </div>
                <div className="editor-field">
                  <label>Ár / éjszaka</label>
                  <input type="text" value={formData.pricePerNight} onChange={setField('pricePerNight')} />
                </div>
                <div className="editor-row">
                  <div className="editor-field">
                    <label>Telefon</label>
                    <input
                      type="tel"
                      value={formData.phone}
                      onChange={setField('phone')}
                      placeholder="pl. +36 88 123 456"
                    />
                  </div>
                  <div className="editor-field">
                    <label>Weboldal</label>
                    <input
                      type="text"
                      inputMode="url"
                      value={formData.website}
                      onChange={setField('website')}
                      placeholder="pl. www.pelda.hu"
                    />
                  </div>
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
        {accommodations.length === 0 && (
          <div className="content-empty">
            <span className="empty-icon" aria-hidden="true">🏠</span>
            <h3>Még nincs szállás</h3>
            <p>Add hozzá az első szálláshelyet a fenti gombbal.</p>
          </div>
        )}
        {accommodations.length > 0 && visibleItems.length === 0 && (
          <div className="content-empty">
            <span className="empty-icon" aria-hidden="true">🔎</span>
            <h3>Nincs találat</h3>
            <p>Próbálj másik kulcsszót, vagy töröld a keresést.</p>
          </div>
        )}
        {visibleItems.map((acc) => (
          <div key={acc.id} className="card">
            <h3>{acc.name || 'Nincs név'}</h3>
            {acc.imageUrl && (
              <img src={acc.imageUrl} alt={acc.name} loading="lazy" className="content-cover" />
            )}
            {acc.address       && <p><strong>Cím:</strong> {acc.address}</p>}
            {acc.type          && <p><strong>Típus:</strong> {TYPE_LABELS[acc.type] || acc.type}</p>}
            {acc.pricePerNight && <p><strong>Ár:</strong> {acc.pricePerNight}</p>}
            {acc.capacity      && <p><strong>Kapacitás:</strong> {acc.capacity}</p>}
            {acc.description   && <p>{acc.description}</p>}
            {acc.phone && <p><strong>Telefon:</strong> {acc.phone}</p>}
            {acc.website && (
              <p>
                <strong>Weboldal:</strong>{' '}
                <a href={acc.website} className="card-link" target="_blank" rel="noopener noreferrer">{websiteLabel(acc.website)}</a>
              </p>
            )}
            <div className="card-actions">
              <button className="btn-edit"   onClick={() => openEditor(acc)}>Szerkesztés</button>
              <button className="btn-delete" onClick={() => setDeleteDialog({ open: true, id: acc.id })}>Törlés</button>
            </div>
          </div>
        ))}
      </div>

      <ConfirmDialog
        open={deleteDialog.open}
        title="Szállás törlése"
        message="Biztosan törlöd ezt a szállást?"
        confirmText="Törlés"
        onClose={() => setDeleteDialog({ open: false, id: null })}
        onConfirm={confirmDelete}
      />
    </div>
  );
}

export default Accommodations;
