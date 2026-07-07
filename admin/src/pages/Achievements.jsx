import React, { useCallback, useEffect, useState } from "react";
import { db } from "../firebaseConfig";
import {
  addDoc, collection, deleteDoc, doc,
  getDocs, serverTimestamp, setDoc, updateDoc,
} from "firebase/firestore";
import "../styles/Achievements.css";
import ConfirmDialog from "../components/ConfirmDialog";
import Snackbar from "@mui/material/Snackbar";
import Alert from "@mui/material/Alert";

const CONDITION_TYPES = [
  { value: "station_count",    label: "Állomást látogasson meg (>= N db)" },
  { value: "event_count",      label: "Eseményen vegyen részt (>= N db)" },
  { value: "qr_count",         label: "QR-kódot olvasson be össz. (>= N db)" },
  { value: "points_threshold", label: "Pontot gyűjtsön össze (>= N pont)" },
  { value: "trip_complete",    label: "Teljes túrát teljesítsen (>= N túra)" },
  { value: "top_n",            label: "Legyen top N a ranglistán" },
  { value: "manual",           label: "Manuális (admin adja át)" },
];

const CONDITION_LABELS = Object.fromEntries(CONDITION_TYPES.map((c) => [c.value, c.label]));

const DEFAULTS = [
  { id: "first_steps",  name: "Első lépések",   description: "Olvass be 1 QR-kódot",         icon: "👣", color: "#22c55e", conditionType: "qr_count",        conditionValue: 1   },
  { id: "explorer",     name: "Felfedező",      description: "Látogass meg 3 állomást",       icon: "🧭", color: "#3b82f6", conditionType: "station_count",    conditionValue: 3   },
  { id: "trail_hero",   name: "Túrahős",        description: "Gyűjts össze 140 pontot",       icon: "🏃", color: "#f97316", conditionType: "points_threshold", conditionValue: 140 },
  { id: "event_hunter", name: "Eseményvadász",  description: "Vegyél részt 1 eseményen",      icon: "🎉", color: "#ec4899", conditionType: "event_count",      conditionValue: 1   },
  { id: "local_legend", name: "Helyi legenda",  description: "Teljesíts egy teljes túrát",    icon: "👑", color: "#a855f7", conditionType: "trip_complete",    conditionValue: 1   },
];

const EMPTY = { name: "", description: "", icon: "🏆", color: "#667EEA", conditionType: "station_count", conditionValue: 1 };
const ICON_PRESETS = ["🏆","🥇","👣","🧭","🏃","🎉","👑","⭐","🔥","💎","🌟","🎯","🗺️","🏅","🎖️"];
const COLOR_PRESETS = ["#22c55e","#3b82f6","#f97316","#ec4899","#a855f7","#667EEA","#06b6d4","#eab308","#ef4444","#14b8a6"];

