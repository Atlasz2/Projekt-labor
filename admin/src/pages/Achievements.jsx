import React, { useEffect, useState } from "react";
import { db } from "../firebaseConfig";
import {
  collection, deleteDoc, doc,
  getDocs, serverTimestamp, setDoc, updateDoc,
} from "firebase/firestore";
import "../styles/Achievements.css";

const DEFAULTS = [
  { id: "first_steps",  name: "Elso lepesek",  description: "Olvass be 1 QR-kodot",         icon: "👣", color: "#22c55e" },
  { id: "explorer",     name: "Felfedezo",      description: "Latogass meg 3 allomast",       icon: "🧭", color: "#3b82f6" },
  { id: "trail_hero",   name: "Turahos",        description: "Gyujts ossze 140 pontot",       icon: "🏃", color: "#f97316" },
  { id: "event_hunter", name: "Esemenyivadasz", description: "Vegyel reszt 1 esemeryen",      icon: "🎉", color: "#ec4899" },
  { id: "local_legend", name: "Helyi legenda",  description: "Teljesits egy teljes turat",    icon: "👑", color: "#a855f7" },
];

const EMPTY = { name: "", description: "", icon: "🏆", color: "#667EEA" };
const ICON_PRESETS = ["🏆","🥇","👣","🧭","🏃","🎉","👑","⭐","🔥","💎","🌟","🎯","🗺️","🏅","🎖️"];
const COLOR_PRESETS = ["#22c55e","#3b82f6","#f97316","#ec4899","#a855f7","#667EEA","#06b6d4","#eab308","#ef4444","#14b8a6"];

export default function Achievements() {
  const [loading, setLoading] = useState(true);
  const [achievements, setAchievements] = useState([]);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(EMPTY);
  const [saving, setSaving] = useState(false);

  useEffect(() => { loadAll(); }, []);

  const loadAll = async () => {
    setLoading(true);
    try {
      const snap = await getDocs(collection(db, "achievements"));
      let list = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
      if (list.length === 0) {
        await Promise.all(DEFAULTS.map((r) =>
          setDoc(doc(db, "achievements", r.id), {
            name: r.name, description: r.description, icon: r.icon, color: r.color,
            unlockedCount: 0, createdAt: serverTimestamp(),
          })
        ));
        const reload = await getDocs(collection(db, "achievements"));
        list = reload.docs.map((d) => ({ id: d.id, ...d.data() }));
      }
      setAchievements(list);
    } finally { setLoading(false); }
  };

  const openCreate = () => { setEditing(null); setForm(EMPTY); setShowForm(true); };
  const openEdit = (a) => {
    setEditing(a.id);
    setForm({ name: a.name || "", description: a.description || "", icon: a.icon || "🏆", color: a.color || "#667EEA" });
    setShowForm(true);
  };

  const handleSave = async () => {
    if (!form.name.trim()) return;
    setSaving(true);
    try {
      const payload = {
        name: form.name.trim(),
        description: form.description.trim(),
        icon: form.icon || "🏆",
        color: form.color || "#667EEA",
      };
      if (editing) {
        await updateDoc(doc(db, "achievements", editing), payload);
      } else {
        await setDoc(doc(db, "achievements", crypto.randomUUID()), {
          ...payload, unlockedCount: 0, createdAt: serverTimestamp(),
        });
      }
      setShowForm(false);
      await loadAll();
    } finally { setSaving(false); }
  };

  const handleDelete = async (id) => {
    if (!window.confirm("Biztosan torolni szeretned ezt az achievementet?")) return;
    await deleteDoc(doc(db, "achievements", id));
    await loadAll();
  };

  const setField = (key, val) => setForm((p) => ({ ...p, [key]: val }));

  if (loading) return <div className="ach-wrap"><div className="ach-loading">Betoltes...</div></div>;

  return (
    <div className="ach-wrap">
      <div className="ach-header">
        <div>
          <h1>🏆 Jutalmak</h1>
          <p className="ach-header-sub">A latogatoknak automatikusan jelenik meg, ha teljesitik a feltetelt.</p>
        </div>
        <button className="ach-add-btn" onClick={openCreate}>+ Uj jutalom</button>
      </div>

      <div className="ach-list">
        {achievements.length === 0 && (
          <div className="ach-empty-state">
            <div className="ach-empty-icon">🏆</div>
            <p>Meg nincsenek jutalmak. Adj hozza az elsoket!</p>
          </div>
        )}
        {achievements.map((a) => (
          <div key={a.id} className="ach-row" style={{ "--ac": a.color || "#667EEA" }}>
            <div className="ach-row-icon">{a.icon || "🏆"}</div>
            <div className="ach-row-body">
              <span className="ach-row-name">{a.name}</span>
              <span className="ach-row-desc">{a.description}</span>
            </div>
            <div className="ach-row-actions">
              <button className="ach-row-btn edit" onClick={() => openEdit(a)} title="Szerkesztes">✏️ Szerkesztes</button>
              <button className="ach-row-btn del" onClick={() => handleDelete(a.id)} title="Torles">🗑️</button>
            </div>
          </div>
        ))}
      </div>

      {showForm && (
        <div className="ach-overlay" onClick={(e) => e.target === e.currentTarget && setShowForm(false)}>
          <div className="ach-modal">
            <div className="ach-modal-header">
              <h2>{editing ? "Jutalom szerkesztese" : "Uj jutalom hozzaadasa"}</h2>
              <button className="ach-modal-x" onClick={() => setShowForm(false)}>✕</button>
            </div>

            <div className="ach-modal-body">
              <label className="ach-label">Megnevezes *</label>
              <input
                className="ach-input"
                value={form.name}
                onChange={(e) => setField("name", e.target.value)}
                placeholder="pl. Felfedezo"
              />

              <label className="ach-label">Mire kap a latogato ezt a jutalmot?</label>
              <input
                className="ach-input"
                value={form.description}
                onChange={(e) => setField("description", e.target.value)}
                placeholder="pl. Beolvasott 3 QR-kodot"
              />

              <label className="ach-label">Ikon</label>
              <div className="ach-icon-row">
                {ICON_PRESETS.map((ic) => (
                  <button
                    key={ic}
                    className={`ach-icon-btn${form.icon === ic ? " active" : ""}`}
                    onClick={() => setField("icon", ic)}
                    type="button"
                  >{ic}</button>
                ))}
              </div>

              <label className="ach-label">Szin</label>
              <div className="ach-color-row">
                {COLOR_PRESETS.map((c) => (
                  <button
                    key={c}
                    className={`ach-color-btn${form.color === c ? " active" : ""}`}
                    style={{ background: c }}
                    onClick={() => setField("color", c)}
                    type="button"
                  />
                ))}
                <input
                  type="color"
                  className="ach-color-picker"
                  value={form.color}
                  onChange={(e) => setField("color", e.target.value)}
                  title="Egyedi szin"
                />
              </div>

              <div className="ach-preview">
                <span className="ach-preview-icon" style={{ background: form.color }}>{form.icon}</span>
                <span className="ach-preview-name">{form.name || "Jutalom neve"}</span>
              </div>
            </div>

            <div className="ach-modal-footer">
              <button className="ach-cancel-btn" onClick={() => setShowForm(false)}>Megse</button>
              <button className="ach-save-btn" onClick={handleSave} disabled={saving || !form.name.trim()}>
                {saving ? "Mentés..." : editing ? "Mentés" : "Hozzáadás"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
