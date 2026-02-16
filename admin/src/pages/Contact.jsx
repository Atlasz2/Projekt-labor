import React, { useState, useEffect } from "react";
import { db } from "../firebaseConfig";
import { collection, getDocs, doc, updateDoc } from "firebase/firestore";
import "../styles/Content.css";

const safeString = (val) => {
  if (val === null || val === undefined) return "";
  if (typeof val === "object") return "";
  return String(val).trim();
};

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
  const [error, setError] = useState(null);

  useEffect(() => {
    fetchContact();
  }, []);

  const fetchContact = async () => {
    try {
      setLoading(true);
      const snapshot = await getDocs(collection(db, "contact"));
      if (snapshot.size > 0) {
        const doc = snapshot.docs[0];
        const data = doc.data();
        const office = data.mainOffice || {};
        setDocId(doc.id);
        setContact({
          name: safeString(office.name),
          address: safeString(office.address),
          phone: safeString(office.phone),
          email: safeString(office.email),
        });
      }
      setLoading(false);
    } catch (err) {
      setError("Hiba az adatok betöltése során");
      setLoading(false);
    }
  };

  const handleInputChange = (e) => {
    const { name, value } = e.target;
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
      setError(null);
    } catch (err) {
      setError("Hiba a mentés során");
      setSaving(false);
    }
  };

  if (loading) return <p>Betöltés...</p>;

  return (
    <div className="content-page">
      <div className="page-header">
        <h1>Kapcsolat</h1>
        <p>Iroda adatainak szerkesztése</p>
      </div>

      {error && <div className="error-message">{error}</div>}

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

      <div className="contact-preview" style={{ maxWidth: "600px", margin: "40px auto", padding: "20px", backgroundColor: "#f5f5f5", borderRadius: "8px" }}>
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
