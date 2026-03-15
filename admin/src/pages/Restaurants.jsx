import React, { useState, useEffect } from "react";
import { db } from "../firebaseConfig";
import { collection, addDoc, updateDoc, deleteDoc, getDocs, doc } from "firebase/firestore";
import "../styles/Content.css";
import { safeString } from "../utils/safeString";
import ConfirmDialog from "../components/ConfirmDialog";

function Restaurants() {
  const [restaurants, setRestaurants] = useState([]);
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [deleteDialog, setDeleteDialog] = useState({ open: false, id: null });
  const [formData, setFormData] = useState({
    name: "",
    type: "hungarian",
    cuisine: "",
    priceRange: "",
    description: "",
  });

  useEffect(() => {
    fetchRestaurants();
  }, []);

  const fetchRestaurants = async () => {
    try {
      setLoading(true);
      const snapshot = await getDocs(collection(db, "restaurants"));
      const data = snapshot.docs.map((item) => {
        const docData = item.data();
        return {
          id: item.id,
          name: safeString(docData.name),
          type: safeString(docData.type) || "hungarian",
          cuisine: safeString(docData.cuisine),
          priceRange: safeString(docData.priceRange),
          description: safeString(docData.description),
        };
      });
      setRestaurants(data);
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
        type: safeString(formData.type),
        cuisine: safeString(formData.cuisine),
        priceRange: safeString(formData.priceRange),
        description: safeString(formData.description),
      };
      if (editingId) {
        await updateDoc(doc(db, "restaurants", editingId), cleanData);
      } else {
        await addDoc(collection(db, "restaurants"), cleanData);
      }
      setFormData({
        name: "",
        type: "hungarian",
        cuisine: "",
        priceRange: "",
        description: "",
      });
      setShowForm(false);
      setEditingId(null);
      fetchRestaurants();
    } catch {
      setError("Hiba a mentéskor");
    }
  };

  const handleEdit = (item) => {
    setEditingId(item.id);
    setFormData({
      name: item.name || "",
      type: item.type || "hungarian",
      cuisine: item.cuisine || "",
      priceRange: item.priceRange || "",
      description: item.description || "",
    });
    setShowForm(true);
  };

  const handleDelete = (id) => {
    setDeleteDialog({ open: true, id });
  };

  const confirmDelete = async () => {
    if (!deleteDialog.id) return;
    try {
      await deleteDoc(doc(db, "restaurants", deleteDialog.id));
      setDeleteDialog({ open: false, id: null });
      fetchRestaurants();
    } catch {
      setError("Hiba a törlékor");
      setDeleteDialog({ open: false, id: null });
    }
  };

  if (loading) return <p>Betöltés...</p>;

  return (
    <div className="content-page">
      <div className="page-header">
        <h1>Vendéglátás</h1>
        <p>Éttermek és vendéglátóhelyek kezelése</p>
      </div>

      {error && <div className="error-message">{error}</div>}

      {!showForm && (
        <button className="btn-primary" onClick={() => setShowForm(true)}>
          + Új étterem
        </button>
      )}

      {showForm && (
        <div className="form-container">
          <h2>{editingId ? "Szerkesztés" : "Új étterem"}</h2>
          <form onSubmit={handleSubmit}>
            <input type="text" name="name" placeholder="Étterem neve" value={formData.name} onChange={handleInputChange} required />
            <select name="type" value={formData.type} onChange={handleInputChange}>
              <option value="hungarian">Magyar konyha</option>
              <option value="fish">Halételek</option>
              <option value="cafe">Kávézó</option>
              <option value="pizzeria">Pizzéria</option>
              <option value="icecream">Fagylaltozó</option>
              <option value="bar">Bár</option>
            </select>
            <input type="text" name="cuisine" placeholder="Konyha típusa" value={formData.cuisine} onChange={handleInputChange} required />
            <input type="text" name="priceRange" placeholder="Árszint" value={formData.priceRange} onChange={handleInputChange} required />
            <textarea name="description" placeholder="Leírás" value={formData.description} onChange={handleInputChange} rows="3" />
            <button type="submit" className="btn-primary">{editingId ? "Frissítés" : "Hozzáadás"}</button>
            <button type="button" className="btn-secondary" onClick={() => { setShowForm(false); setEditingId(null); }}>
              Mégse
            </button>
          </form>
        </div>
      )}

      <div className="cards-grid">
        {restaurants.map((rest) => (
          <div key={rest.id} className="card">
            <h3>{rest.name || "Nincs név"}</h3>
            {rest.cuisine && <p><strong>Konyha:</strong> {rest.cuisine}</p>}
            {rest.priceRange && <p><strong>Árszint:</strong> {rest.priceRange}</p>}
            {rest.description && <p>{rest.description}</p>}
            <div className="card-actions">
              <button className="btn-edit" onClick={() => handleEdit(rest)}>Szerkesztés</button>
              <button className="btn-delete" onClick={() => handleDelete(rest.id)}>Törlés</button>
            </div>
          </div>
        ))}
      </div>

      <ConfirmDialog
        open={deleteDialog.open}
        title="Étterem törlése"
        message="Biztosan törlöd ezt az éttermet?"
        confirmText="Törlés"
        onClose={() => setDeleteDialog({ open: false, id: null })}
        onConfirm={confirmDelete}
      />
    </div>
  );
}

export default Restaurants;

