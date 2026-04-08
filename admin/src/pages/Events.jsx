import React, { useEffect, useMemo, useState } from "react";
import { db, storage } from "../firebaseConfig";
import { collection, addDoc, updateDoc, deleteDoc, getDocs, doc } from "firebase/firestore";
import { uploadImageWithFallback } from '../utils/imageUpload';
import "../styles/Content.css";
import { safeString } from "../utils/safeString";
import ConfirmDialog from "../components/ConfirmDialog";

const EMPTY_FORM = {
  name: "",
  date: "",
  description: "",
  location: "",
  photos: [],
  qrCode: "",
  points: 20,
};

const getQrValue = (event) => event.qrCode || event.id;
const getQrImageUrl = (value, size = 140) => {
  const data = encodeURIComponent(value || "");
  return `https://api.qrserver.com/v1/create-qr-code/?size=${size}x${size}&data=${data}`;
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
function Events() {
  const [events, setEvents] = useState([]);
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [deleteDialog, setDeleteDialog] = useState({ open: false, id: null });
  const [uploading, setUploading] = useState(false);
  const [uploadFeedback, setUploadFeedback] = useState({ type: "idle", text: "" });
  const [formData, setFormData] = useState(EMPTY_FORM);

  useEffect(() => {
    fetchEvents();
  }, []);

  const headerSubtitle = useMemo(
    () => `${events.length} rendezvény • QR pecsét és fotó támogatás`,
    [events.length],
  );

  const fetchEvents = async () => {
    try {
      setLoading(true);
      setError(null);
      const snapshot = await getDocs(collection(db, "events"));
      const data = snapshot.docs.map((item) => {
        const docData = item.data();
        const rawPhotos = Array.isArray(docData.photos) ? docData.photos.map(p => typeof p === "string" ? p : p?.url).filter(Boolean) : [];
        const rawPhotoUrls = Array.isArray(docData.photoUrls) ? docData.photoUrls.filter(Boolean) : [];
        const rawUrl = safeString(docData.imageUrl);
        const photos = [...new Set([...rawPhotos, ...rawPhotoUrls, ...(rawUrl ? [rawUrl] : [])])].slice(0, 6);

        return {
          id: item.id,
          name: safeString(docData.name),
          date: safeString(docData.date),
          description: safeString(docData.description),
          location: safeString(docData.location),
          photos,
          imageUrl: photos[0] || "",
          qrCode: safeString(docData.qrCode),
          points: Number(docData.points || 20),
        };
      });
      setEvents(data);
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
        date: safeString(formData.date),
        description: safeString(formData.description),
        location: safeString(formData.location),
        ...buildPhotoFields(formData.photos),
        qrCode: safeString(formData.qrCode),
        points: Number(formData.points || 20),
      };

      if (editingId) {
        await updateDoc(doc(db, "events", editingId), {
          ...cleanData,
          qrCode: cleanData.qrCode || editingId,
        });
      } else {
        const created = await addDoc(collection(db, "events"), cleanData);
        if (!cleanData.qrCode) {
          await updateDoc(doc(db, "events", created.id), { qrCode: created.id });
        }
      }

      closeEditor();
      fetchEvents();
    } catch {
      setError("Hiba a mentéskor");
    }
  };

  const handleEdit = (event) => {
    setEditingId(event.id);
    setFormData({
      name: event.name || "",
      date: event.date || "",
      description: event.description || "",
      location: event.location || "",
      photos: event.photos || (event.imageUrl ? [event.imageUrl] : []),
      qrCode: event.qrCode || "",
      points: event.points || 20,
    });
    setShowForm(true);
  };

  const confirmDelete = async () => {
    if (!deleteDialog.id) return;
    try {
      await deleteDoc(doc(db, "events", deleteDialog.id));
      setDeleteDialog({ open: false, id: null });
      fetchEvents();
    } catch {
      setError("Hiba a törléskor");
      setDeleteDialog({ open: false, id: null });
    }
  };

  if (loading) return <p>Betöltés...</p>;

  return (
    <div className="content-page">
      <div className="page-header">
        <h1>Rendezvények</h1>
        <p>{headerSubtitle}</p>
      </div>

      {error && <div className="error-message">{error}</div>}

      <button className="btn-primary" onClick={() => setShowForm(true)}>
        + Új rendezvény
      </button>

      {showForm && (
        <div className="editor-overlay" onClick={(e) => e.target === e.currentTarget && closeEditor()}>
          <div className="editor-modal">
            <div className="editor-header">
              <div>
                <p className="editor-kicker">Rendezvény szerkesztő</p>
                <h2>{editingId ? "Rendezvény frissítése" : "Új rendezvény"}</h2>
              </div>
              <button className="editor-close" onClick={closeEditor}>✕</button>
            </div>

            <form onSubmit={handleSubmit} className="editor-grid">
              {error && <div className="error-message editor-error">{error}</div>}
              <div className="editor-main">
                <div className="editor-field">
                  <label>Név *</label>
                  <input type="text" name="name" value={formData.name} onChange={(e) => setFormData((prev) => ({ ...prev, name: e.target.value }))} required />
                </div>
                <div className="editor-row">
                  <div className="editor-field">
                    <label>Dátum *</label>
                    <input type="date" name="date" value={formData.date} onChange={(e) => setFormData((prev) => ({ ...prev, date: e.target.value }))} required />
                  </div>
                  <div className="editor-field">
                    <label>Pont</label>
                    <input type="number" min="0" name="points" value={formData.points} onChange={(e) => setFormData((prev) => ({ ...prev, points: e.target.value }))} />
                  </div>
                </div>
                <div className="editor-field">
                  <label>Helyszín</label>
                  <input type="text" name="location" value={formData.location} onChange={(e) => setFormData((prev) => ({ ...prev, location: e.target.value }))} />
                </div>
                <div className="editor-field">
                  <label>QR kód</label>
                  <input type="text" name="qrCode" value={formData.qrCode} onChange={(e) => setFormData((prev) => ({ ...prev, qrCode: e.target.value }))} placeholder="ha üres, doc ID lesz" />
                </div>
                <div className="editor-field">
                  <label>Leírás</label>
                  <textarea rows="4" name="description" value={formData.description} onChange={(e) => setFormData((prev) => ({ ...prev, description: e.target.value }))} />
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
        {events.map((event) => {
          const qrValue = getQrValue(event);
          return (
            <div key={event.id} className="card">
              <h3>{event.name || "Nincs név"}</h3>
              {event.date && <p><strong>Dátum:</strong> {event.date}</p>}
              {event.location && <p><strong>Helyszín:</strong> {event.location}</p>}
              <p><strong>Pont:</strong> {event.points}</p>
              {event.imageUrl && <img src={event.imageUrl} alt={event.name} loading="lazy" className="content-cover" />}
              <img src={getQrImageUrl(qrValue)} alt={`QR ${event.name}`} loading="lazy" className="content-qr" />
              {event.description && <p>{event.description}</p>}
              <div className="card-actions">
                <button className="btn-edit" onClick={() => handleEdit(event)}>Szerkesztés</button>
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
