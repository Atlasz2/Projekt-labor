import React, { useState, useEffect, useCallback } from "react";
import { db } from "../firebaseConfig";
import { collection, getDocs, doc, updateDoc, addDoc } from "firebase/firestore";
import "../styles/Content.css";
import { safeString } from "../utils/safeString";
import { useProject } from "../context/ProjectContext";
import { docProjectId } from "../utils/projects";
import StateCard from "../components/StateCard";

function Contact() {
  const { activeProjectId } = useProject();
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
  const fetchContact = useCallback(async () => {
    try {
      setLoading(true);
      const snapshot = await getDocs(collection(db, "contact"));
      // Az aktív településhez tartozó kapcsolati doksi (a hiányzó projectId az
      // alapértelmezett projektet jelenti). Ha nincs, üresen indul – mentéskor
      // létrejön ehhez a projekthez.
      const contactDoc = snapshot.docs.find(
        (d) => docProjectId(d.data()) === activeProjectId,
      );
      if (contactDoc) {
        const office = contactDoc.data().mainOffice || {};
        setDocId(contactDoc.id);
        setContact({
          name: safeString(office.name),
          address: safeString(office.address),
          phone: safeString(office.phone),
          email: safeString(office.email),
        });
      } else {
        setDocId(null);
        setContact({ name: "", address: "", phone: "", email: "" });
      }
      setLoading(false);
    } catch {
      setError("Hiba az adatok betöltése során");
      setLoading(false);
    }
  }, [activeProjectId]);

  useEffect(() => {
    const timer = setTimeout(() => {
      void fetchContact();
    }, 0);

    return () => clearTimeout(timer);
  }, [fetchContact]);

  const handleInputChange = (e) => {
    const { name, value } = e.target;
    setSaved(false);
    setContact((prev) => ({ ...prev, [name]: value }));
  };

  const handleSave = async () => {
    try {
      setSaving(true);
      const cleanData = {
        mainOffice: {
          name: safeString(contact.name),
          address: safeString(contact.address),
          phone: safeString(contact.phone),
          email: safeString(contact.email),
        },
        projectId: activeProjectId,
      };
      if (docId) {
        await updateDoc(doc(db, "contact", docId), cleanData);
      } else {
        // Ehhez a településhez még nincs kapcsolati doksi – létrehozzuk.
        const ref = await addDoc(collection(db, "contact"), cleanData);
        setDocId(ref.id);
      }
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

