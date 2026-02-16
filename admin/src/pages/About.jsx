import React, { useState, useEffect } from "react";
import { db } from "../firebaseConfig";
import { collection, getDocs, doc, updateDoc, deleteDoc, addDoc } from "firebase/firestore";
import "../styles/About.css";

const safeString = (val) => {
  if (val === null || val === undefined) return "";
  if (typeof val === "object") return "";
  return String(val).trim();
};

function About() {
  const [events, setEvents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [error, setError] = useState(null);
  const [formData, setFormData] = useState({
    year: "",
    title: "",
    description: "",
  });

  useEffect(() => {
    fetchEvents();
  }, []);

  const fetchEvents = async () => {
    try {
      setLoading(true);
      const snapshot = await getDocs(collection(db, "about"));
      const data = snapshot.docs.map((doc) => ({
        id: doc.id,
        year: safeString(doc.data().year),
        title: safeString(doc.data().title),
        description: safeString(doc.data().description),
      }));
      // Sort chronologically: earliest first
      data.sort((a, b) => {
        const yearA = parseInt(a.year) || 0;
        const yearB = parseInt(b.year) || 0;
        return yearA - yearB;
      });
      setEvents(data);
    } catch (err) {
      setError("Hiba az adatok betöltésénél");
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
        year: safeString(formData.year),
        title: safeString(formData.title),
        description: safeString(formData.description),
      };

      if (editingId) {
        await updateDoc(doc(db, "about", editingId), cleanData);
      } else {
        await addDoc(collection(db, "about"), cleanData);
      }

      setFormData({ year: "", title: "", description: "" });
      setShowForm(false);
      setEditingId(null);
      fetchEvents();
    } catch (err) {
      setError("Hiba a mentéskor");
    }
  };

  const handleEdit = (event) => {
    setEditingId(event.id);
    setFormData({
      year: event.year,
      title: event.title,
      description: event.description,
    });
    setShowForm(true);
  };

  const handleDelete = async (id) => {
    if (window.confirm("Biztosan törlöd ezt az eseményt?")) {
      try {
        await deleteDoc(doc(db, "about", id));
        fetchEvents();
      } catch (err) {
        setError("Hiba a törlékor");
      }
    }
  };

  if (loading) return <p>Betöltés...</p>;

  return (
    <div className="content-page">
      <div className="page-header">
        <h1>🏛️ Nagyvázsony Története</h1>
        <p>Szerkeszd a település történeti eseményeit (időrendben)</p>
      </div>

      {error && <div className="error-message">{error}</div>}

      {!showForm && (
        <button className="btn-primary" onClick={() => setShowForm(true)}>
          + Új esemény
        </button>
      )}

      {showForm && (
        <div className="form-container">
          <h2>{editingId ? "Esemény szerkesztése" : "Új esemény"}</h2>
          <form onSubmit={handleSubmit}>
            <div className="form-row">
              <div className="form-group">
                <label>Év/Időszak *</label>
                <input
                  type="text"
                  name="year"
                  placeholder="pl. 1543, vagy: 1500-1600"
                  value={formData.year}
                  onChange={handleInputChange}
                  required
                />
              </div>
            </div>

            <div className="form-group">
              <label>Cím *</label>
              <input
                type="text"
                name="title"
                placeholder="pl. Nagyvázsony vára építésének kezdete"
                value={formData.title}
                onChange={handleInputChange}
                required
              />
            </div>

            <div className="form-group">
              <label>Leírás</label>
              <textarea
                name="description"
                placeholder="Részletes leírás az eseményről..."
                value={formData.description}
                onChange={handleInputChange}
                rows="5"
              />
            </div>

            <div className="form-actions">
              <button type="submit" className="btn-primary">
                {editingId ? "Frissítés" : "Hozzáadás"}
              </button>
              <button
                type="button"
                className="btn-secondary"
                onClick={() => {
                  setShowForm(false);
                  setEditingId(null);
                  setFormData({ year: "", title: "", description: "" });
                }}
              >
                Mégse
              </button>
            </div>
          </form>
        </div>
      )}

      <div className="timeline">
        {events.length === 0 ? (
          <p className="no-data">Nincsenek még történeti események. Adj hozzá valamilyen eseményt!</p>
        ) : (
          events.map((event, idx) => (
            <div key={event.id} className="timeline-item">
              <div className="timeline-marker">
                <div className="timeline-dot"></div>
                {idx < events.length - 1 && <div className="timeline-line"></div>}
              </div>
              <div className="timeline-content">
                <div className="timeline-year">{event.year}</div>
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
    </div>
  );
}

export default About;
