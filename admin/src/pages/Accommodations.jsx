import React, { useState, useEffect } from "react";
import { db } from "../firebaseConfig";
import { collection, addDoc, updateDoc, deleteDoc, getDocs, doc } from "firebase/firestore";
import "../styles/Content.css";

const safeString = (val) => {
  if (val === null || val === undefined) return "";
  if (typeof val === "object") return "";
  return String(val).trim();
};

function Accommodations() {
  const [accommodations, setAccommodations] = useState([]);
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [formData, setFormData] = useState({
    name: "",
    type: "hotel",
    pricePerNight: "",
    capacity: "",
    description: "",
  });

  useEffect(() => {
    fetchAccommodations();
  }, []);

  const fetchAccommodations = async () => {
    try {
      setLoading(true);
      const snapshot = await getDocs(collection(db, "accommodations"));
      const data = snapshot.docs.map((doc) => {
        const docData = doc.data();
        return {
          id: doc.id,
          name: safeString(docData.name),
          type: safeString(docData.type) || "hotel",
          pricePerNight: safeString(docData.pricePerNight),
          capacity: safeString(docData.capacity),
          description: safeString(docData.description),
        };
      });
      setAccommodations(data);
    } catch (err) {
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
        type: safeString(formData.type),
        pricePerNight: safeString(formData.pricePerNight),
        capacity: safeString(formData.capacity),
        description: safeString(formData.description),
      };
      if (editingId) {
        await updateDoc(doc(db, "accommodations", editingId), cleanData);
      } else {
        await addDoc(collection(db, "accommodations"), cleanData);
      }
      setFormData({
        name: "",
        type: "hotel",
        pricePerNight: "",
        capacity: "",
        description: "",
      });
      setShowForm(false);
      setEditingId(null);
      fetchAccommodations();
    } catch (err) {
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
    });
    setShowForm(true);
  };

  const handleDelete = async (id) => {
    if (window.confirm("Biztosan törlöd?")) {
      try {
        await deleteDoc(doc(db, "accommodations", id));
        fetchAccommodations();
      } catch (err) {
        setError("Hiba a törlékor");
      }
    }
  };

  if (loading) return <p>Betöltés...</p>;

  return (
    <div className="content-page">
      <div className="page-header">
        <h1>Szállások</h1>
        <p>Szállások kezelése</p>
      </div>

      {error && <div className="error-message">{error}</div>}

      {!showForm && (
        <button className="btn-primary" onClick={() => setShowForm(true)}>
          + Új szállás
        </button>
      )}

      {showForm && (
        <div className="form-container">
          <h2>{editingId ? "Szerkesztés" : "Új szállás"}</h2>
          <form onSubmit={handleSubmit}>
            <input
              type="text"
              name="name"
              placeholder="Szállás neve"
              value={formData.name}
              onChange={handleInputChange}
              required
            />
            <select
              name="type"
              value={formData.type}
              onChange={handleInputChange}
            >
              <option value="hotel">Hotel</option>
              <option value="guesthouse">Vendégház</option>
              <option value="apartment">Apartman</option>
              <option value="campsite">Kemping</option>
            </select>
            <input
              type="text"
              name="pricePerNight"
              placeholder="Ár/éjszaka"
              value={formData.pricePerNight}
              onChange={handleInputChange}
              required
            />
            <input
              type="number"
              name="capacity"
              placeholder="Kapacitás"
              value={formData.capacity}
              onChange={handleInputChange}
              required
            />
            <textarea
              name="description"
              placeholder="Leírás"
              value={formData.description}
              onChange={handleInputChange}
              rows="3"
            />
            <button type="submit" className="btn-primary">
              {editingId ? "Frissítés" : "Hozzáadás"}
            </button>
            <button
              type="button"
              className="btn-secondary"
              onClick={() => {
                setShowForm(false);
                setEditingId(null);
              }}
            >
              Mégse
            </button>
          </form>
        </div>
      )}

      <div className="cards-grid">
        {accommodations.map((acc) => (
          <div key={acc.id} className="card">
            <h3>{acc.name || "Nincs név"}</h3>
            {acc.type && (
              <p>
                <strong>Típus:</strong> {acc.type}
              </p>
            )}
            {acc.pricePerNight && (
              <p>
                <strong>Ár:</strong> {acc.pricePerNight}
              </p>
            )}
            {acc.capacity && (
              <p>
                <strong>Kapacitás:</strong> {acc.capacity}
              </p>
            )}
            {acc.description && <p>{acc.description}</p>}
            <div className="card-actions">
              <button className="btn-edit" onClick={() => handleEdit(acc)}>
                Szerkesztés
              </button>
              <button className="btn-delete" onClick={() => handleDelete(acc.id)}>
                Törlés
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export default Accommodations;
