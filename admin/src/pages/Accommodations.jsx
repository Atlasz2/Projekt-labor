import React, { useEffect, useMemo, useState } from "react";
import { db, storage } from "../firebaseConfig";
import { collection, addDoc, updateDoc, deleteDoc, getDocs, doc } from "firebase/firestore";
import { uploadImageWithFallback } from '../utils/imageUpload';
import "../styles/Content.css";
import { safeString } from "../utils/safeString";
import ConfirmDialog from "../components/ConfirmDialog";

const EMPTY_FORM = {
  name: "",
  type: "hotel",
  pricePerNight: "",
  capacity: "",
  description: "",
  imageUrl: "",
};

const extractPrimaryImage = (data) => {
  const photos = data?.photos;
  if (Array.isArray(photos) && photos.length > 0) {
    const first = photos[0];
    if (typeof first === "string") return safeString(first);
    if (first && typeof first === "object") return safeString(first.url);
  }

  const photoUrls = data?.photoUrls;
  if (Array.isArray(photoUrls) && photoUrls.length > 0) {
    return safeString(photoUrls[0]);
  }

  return safeString(data?.imageUrl);
};

const buildPhotoFields = (photos) => {
  const urls = Array.isArray(photos) ? photos.filter(Boolean) : [];
  if (!urls.length) return { imageUrl: "", photoUrls: [], photos: [] };
  return { imageUrl: urls[0], photoUrls: urls, photos: urls.map(url => ({ url })) };
};
function Accommodations() {
  const [accommodations, setAccommodations] = useState([]);
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [uploading, setUploading] = useState(false);
  const [uploadFeedback, setUploadFeedback] = useState({ type: "idle", text: "" });
  const [deleteDialog, setDeleteDialog] = useState({ open: false, id: null });
  const [formData, setFormData] = useState(EMPTY_FORM);

  useEffect(() => {
    fetchAccommodations();
  }, []);

  const subtitle = useMemo(
    () => `${accommodations.length} szállás • képfeltöltés támogatva`,
    [accommodations.length],
  );

  const fetchAccommodations = async () => {
    try {
      setLoading(true);
      setError(null);
      const snapshot = await getDocs(collection(db, "accommodations"));
      const data = snapshot.docs.map((item) => {
        const d = item.data();
        const rawPhotos = Array.isArray(d.photos) ? d.photos.map(p => typeof p === "string" ? p : p?.url).filter(Boolean) : [];
        const rawPhotoUrls = Array.isArray(d.photoUrls) ? d.photoUrls.filter(Boolean) : [];
        const rawUrl = safeString(d.imageUrl);
        const photos = [...new Set([...rawPhotos, ...rawPhotoUrls, ...(rawUrl ? [rawUrl] : [])])].slice(0, 6);
        return {
          id: item.id,
          name: safeString(d.name),
          type: safeString(d.type) || "hotel",
          pricePerNight: safeString(d.pricePerNight),
          capacity: safeString(d.capacity),
          description: safeString(d.description),
          photos,
          imageUrl: photos[0] || "",
        };
      });
      setAccommodations(data);
    } catch {
      setError("Hiba az adatok betöltésekor");
    } finally {
      setLoading(false);
    }
  };

  const closeEditor = () => {
    setShowForm(false);
    setEditingId(null);
    setUploading(false);
    setFormData(EMPTY_FORM);
  };

  const handleImageUpload = async (file) => {
    if (!file) return;
    if (formData.photos.length >= 6) { setUploadFeedback({ type: "error", text: "Maximum 6 kép tölthető fel." }); return; }
    try {
      setError(null);
      setUploadFeedback({ type: "info", text: `Feltöltés: ${file.name}` });
      setUploading(true);
      const result = await uploadImageWithFallback({ file, storage, folder: "content-images" });
      setFormData((prev) => ({ ...prev, photos: [...prev.photos, result.url] }));
      setUploadFeedback({ type: "success", text: result.message });
    } catch (err) {
      const message = err?.message || "Kép feltöltése sikertelen";
      setUploadFeedback({ type: "error", text: message });
      setError(message);
    } finally {
      setUploading(false);
    }
  };

  const handleRemovePhoto = (index) => {
    setFormData((prev) => ({ ...prev, photos: prev.photos.filter((_, i) => i !== index) }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    try {
      setError(null);
      const cleanData = {
        name: safeString(formData.name),
        type: safeString(formData.type),
        pricePerNight: safeString(formData.pricePerNight),
        capacity: safeString(formData.capacity),
        description: safeString(formData.description),
        ...buildPhotoFields(formData.photos),
      };

      if (editingId) {
        await updateDoc(doc(db, "accommodations", editingId), cleanData);
      } else {
        await addDoc(collection(db, "accommodations"), cleanData);
      }

      closeEditor();
      fetchAccommodations();
    } catch {
      setError("Hiba a mentéskor");
    }
  };

  const handleEdit = (item) => {
    setEditingId(item.id);
    setFormData({
      name: item.name || "",
      type: item.type || "hotel",
      pricePerNight: item.pricePerNight || "",
      capacity: item.capacity || "",
      description: item.description || "",
      photos: item.photos || (item.imageUrl ? [item.imageUrl] : []),
    });
    setShowForm(true);
  };

  const confirmDelete = async () => {
    if (!deleteDialog.id) return;
    try {
      await deleteDoc(doc(db, "accommodations", deleteDialog.id));
      setDeleteDialog({ open: false, id: null });
      fetchAccommodations();
    } catch {
      setError("Hiba a törléskor");
      setDeleteDialog({ open: false, id: null });
    }
  };

  if (loading) return <p>Betöltés...</p>;

  return (
    <div className="content-page">
      <div className="page-header">
        <h1>Szállások</h1>
        <p>{subtitle}</p>
      </div>

      {error && <div className="error-message">{error}</div>}

      <button className="btn-primary" onClick={() => setShowForm(true)}>
        + Új szállás
      </button>

      {showForm && (
        <div className="editor-overlay" onClick={(e) => e.target === e.currentTarget && closeEditor()}>
          <div className="editor-modal">
            <div className="editor-header">
              <div>
                <p className="editor-kicker">Szállás szerkesztő</p>
                <h2>{editingId ? "Szállás frissítése" : "Új szállás"}</h2>
              </div>
              <button className="editor-close" onClick={closeEditor}>✕</button>
            </div>

            <form onSubmit={handleSubmit} className="editor-grid">
              {error && <div className="error-message editor-error">{error}</div>}
              <div className="editor-main">
                <div className="editor-field">
                  <label>Név *</label>
                  <input type="text" value={formData.name} onChange={(e) => setFormData((prev) => ({ ...prev, name: e.target.value }))} required />
                </div>
                <div className="editor-row">
                  <div className="editor-field">
                    <label>Típus</label>
                    <select value={formData.type} onChange={(e) => setFormData((prev) => ({ ...prev, type: e.target.value }))}>
                      <option value="hotel">Hotel</option>
                      <option value="guesthouse">Vendégház</option>
                      <option value="apartment">Apartman</option>
                      <option value="campsite">Kemping</option>
                    </select>
                  </div>
                  <div className="editor-field">
                    <label>Kapacitás</label>
                    <input type="number" min="1" value={formData.capacity} onChange={(e) => setFormData((prev) => ({ ...prev, capacity: e.target.value }))} />
                  </div>
                </div>
                <div className="editor-field">
                  <label>Ár / éjszaka</label>
                  <input type="text" value={formData.pricePerNight} onChange={(e) => setFormData((prev) => ({ ...prev, pricePerNight: e.target.value }))} />
                </div>
                <div className="editor-field">
                  <label>Leírás</label>
                  <textarea rows="4" value={formData.description} onChange={(e) => setFormData((prev) => ({ ...prev, description: e.target.value }))} />
                </div>
              </div>

              <div className="editor-side">
                <div className="editor-upload-box">
                  <label>Képek <span className="upload-count">{formData.photos.length}/6</span></label>
                  <div className="photo-grid">
                    {formData.photos.map((url, i) => (
                      <div key={i} className="photo-thumb">
                        <img src={url} alt="" />
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
                  {uploadFeedback.type !== "idle" && <p className={"upload-note upload-note-" + uploadFeedback.type}>{uploadFeedback.text}</p>}
                </div>
              </div>

              <div className="editor-actions">
                <button type="button" className="btn-secondary" onClick={closeEditor}>Mégse</button>
                <button type="submit" className="btn-primary" disabled={uploading}>{uploading ? "Feltöltés folyamatban..." : editingId ? "Frissítés" : "Mentés"}</button>
              </div>
            </form>
          </div>
        </div>
      )}

      <div className="cards-grid">
        {accommodations.map((acc) => (
          <div key={acc.id} className="card">
            <h3>{acc.name || "Nincs név"}</h3>
            {acc.imageUrl && <img src={acc.imageUrl} alt={acc.name} loading="lazy" className="content-cover" />}
            {acc.type && <p><strong>Típus:</strong> {acc.type}</p>}
            {acc.pricePerNight && <p><strong>Ár:</strong> {acc.pricePerNight}</p>}
            {acc.capacity && <p><strong>Kapacitás:</strong> {acc.capacity}</p>}
            {acc.description && <p>{acc.description}</p>}
            <div className="card-actions">
              <button className="btn-edit" onClick={() => handleEdit(acc)}>Szerkesztés</button>
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
