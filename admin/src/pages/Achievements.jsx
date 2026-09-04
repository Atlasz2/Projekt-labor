import React, { useCallback, useEffect, useState } from "react";
import { db } from "../firebaseConfig";
import {
  addDoc, collection, deleteDoc, doc,
  getDocs, serverTimestamp, setDoc, updateDoc,
} from "firebase/firestore";
import "../styles/Achievements.css";
import "../styles/About.css";
import { useProject } from "../context/ProjectContext";
import { docProjectId } from "../utils/projects";
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

const EMPTY = { name: "", description: "", icon: "🏆", color: "#667EEA", conditionType: "station_count", conditionValue: 1, rewardInfo: "" };
const ICON_PRESETS = ["🏆","🥇","👣","🧭","🏃","🎉","👑","⭐","🔥","💎","🌟","🎯","🗺️","🏅","🎖️"];
const COLOR_PRESETS = ["#22c55e","#3b82f6","#f97316","#ec4899","#a855f7","#667EEA","#06b6d4","#eab308","#ef4444","#14b8a6"];

export default function Achievements() {
  const { activeProjectId } = useProject();
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
      // Megjelenítés az aktív településre szűrve (a hiányzó projectId az
      // alapértelmezett projektet jelenti). A seed a teljes kollekció ürességét
      // nézi, hogy a fix doc-id-k projektenként ne ütközzenek.
      setAchievements(list.filter((a) => docProjectId(a) === activeProjectId));
    } catch {
      showMsg("Hiba az adatok betoltésekor");
    } finally { setLoading(false); }
  }, [showMsg, activeProjectId]);

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
      rewardInfo: a.rewardInfo || "",
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
        rewardInfo: form.rewardInfo.trim(),
        projectId: activeProjectId,
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
              {a.rewardInfo && (
                <span className="ach-row-reward" title={a.rewardInfo}>🎁 Jutalom jár érte: {a.rewardInfo}</span>
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
        <div className="about-editor-backdrop" onClick={(e) => e.target === e.currentTarget && setShowForm(false)} role="presentation">
          <div className="about-editor-shell achievement-editor-shell" role="dialog" aria-modal="true" onClick={(e) => e.stopPropagation()}>
            <div className="about-editor-header">
              <div>
                <p className="about-editor-kicker">Jutalom szerkesztő</p>
                <h2>{editing ? "Jutalom szerkesztése" : "Új jutalom"}</h2>
                <p>A látogatóknak automatikusan feloldódik, ha teljesítik a feltételt. A csillaggal jelölt mező kötelező.</p>
              </div>
              <button className="about-editor-close" onClick={() => setShowForm(false)} type="button">Bezárás</button>
            </div>

            <div className="about-editor-body">
              <div className="about-editor-form">
                <section className="about-editor-section">
                  <div className="about-editor-section-head">
                    <span>1</span>
                    <div><h3>Alapadatok</h3><p>A jutalom neve és rövid magyarázata.</p></div>
                  </div>
                  <div className="field-group">
                    <label>Megnevezés <span className="required">*</span></label>
                    <input
                      type="text"
                      value={form.name}
                      onChange={(e) => setField("name", e.target.value)}
                      placeholder="pl. Felfedező"
                    />
                  </div>
                  <div className="field-group">
                    <label>Mire kap a látogató ezt a jutalmot?</label>
                    <input
                      type="text"
                      value={form.description}
                      onChange={(e) => setField("description", e.target.value)}
                      placeholder="pl. Beolvasott 3 QR-kódot"
                    />
                  </div>
                </section>

                <section className="about-editor-section">
                  <div className="about-editor-section-head">
                    <span>2</span>
                    <div><h3>Feltétel</h3><p>Mikor oldódjon fel automatikusan a jutalom.</p></div>
                  </div>
                  <div className={form.conditionType !== "manual" ? "field-row" : "field-group"}>
                    <div className="field-group">
                      <label>Feltétel típusa</label>
                      <select value={form.conditionType} onChange={(e) => setField("conditionType", e.target.value)}>
                        {CONDITION_TYPES.map((ct) => (
                          <option key={ct.value} value={ct.value}>{ct.label}</option>
                        ))}
                      </select>
                    </div>
                    {form.conditionType !== "manual" && (
                      <div className="field-group">
                        <label>Feltétel értéke (N){form.conditionType === "top_n" ? " – top hányadik" : " – minimum darab/pont"}</label>
                        <input
                          type="number"
                          min="1"
                          value={form.conditionValue}
                          onChange={(e) => setField("conditionValue", e.target.value)}
                        />
                      </div>
                    )}
                  </div>
                </section>

                <section className="about-editor-section">
                  <div className="about-editor-section-head">
                    <span>3</span>
                    <div><h3>Megjelenés</h3><p>Ikon és szín, ahogy a látogatónál megjelenik.</p></div>
                  </div>
                  <div className="field-group">
                    <label>Ikon</label>
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
                  </div>
                  <div className="field-group">
                    <label>Szín</label>
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
                  </div>
                  <div className="ach-preview">
                    <span className="ach-preview-icon" style={{ background: form.color }}>{form.icon}</span>
                    <span className="ach-preview-name">{form.name || "Jutalom neve"}</span>
                  </div>
                </section>

                <section className="about-editor-section">
                  <div className="about-editor-section-head">
                    <span>4</span>
                    <div><h3>Fizikai / kedvezmény jutalom</h3><p>Opcionális. Ha kitöltöd, a látogató a feloldás után ezt a szöveget felmutathatja a helyszínen (pl. recepción) igazolásként.</p></div>
                  </div>
                  <div className="field-group">
                    <label>Jutalom leírása</label>
                    <textarea
                      rows={3}
                      value={form.rewardInfo}
                      onChange={(e) => setField("rewardInfo", e.target.value)}
                      placeholder="pl. 10% kedvezmény egy fagylaltra a Fő téri cukrászdában"
                    />
                  </div>
                </section>

                {saveError && <div className="ach-save-error">{saveError}</div>}

                <div className="form-actions about-editor-actions">
                  <button className="btn-primary" onClick={handleSave} disabled={saving || !form.name.trim()} type="button">
                    {saving ? "Mentés..." : editing ? "💾 Mentés" : "💾 Hozzáadás"}
                  </button>
                  <button className="btn-secondary" onClick={() => setShowForm(false)} type="button">Mégse</button>
                </div>
              </div>
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





