import React, { useState, useEffect, useCallback } from "react";
import { db } from "../firebaseConfig";
import { collection, getDocs, doc, updateDoc, deleteDoc, addDoc } from "firebase/firestore";
import "../styles/About.css";
import { safeString } from "../utils/safeString";
import ConfirmDialog from "../components/ConfirmDialog";
import { fileToOptimizedDataUrl } from "../utils/imageUpload";
import Snackbar from "@mui/material/Snackbar";
import Alert from "@mui/material/Alert";
import StateCard from "../components/StateCard";

const EMPTY_FORM = {
  year: "",
  title: "",
  description: "",
  imageUrl: "",
};

function About() {
  const [events, setEvents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [formData, setFormData] = useState(EMPTY_FORM);
  const [deleteDialog, setDeleteDialog] = useState({ open: false, id: null });
  const [imagePreview, setImagePreview] = useState("");
  const [uploadingImage, setUploadingImage] = useState(false);
  const [snack, setSnack] = useState({ open: false, msg: "", severity: "error" });

  const showMsg = useCallback((msg, severity = "error") => {
    setSnack({ open: true, msg, severity });
  }, []);

  const fetchEvents = useCallback(async () => {
    try {
      setLoading(true);
      const snapshot = await getDocs(collection(db, "about"));
      const data = snapshot.docs.map((item) => ({
        id: item.id,
        year: safeString(item.data().year),
        title: safeString(item.data().title),
        description: safeString(item.data().description),
        imageUrl: safeString(item.data().imageUrl ?? ""),
      }));
      data.sort((a, b) => (parseInt(a.year, 10) || 0) - (parseInt(b.year, 10) || 0));
      setEvents(data);
    } catch {
      showMsg("Hiba az adatok betöltésénél");
    } finally {
      setLoading(false);
    }
  }, [showMsg]);

  useEffect(() => {
    const timer = setTimeout(() => {
      void fetchEvents();
    }, 0);

    return () => clearTimeout(timer);
  }, [fetchEvents]);

  const resetEditor = () => {
    setShowForm(false);
    setEditingId(null);
    setFormData(EMPTY_FORM);
    setImagePreview("");
  };

  const openCreateForm = () => {
    setEditingId(null);
    setFormData(EMPTY_FORM);
    setImagePreview("");
    setShowForm(true);
  };

  const handleInputChange = (e) => {
    const { name, value } = e.target;
    setFormData((prev) => ({ ...prev, [name]: value }));
  };

  const handleImageChange = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploadingImage(true);
    try {
      const url = await fileToOptimizedDataUrl(file);
      setFormData((prev) => ({ ...prev, imageUrl: url }));
      setImagePreview(url);
    } catch (err) {
      showMsg(`Képfeltöltési hiba: ${err.message}`);
    } finally {
      setUploadingImage(false);
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    try {
      const cleanData = {
        year: safeString(formData.year),
        title: safeString(formData.title),
        description: safeString(formData.description),
        imageUrl: safeString(formData.imageUrl),
      };

      if (editingId) {
        await updateDoc(doc(db, "about", editingId), cleanData);
      } else {
        await addDoc(collection(db, "about"), cleanData);
      }

      resetEditor();
      showMsg(editingId ? "Esemény frissítve" : "Esemény hozzáadva", "success");
      await fetchEvents();
    } catch {
      showMsg("Hiba a mentéskor");
    }
  };

  const handleEdit = (event) => {
    setEditingId(event.id);
    setFormData({
      year: event.year,
      title: event.title,
      description: event.description,
      imageUrl: event.imageUrl ?? "",
    });
    setImagePreview(event.imageUrl ?? "");
    setShowForm(true);
  };

  const handleDelete = (id) => {
    setDeleteDialog({ open: true, id });
  };

  const confirmDelete = async () => {
    if (!deleteDialog.id) return;
    try {
      await deleteDoc(doc(db, "about", deleteDialog.id));
      setDeleteDialog({ open: false, id: null });
      showMsg("Esemény törölve", "success");
      await fetchEvents();
    } catch {
      showMsg("Hiba a törlésnél");
      setDeleteDialog({ open: false, id: null });
    }
  };

  if (loading) {
    return (
      <div className="content-page">
        <div className="page-header">
          <h1>🏛️ Nagyvázsony Története</h1>
          <p>Szerkeszd a település történeti eseményeit időrendben.</p>
        </div>
        <StateCard
          variant="loading"
          icon="📜"
          title="Történeti események betöltése..."
          description="Az idővonal elemei rendezés alatt állnak."
        />
      </div>
    );
  }

  return (
    <div className="content-page">
      <div className="page-header">
        <h1>🏛️ Nagyvázsony Története</h1>
        <p>Szerkeszd a település történeti eseményeit időrendben.</p>
      </div>

      {!showForm && (
        <button className="btn-primary" onClick={openCreateForm}>
          + Új esemény
        </button>
      )}

      {showForm && (
        <div className="about-editor-backdrop" onClick={resetEditor} role="presentation">
          <div
            aria-modal="true"
            className="about-editor-shell"
            onClick={(e) => e.stopPropagation()}
            role="dialog"
          >
            <div className="about-editor-header">
              <div>
                <p className="about-editor-kicker">Történeti szerkesztő</p>
                <h2>{editingId ? "Esemény szerkesztése" : "Új idővonali esemény"}</h2>
                <p>
                  Adj meg egy rövid, könnyen olvasható korszakbejegyzést, hogy a mobilos történeti
                  nézet is áttekinthető maradjon.
                </p>
              </div>
              <button className="about-editor-close" onClick={resetEditor} type="button">
                Bezárás
              </button>
            </div>

            <div className="about-editor-grid">
              <form className="about-editor-form" onSubmit={handleSubmit}>
                <section className="about-editor-section">
                  <div className="about-editor-section-head">
                    <span>1</span>
                    <div>
                      <h3>Alapadatok</h3>
                      <p>A címet, időszakot és szöveget a látogatók az idővonalon ebből látják.</p>
                    </div>
                  </div>

                  <div className="form-row">
                    <div className="form-group">
                      <label>Év/Időszak *</label>
                      <input
                        name="year"
                        onChange={handleInputChange}
                        placeholder="pl. 1543 vagy 1500-1600"
                        required
                        type="text"
                        value={formData.year}
                      />
                    </div>
                  </div>

                  <div className="form-group">
                    <label>Cím *</label>
                    <input
                      name="title"
                      onChange={handleInputChange}
                      placeholder="pl. Nagyvázsony vára építésének kezdete"
                      required
                      type="text"
                      value={formData.title}
                    />
                  </div>

                  <div className="form-group">
                    <label>Leírás</label>
                    <textarea
                      name="description"
                      onChange={handleInputChange}
                      placeholder="Részletes leírás az eseményről..."
                      rows="7"
                      value={formData.description}
                    />
                  </div>
                </section>

                <section className="about-editor-section">
                  <div className="about-editor-section-head">
                    <span>2</span>
                    <div>
                      <h3>Vizuális tartalom</h3>
                      <p>A kép a kártya vizuális fókusza lesz az admin és a mobil oldalon is.</p>
                    </div>
                  </div>

                  <div className="form-group">
                    <label>Kép (opcionális)</label>
                    <div className="about-img-upload-wrap">
                      {imagePreview ? (
                        <div className="about-img-preview">
                          <img alt="Előnézet" src={imagePreview} />
                          <button
                            className="about-img-remove"
                            onClick={() => {
                              setImagePreview("");
                              setFormData((prev) => ({ ...prev, imageUrl: "" }));
                            }}
                            type="button"
                          >
                            ✕
                          </button>
                        </div>
                      ) : (
                        <label className="about-img-dropzone" htmlFor="about-img-input">
                          <span className="about-img-icon">🖼</span>
                          <span>{uploadingImage ? "Feltöltés..." : "Kattints a képfeltöltéshez"}</span>
                          <small>Ajánlott széles kivágás, hogy mobilon is szépen jelenjen meg.</small>
                        </label>
                      )}
                      <input
                        accept="image/*"
                        disabled={uploadingImage}
                        id="about-img-input"
                        onChange={handleImageChange}
                        style={{ display: "none" }}
                        type="file"
                      />
                    </div>
                  </div>
                </section>

                <div className="form-actions about-editor-actions">
                  <button className="btn-primary" type="submit">
                    {editingId ? "Frissítés" : "Hozzáadás"}
                  </button>
                  <button className="btn-secondary" onClick={resetEditor} type="button">
                    Mégse
                  </button>
                </div>
              </form>

              <aside className="about-editor-preview-panel">
                <div className="about-editor-preview-card">
                  <p className="about-editor-preview-label">Előnézet</p>
                  <div className="about-editor-preview-media">
                    {imagePreview ? <img alt="Kártya előnézet" src={imagePreview} /> : <span>📜</span>}
                  </div>
                  <div className="about-editor-preview-body">
                    <span className="about-editor-preview-year">{formData.year || "Időszak"}</span>
                    <h3>{formData.title || "Történeti esemény címe"}</h3>
                    <p>
                      {formData.description ||
                        "Itt ellenőrizheted, hogyan hat együtt a cím, a kép és a bevezető szöveg az idővonal-kártyán."}
                    </p>
                  </div>
                </div>

                <div className="about-editor-tips">
                  <h4>Gyors tippek</h4>
                  <ul>
                    <li>Az első 1-2 mondat rögtön adja meg az esemény lényegét.</li>
                    <li>Hosszabb szöveg esetén bontsd jól követhető bekezdésekre.</li>
                    <li>Az időszak mezőben egy korszak vagy évintervallum is megadható.</li>
                  </ul>
                </div>
              </aside>
            </div>
          </div>
        </div>
      )}

      <div className="timeline">
        {events.length === 0 ? (
          <StateCard
            actionLabel="Új esemény hozzáadása"
            description="Indítsd el az oldalt egy első történeti bejegyzéssel, hogy a látogatók rögtön tartalmat lássanak."
            icon="🏛️"
            onAction={openCreateForm}
            title="Még nincs idővonali esemény"
          />
        ) : (
          events.map((event, idx) => (
            <div className="timeline-item" key={event.id}>
              <div className="timeline-marker">
                <div className="timeline-dot" />
                {idx < events.length - 1 && <div className="timeline-line" />}
              </div>
              <div className="timeline-content">
                <div className="timeline-year">{event.year}</div>
                {event.imageUrl && (
                  <div className="timeline-img">
                    <img alt={event.title} src={event.imageUrl} />
                  </div>
                )}
                <h3>{event.title}</h3>
                {event.description && <p>{event.description}</p>}
                <div className="timeline-actions">
                  <button className="btn-edit" onClick={() => handleEdit(event)}>
                    Szerkesztés
                  </button>
                  <button className="btn-delete" onClick={() => handleDelete(event.id)}>
                    Törlés
                  </button>
                </div>
              </div>
            </div>
          ))
        )}
      </div>

      <Snackbar
        anchorOrigin={{ vertical: "bottom", horizontal: "center" }}
        autoHideDuration={4000}
        onClose={() => setSnack((s) => ({ ...s, open: false }))}
        open={snack.open}
      >
        <Alert onClose={() => setSnack((s) => ({ ...s, open: false }))} severity={snack.severity}>
          {snack.msg}
        </Alert>
      </Snackbar>

      <ConfirmDialog
        confirmText="Törlés"
        message="Biztosan törlöd ezt a történeti eseményt?"
        onClose={() => setDeleteDialog({ open: false, id: null })}
        onConfirm={confirmDelete}
        open={deleteDialog.open}
        title="Esemény törlése"
      />
    </div>
  );
}

export default About;