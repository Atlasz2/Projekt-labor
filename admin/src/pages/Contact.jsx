import React, { useState, useEffect } from "react";
import { db } from "../firebaseConfig";
import { collection, getDocs, doc, updateDoc } from "firebase/firestore";
import "../styles/Content.css";
import { safeString } from "../utils/safeString";
import StateCard from "../components/StateCard";

function Contact() {
  const [contact, setContact] = useState({
    name: "",
    address: "",
    phone: "",
    email: "",
  });
  const [docId, setDocId] = useState(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState(null);
  async function fetchContact() {
    try {
      setLoading(true);
      const snapshot = await getDocs(collection(db, "contact"));
      if (snapshot.size > 0) {
        const contactDoc = snapshot.docs[0];
        const data = contactDoc.data();
        const office = data.mainOffice || {};
        setDocId(contactDoc.id);
        setContact({
          name: safeString(office.name),
          address: safeString(office.address),
          phone: safeString(office.phone),
          email: safeString(office.email),
        });
      }
      setLoading(false);
    } catch {
      setError("Hiba az adatok betöltése során");
      setLoading(false);
    }
  }

  useEffect(() => {
    const timer = setTimeout(() => {
      void fetchContact();
    }, 0);

    return () => clearTimeout(timer);
  }, []);

  const handleInputChange = (e) => {
    const { name, value } = e.target;
    setSaved(false);
    setContact((prev) => ({ ...prev, [name]: value }));
  };

  const handleSave = async () => {
    if (!docId) return;
    try {
      setSaving(true);
      const cleanData = {
        mainOffice: {
          name: safeString(contact.name),
          address: safeString(contact.address),
          phone: safeString(contact.phone),
          email: safeString(contact.email),
        },
      };
      await updateDoc(doc(db, "contact", docId), cleanData);
      setSaving(false);
      setSaved(true);
      setError(null);
    } catch {
      setError("Hiba a mentés során");
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <StateCard
        variant="loading"
        icon="📇"
        title="Kapcsolati adatok betöltése..."
        description="Kérlek várj, az adatok betöltése folyamatban van."
      />
    );
  }

  return (
    <div className="content-page">
      <div className="page-header">
        <h1>Kapcsolat</h1>
        <p>Iroda adatainak szerkesztése</p>
      </div>

      {error && <div className="error-message">{error}</div>}
      {saved && <div className="success-message">✅ A kapcsolati adatok elmentve.</div>}

      <div className="form-container" style={{ maxWidth: "600px", margin: "30px auto" }}>
        <h2>Nagyvázsony Információs Iroda</h2>
        
        <div className="form-group">
          <label>Iroda neve</label>
          <input
            type="text"
            name="name"
            placeholder="Iroda neve"
            value={contact.name}
            onChange={handleInputChange}
          />
        </div>

        <div className="form-group">
          <label>Cím</label>
          <input
            type="text"
            name="address"
            placeholder="Cím"
            value={contact.address}
            onChange={handleInputChange}
          />
        </div>

        <div className="form-group">
          <label>Telefonszám</label>
          <input
            type="tel"
            name="phone"
            placeholder="Telefonszám"
            value={contact.phone}
            onChange={handleInputChange}
          />
        </div>

        <div className="form-group">
          <label>E-mail cím</label>
          <input
            type="email"
            name="email"
            placeholder="E-mail cím"
            value={contact.email}
            onChange={handleInputChange}
          />
        </div>

        <div className="form-actions">
          <button className="btn-primary" onClick={handleSave} disabled={saving}>
            {saving ? "Mentés..." : "💾 Mentés"}
          </button>
        </div>
      </div>

      <div className="contact-preview">
        <h3>Előnézet</h3>
        {contact.name && <p><strong>{contact.name}</strong></p>}
        {contact.address && <p>📍 {contact.address}</p>}
        {contact.phone && <p>📞 {contact.phone}</p>}
        {contact.email && <p>✉️ {contact.email}</p>}
      </div>
    </div>
  );
}

export default Contact;