export default function Achievements() {
  const [loading, setLoading] = useState(true);
  const [achievements, setAchievements] = useState([]);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(EMPTY);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState("");
  const [confirmDeleteId, setConfirmDeleteId] = useState(null);
  const [snack, setSnack] = useState({ open: false, msg: "", severity: "error" });
  const showMsg = useCallback((msg, severity = "error") => setSnack({ open: true, msg, severity }), []);

  const loadAll = useCallback(async () => {
    setLoading(true);
    try {
      const snap = await getDocs(collection(db, "achievements"));
      let list = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
      if (list.length === 0) {
        await Promise.all(DEFAULTS.map((r) =>
          setDoc(doc(db, "achievements", r.id), {
            name: r.name, description: r.description, icon: r.icon, color: r.color,
            conditionType: r.conditionType, conditionValue: r.conditionValue,
            unlockedCount: 0, createdAt: serverTimestamp(),
          })
        ));
        const reload = await getDocs(collection(db, "achievements"));
        list = reload.docs.map((d) => ({ id: d.id, ...d.data() }));
      }
      setAchievements(list);
    } catch {
      showMsg("Hiba az adatok betoltésekor");
    } finally { setLoading(false); }
  }, [showMsg]);

  useEffect(() => { setTimeout(() => void loadAll(), 0); }, [loadAll]);

  const openCreate = () => { setEditing(null); setForm(EMPTY); setShowForm(true); };
  const openEdit = (a) => {
    setEditing(a.id);
    setForm({
      name: a.name || "",
      description: a.description || "",
      icon: a.icon || "🏆",
      color: a.color || "#667EEA",
      conditionType: a.conditionType || "station_count",
      conditionValue: a.conditionValue ?? 1,
    });
    setShowForm(true);
  };

  const handleSave = async () => {
    if (!form.name.trim()) return;
    setSaving(true);
    setSaveError("");
    try {
      const payload = {
        name: form.name.trim(),
        description: form.description.trim(),
        icon: form.icon || "🏆",
        color: form.color || "#667EEA",
        conditionType: form.conditionType || "station_count",
        conditionValue: Number(form.conditionValue) || 1,
      };
      if (editing) {
        await updateDoc(doc(db, "achievements", editing), payload);
      } else {
        await addDoc(collection(db, "achievements"), {
          ...payload, unlockedCount: 0, createdAt: serverTimestamp(),
        });
      }
      setShowForm(false);
      await loadAll();
    } catch (err) {
      setSaveError(err.message || "Ismeretlen hiba");
    } finally { setSaving(false); }
  };

  const handleDelete = (id) => setConfirmDeleteId(id);

  const doDelete = async () => {
    if (!confirmDeleteId) return;
    try {
      await deleteDoc(doc(db, "achievements", confirmDeleteId));
      setConfirmDeleteId(null);
      await loadAll();
    } catch {
      showMsg("Hiba a törléskor");
      setConfirmDeleteId(null);
    }
  };

  const setField = (key, val) => setForm((p) => ({ ...p, [key]: val }));

  if (loading) return <div className="ach-wrap"><div className="ach-loading">Betöltés...</div></div>;

  return (
    <div className="ach-wrap">
      <div className="ach-header">
        <div>
          <h1>🏆 Jutalmak</h1>
          <p className="ach-header-sub">A látogatóknak automatikusan jelenik meg, ha teljesítik a feltételt.</p>
        </div>
        <button className="ach-add-btn" onClick={openCreate}>+ Új jutalom</button>
      </div>

      <div className="ach-list">
        {achievements.length === 0 && (
          <div className="ach-empty-state">
            <div className="ach-empty-icon">🏆</div>
            <p>Még nincsenek jutalmak. Adj hozzá az elsőket!</p>
          </div>
        )}
        {achievements.map((a) => (
          <div key={a.id} className="ach-row" style={{ "--ac": a.color || "#667EEA" }}>
            <div className="ach-row-icon">{a.icon || "🏆"}</div>
            <div className="ach-row-body">
              <span className="ach-row-name">{a.name}</span>
              <span className="ach-row-desc">{a.description}</span>
              {a.conditionType && a.conditionType !== "manual" && (
                <span className="ach-row-cond">
                  {CONDITION_LABELS[a.conditionType] || a.conditionType}: <strong>{a.conditionValue}</strong>
                </span>
              )}
              {a.conditionType === "manual" && (
                <span className="ach-row-cond">Manuális (admin adja át)</span>
              )}
            </div>
            <div className="ach-row-actions">
              <button className="ach-row-btn edit" onClick={() => openEdit(a)} title="Szerkesztés">✏️ Szerkesztés</button>
              <button className="ach-row-btn del" onClick={() => handleDelete(a.id)} title="Törlés">🗑️</button>
            </div>
          </div>
        ))}
      </div>

      {showForm && (
        <div className="ach-overlay" onClick={(e) => e.target === e.currentTarget && setShowForm(false)}>
          <div className="ach-modal">
            <div className="ach-modal-header">
              <h2>{editing ? "Jutalom szerkesztése" : "Új jutalom hozzáadása"}</h2>
              <button className="ach-modal-x" onClick={() => setShowForm(false)}>✕</button>
            </div>

            <div className="ach-modal-body">
              <label className="ach-label">Megnevezés *</label>
              <input
                className="ach-input"
                value={form.name}
                onChange={(e) => setField("name", e.target.value)}
                placeholder="pl. Felfedező"
              />

              <label className="ach-label">Mire kap a látogató ezt a jutalmot?</label>
              <input
                className="ach-input"
                value={form.description}
                onChange={(e) => setField("description", e.target.value)}
                placeholder="pl. Beolvasott 3 QR-kódot"
              />

              <label className="ach-label">Feltétel típusa</label>
              <select
                className="ach-input ach-select"
                value={form.conditionType}
                onChange={(e) => setField("conditionType", e.target.value)}
              >
                {CONDITION_TYPES.map((ct) => (
                  <option key={ct.value} value={ct.value}>{ct.label}</option>
                ))}
              </select>

              {form.conditionType !== "manual" && (
                <>
                  <label className="ach-label">
                    Feltétel értéke (N){form.conditionType === "top_n" ? " – top hányadik" : " – minimum darab/pont"}
                  </label>
                  <input
                    className="ach-input"
                    type="number"
                    min="1"
                    value={form.conditionValue}
                    onChange={(e) => setField("conditionValue", e.target.value)}
                  />
                </>
              )}

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

              <label className="ach-label">Szín</label>
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
                  title="Egyedi szín"
                />
              </div>

              <div className="ach-preview">
                <span className="ach-preview-icon" style={{ background: form.color }}>{form.icon}</span>
                <span className="ach-preview-name">{form.name || "Jutalom neve"}</span>
              </div>
            </div>

            <div className="ach-modal-footer">
              {saveError && <div style={{color:"#dc2626",fontSize:"0.82rem",flex:1,padding:"0 8px"}}>{saveError}</div>}
              <button className="ach-cancel-btn" onClick={() => setShowForm(false)}>Mégse</button>
              <button className="ach-save-btn" onClick={handleSave} disabled={saving || !form.name.trim()}>
                {saving ? "Mentés..." : editing ? "Mentés" : "Hozzáadás"}
              </button>
            </div>
          </div>
        </div>
      )}
      <ConfirmDialog
        open={confirmDeleteId !== null}
        title="Törlés megerősítése"
        message="Biztosan törölni szeretnéd ezt a jutalmat? Ez a művelet nem vonható vissza."
        confirmText="Törlés"
        onConfirm={doDelete}
        onClose={() => setConfirmDeleteId(null)}
      />
      <Snackbar open={snack.open} autoHideDuration={4000} onClose={() => setSnack((s) => ({ ...s, open: false }))} anchorOrigin={{ vertical: "bottom", horizontal: "center" }}>
        <Alert severity={snack.severity} onClose={() => setSnack((s) => ({ ...s, open: false }))}>{snack.msg}</Alert>
      </Snackbar>
    </div>
  );
}





