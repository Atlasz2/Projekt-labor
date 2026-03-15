import React, { useState, useEffect } from "react";
import { db } from "../firebaseConfig";
import { collection, addDoc, updateDoc, deleteDoc, getDocs, doc } from "firebase/firestore";
import "../styles/Content.css";
import { safeString } from "../utils/safeString";
import ConfirmDialog from "../components/ConfirmDialog";

function Events() {
  const [events, setEvents] = useState([]);
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [deleteDialog, setDeleteDialog] = useState({ open: false, id: null });
  const [formData, setFormData] = useState({
    name: "",
    date: "",
    description: "",
    location: "",
  });

  useEffect(() => {
    fetchEvents();
  }, []);

  const fetchEvents = async () => {
    try {
      setLoading(true);
      const snapshot = await getDocs(collection(db, "events"));
      const data = snapshot.docs.map((item) => {
        const docData = item.data();
        return {
          id: item.id,
          name: safeString(docData.name),
          date: safeString(docData.date),
          description: safeString(docData.description),
          location: safeString(docData.location),
        };
      });
      setEvents(data);
    } catch {
      setError("Hiba az adatok betöltésekor");
    } finally {
      setLoading(false);
    }
  };

  const handleInputChange = (e) => {
    const { name, value } = e.target;
    setFormData((prev) => ({ ...prev, [name]: value }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    try {
      const cleanData = {
        name: safeString(formData.name),
        date: safeString(formData.date),
        description: safeString(formData.description),
        location: safeString(formData.location),
      };
      if (editingId) {
        await updateDoc(doc(db, "events", editingId), cleanData);
      } else {
        await addDoc(collection(db, "events"), cleanData);
      }
      setFormData({ name: "", date: "", description: "", location: "" });
      setShowForm(false);
      setEditingId(null);
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
    });
    setShowForm(true);
  };

  const handleDelete = (id) => {
    setDeleteDialog({ open: true, id });
  };

  const confirmDelete = async () => {
    if (!deleteDialog.id) return;
    try {
      await deleteDoc(doc(db, "events", deleteDialog.id));
      setDeleteDialog({ open: false, id: null });
      fetchEvents();
    } catch {
      setError("Hiba a törlékor");
      setDeleteDialog({ open: false, id: null });
    }
  };

  if (loading) return <p>Betöltés...</p>;

  return (
    <div className="content-page">
      <div className="page-header">
        <h1>Rendezvények</h1>
        <p>Rendezvények kezelése</p>
      </div>

      {error && <div className="error-message">{error}</div>}

      {!showForm && (
        <button className="btn-primary" onClick={() => setShowForm(true)}>
          + Új rendezvény
        </button>
      )}

      {showForm && (
        <div className="form-container">
          <h2>{editingId ? "Szerkesztés" : "Új rendezvény"}</h2>
          <form onSubmit={handleSubmit}>
            <input type="text" name="name" placeholder="Rendezvény neve" value={formData.name} onChange={handleInputChange} required />
            <input type="date" name="date" value={formData.date} onChange={handleInputChange} required />
            <input type="text" name="location" placeholder="Helyszín" value={formData.location} onChange={handleInputChange} required />
            <textarea name="description" placeholder="Leírás" value={formData.description} onChange={handleInputChange} rows="3" />
            <button type="submit" className="btn-primary">{editingId ? "Frissítés" : "Hozzáadás"}</button>
            <button type="button" className="btn-secondary" onClick={() => { setShowForm(false); setEditingId(null); }}>
              Mégse
            </button>
          </form>
        </div>
      )}

      <div className="cards-grid">
        {events.map((event) => (
          <div key={event.id} className="card">
            <h3>{event.name || "Nincs név"}</h3>
            {event.date && <p><strong>Dátum:</strong> {event.date}</p>}
            {event.location && <p><strong>Helyszín:</strong> {event.location}</p>}
            {event.description && <p>{event.description}</p>}
            <div className="card-actions">
              <button className="btn-edit" onClick={() => handleEdit(event)}>Szerkesztés</button>
              <button className="btn-delete" onClick={() => handleDelete(event.id)}>Törlés</button>
            </div>
          </div>
        ))}
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

