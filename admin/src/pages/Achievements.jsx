import React, { useEffect, useMemo, useState } from "react";
import { db } from "../firebaseConfig";
import {
  collection, collectionGroup, deleteDoc, doc,
  getDocs, serverTimestamp, setDoc, updateDoc,
} from "firebase/firestore";
import "../styles/Achievements.css";

const DEFAULTS = [
  { id: "first_steps",   name: "Első lépések",   desc: "Olvass be 1 QR-kódot",              icon: "👣", color: "#22c55e" },
  { id: "explorer",      name: "Felfedező",       desc: "Látogass meg 3 állomást",            icon: "🧭", color: "#3b82f6" },
  { id: "trail_hero",    name: "Túrahős",          desc: "Gyűjts össze 140 pontot",            icon: "🏃", color: "#f97316" },
  { id: "event_hunter",  name: "Eseményvadász",    desc: "Vegyél részt 1 eseményen",           icon: "🎉", color: "#ec4899" },
  { id: "local_legend",  name: "Helyi legenda",    desc: "Teljesíts egy teljes túrát",         icon: "👑", color: "#a855f7" },
];

const EMPTY_FORM = { name: "", desc: "", condition: "", icon: "🏆", color: "#667EEA" };

export default function Achievements() {
  const [loading, setLoading] = useState(true);
  const [achievements, setAchievements] = useState([]);
  const [users, setUsers] = useState([]);
  const [unlockedByUser, setUnlockedByUser] = useState(new Map());
  const [userFilter, setUserFilter] = useState("");
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(EMPTY_FORM);
  const [showForm, setShowForm] = useState(false);

  useEffect(() => { loadAll(); }, []);

  const loadAll = async () => {
    setLoading(true);
    try {
      const [achSnap, userSnap, unlockedSnap] = await Promise.all([
        getDocs(collection(db, "achievements")),
        getDocs(collection(db, "users")),
        getDocs(collectionGroup(db, "unlocked_achievements")),
      ]);

      let achList = achSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
      if (achList.length === 0) {
        await Promise.all(DEFAULTS.map((r) => setDoc(doc(db, "achievements", r.id), {
          name: r.name, description: r.desc, condition: "", icon: r.icon, color: r.color,
          unlockedCount: 0, createdAt: serverTimestamp(),
        })));
        const reload = await getDocs(collection(db, "achievements"));
        achList = reload.docs.map((d) => ({ id: d.id, ...d.data() }));
      }

      const map = new Map();
      unlockedSnap.docs.forEach((d) => {
        const uid = d.ref.path.split("/")[1];
        if (!map.has(uid)) map.set(uid, new Set());
        map.get(uid).add(d.id);
      });

      setAchievements(achList);
      setUsers(userSnap.docs.map((d) => ({ id: d.id, ...d.data() })));
      setUnlockedByUser(map);
    } finally { setLoading(false); }
  };

  const totalUnlocks = useMemo(() => [...unlockedByUser.values()].reduce((s, set) => s + set.size, 0), [unlockedByUser]);
  const activeUsers = useMemo(() => [...unlockedByUser.values()].filter((s) => s.size > 0).length, [unlockedByUser]);

  const leaderboard = useMemo(() =>
    users.map((u) => ({ id: u.id, name: u.displayName || u.name || u.email || "Ismeretlen", count: unlockedByUser.get(u.id)?.size || 0 }))
      .filter((u) => u.count > 0).sort((a, b) => b.count - a.count).slice(0, 10),
  [users, unlockedByUser]);

  const filteredUsers = useMemo(() => {
    const q = userFilter.trim().toLowerCase();
    if (!q) return [];
    return users.filter((u) => (u.displayName || u.name || "").toLowerCase().includes(q) || (u.email || "").toLowerCase().includes(q));
  }, [users, userFilter]);

  const openCreate = () => { setEditing(null); setForm(EMPTY_FORM); setShowForm(true); };
  const openEdit = (a) => { setEditing(a.id); setForm({ name: a.name || "", desc: a.description || "", condition: a.condition || "", icon: a.icon || "🏆", color: a.color || "#667EEA" }); setShowForm(true); };

  const saveAch = async () => {
    if (!form.name.trim()) return;
    const payload = { name: form.name.trim(), description: form.desc.trim(), condition: form.condition.trim(), icon: form.icon || "🏆", color: form.color || "#667EEA" };
    if (editing) { await updateDoc(doc(db, "achievements", editing), payload); }
    else { await setDoc(doc(db, "achievements", crypto.randomUUID()), { ...payload, unlockedCount: 0, createdAt: serverTimestamp() }); }
    setShowForm(false);
    await loadAll();
  };

  const deleteAch = async (id) => { if (window.confirm("Törlöd ezt az achievementet?")) { await deleteDoc(doc(db, "achievements", id)); await loadAll(); } };

  if (loading) return <div className="ach-page"><div className="ach-loading">⏳ Betöltés...</div></div>;

  return (
    <div className="ach-page">
      <div className="ach-hero">
        <div>
          <h1>🏆 Achievement rendszer</h1>
          <p>Feloldott jutalmak kezelése és áttekintése</p>
        </div>
        <button className="ach-btn-add" onClick={openCreate}>+ Új achievement</button>
      </div>

      {/* Stats row */}
      <div className="ach-stats">
        <div className="ach-stat"><span className="stat-num">{achievements.length}</span><span className="stat-lbl">Achievement típus</span></div>
        <div className="ach-stat"><span className="stat-num">{totalUnlocks}</span><span className="stat-lbl">Összes feloldás</span></div>
        <div className="ach-stat"><span className="stat-num">{activeUsers}</span><span className="stat-lbl">Aktív játékos</span></div>
        <div className="ach-stat"><span className="stat-num">{users.length}</span><span className="stat-lbl">Összes felhasználó</span></div>
      </div>

      {/* Achievement cards */}
      <section className="ach-section">
        <h2>🎖️ Achievement típusok</h2>
        <div className="ach-cards">
          {achievements.map((a) => {
            const unlockCount = [...unlockedByUser.values()].filter((s) => s.has(a.id)).length;
            const pct = users.length > 0 ? Math.round((unlockCount / users.length) * 100) : 0;
            return (
              <div key={a.id} className="ach-card" style={{ "--ach-color": a.color || "#667EEA" }}>
                <div className="ach-card-top">
                  <span className="ach-card-icon">{a.icon || "🏆"}</span>
                  <div className="ach-card-actions">
                    <button className="ach-btn-sm edit" onClick={() => openEdit(a)}>✏️</button>
                    <button className="ach-btn-sm del" onClick={() => deleteAch(a.id)}>🗑️</button>
                  </div>
                </div>
                <h3 className="ach-card-name">{a.name}</h3>
                <p className="ach-card-desc">{a.description}</p>
                {a.condition && <p className="ach-card-cond">📋 {a.condition}</p>}
                <div className="ach-progress">
                  <div className="ach-progress-bar" style={{ width: `${pct}%` }} />
                </div>
                <span className="ach-unlock-lbl">{unlockCount} felhasználó feloldotta ({pct}%)</span>
              </div>
            );
          })}
        </div>
      </section>

      {/* Leaderboard */}
      <section className="ach-section">
        <h2>🥇 Top játékosok</h2>
        {leaderboard.length === 0 ? <p className="ach-empty">Még senki nem oldott fel achievementet.</p> : (
          <div className="ach-leaderboard">
            {leaderboard.map((row, i) => (
              <div key={row.id} className="ach-lb-item">
                <span className={`ach-rank rank-${i + 1}`}>{i === 0 ? "🥇" : i === 1 ? "🥈" : i === 2 ? "🥉" : `#${i + 1}`}</span>
                <span className="ach-lb-name">{row.name}</span>
                <div className="ach-lb-badges">
                  {achievements.map((a) => (
                    <span key={a.id} className={`ach-badge${unlockedByUser.get(row.id)?.has(a.id) ? " unlocked" : " locked"}`} title={a.name} style={{ "--ach-color": a.color }}>
                      {a.icon}
                    </span>
                  ))}
                </div>
                <span className="ach-lb-count">{row.count}/{achievements.length}</span>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* User search */}
      <section className="ach-section">
        <h2>🔍 Felhasználó keresése</h2>
        <input className="ach-search" value={userFilter} onChange={(e) => setUserFilter(e.target.value)} placeholder="Keresés névben vagy emailben..." />
        {userFilter && filteredUsers.length === 0 && <p className="ach-empty">Nincs találat.</p>}
        {filteredUsers.map((u) => {
          const set = unlockedByUser.get(u.id) || new Set();
          return (
            <div key={u.id} className="ach-user-row">
              <div className="ach-user-info">
                <strong>{u.displayName || u.name || "Ismeretlen"}</strong>
                <span>{u.email}</span>
              </div>
              <div className="ach-lb-badges">
                {achievements.map((a) => (
                  <span key={a.id} className={`ach-badge${set.has(a.id) ? " unlocked" : " locked"}`} title={a.name} style={{ "--ach-color": a.color }}>{a.icon}</span>
                ))}
              </div>
              <span className="ach-lb-count">{set.size}/{achievements.length}</span>
            </div>
          );
        })}
      </section>

      {/* Form modal */}
      {showForm && (
        <div className="ach-modal-overlay" onClick={(e) => e.target === e.currentTarget && setShowForm(false)}>
          <div className="ach-modal">
            <div className="ach-modal-header">
              <h3>{editing ? "Achievement szerkesztése" : "Új achievement hozzáadása"}</h3>
              <button className="ach-modal-close" onClick={() => setShowForm(false)}>✕</button>
            </div>
            <div className="ach-modal-body">
              <label>Ikon (emoji)</label>
              <input value={form.icon} onChange={(e) => setForm((p) => ({ ...p, icon: e.target.value }))} placeholder="🏆" />
              <label>Megnevezés *</label>
              <input value={form.name} onChange={(e) => setForm((p) => ({ ...p, name: e.target.value }))} placeholder="pl. Felfedező" />
              <label>Leírás</label>
              <textarea rows="2" value={form.desc} onChange={(e) => setForm((p) => ({ ...p, desc: e.target.value }))} placeholder="Mit kell teljesíteni?" />
              <label>Feltétel (technikai)</label>
              <input value={form.condition} onChange={(e) => setForm((p) => ({ ...p, condition: e.target.value }))} placeholder="pl. stations >= 3" />
              <label>Szín</label>
              <div className="color-row">
                <input type="color" value={form.color} onChange={(e) => setForm((p) => ({ ...p, color: e.target.value }))} />
                <input type="text" value={form.color} onChange={(e) => setForm((p) => ({ ...p, color: e.target.value }))} placeholder="#667EEA" />
              </div>
            </div>
            <div className="ach-modal-footer">
              <button className="ach-btn-cancel" onClick={() => setShowForm(false)}>Mégse</button>
              <button className="ach-btn-save" onClick={saveAch}>💾 Mentés</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
