import React, { useEffect, useMemo, useState } from "react";
import { db } from "../firebaseConfig";
import {
  addDoc,
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
} from "firebase/firestore";
import "../styles/Achievements.css";

const DEFAULT_ACHIEVEMENTS = [
  { id: "first_steps", name: "Első lépések", description: "Olvass be 1 QR-kódot", condition: "stations >= 1 vagy events >= 1", icon: "👣", color: "#4CAF50" },
  { id: "explorer", name: "Felfedező", description: "Látogass meg legalább 3 állomást", condition: "stations >= 3", icon: "🧭", color: "#2196F3" },
  { id: "trail_hero", name: "Túrahős", description: "Gyűjts össze legalább 140 pontot", condition: "points >= 140", icon: "🏃", color: "#FF9800" },
  { id: "event_hunter", name: "Eseményvadász", description: "Vegyél részt 1 eseményen", condition: "events >= 1", icon: "🎉", color: "#E91E63" },
  { id: "local_legend", name: "Helyi legenda", description: "Teljesíts egy teljes túrát", condition: "tripCompleted == true", icon: "👑", color: "#9C27B0" },
];

function Achievements() {
  const [isLoading, setIsLoading] = useState(true);
  const [achievements, setAchievements] = useState([]);
  const [users, setUsers] = useState([]);
  const [unlockedByUser, setUnlockedByUser] = useState(new Map());
  const [userFilter, setUserFilter] = useState("");

  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState({ name: "", description: "", condition: "", icon: "🏆", color: "#667EEA" });

  useEffect(() => {
    loadAll();
  }, []);

  const loadAll = async () => {
    try {
      setIsLoading(true);

      const [achSnap, userSnap, unlockedSnap] = await Promise.all([
        getDocs(collection(db, "achievements")),
        getDocs(collection(db, "users")),
        getDocs(collectionGroup(db, "unlocked_achievements")),
      ]);

      let achList = achSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
      if (achList.length === 0) {
        for (const row of DEFAULT_ACHIEVEMENTS) {
          await setDoc(doc(db, "achievements", row.id), {
            name: row.name,
            description: row.description,
            condition: row.condition,
            icon: row.icon,
            color: row.color,
            unlockedCount: 0,
            createdAt: serverTimestamp(),
          });
        }
        const reload = await getDocs(collection(db, "achievements"));
        achList = reload.docs.map((d) => ({ id: d.id, ...d.data() }));
      }

      const usersList = userSnap.docs.map((d) => ({ id: d.id, ...d.data() }));

      const map = new Map();
      unlockedSnap.docs.forEach((d) => {
        const parts = d.ref.path.split("/");
        const uid = parts[1];
        if (!map.has(uid)) map.set(uid, new Set());
        map.get(uid).add(d.id);
      });

      setAchievements(achList);
      setUsers(usersList);
      setUnlockedByUser(map);
    } catch (e) {
      console.error("Achievement load error:", e);
    } finally {
      setIsLoading(false);
    }
  };

  const leaderboard = useMemo(() => {
    return users
      .map((u) => {
        const set = unlockedByUser.get(u.id) || new Set();
        return {
          id: u.id,
          name: u.displayName || u.name || u.email || "Ismeretlen",
          count: set.size,
        };
      })
      .filter((u) => u.count > 0)
      .sort((a, b) => b.count - a.count)
      .slice(0, 12);
  }, [users, unlockedByUser]);

  const filteredUsers = useMemo(() => {
    const term = userFilter.trim().toLowerCase();
    if (!term) return [];
    return users.filter((u) => {
      const name = (u.displayName || u.name || "").toLowerCase();
      const email = (u.email || "").toLowerCase();
      return name.includes(term) || email.includes(term);
    });
  }, [users, userFilter]);

  const openCreate = () => {
    setEditing(null);
    setForm({ name: "", description: "", condition: "", icon: "🏆", color: "#667EEA" });
  };

  const openEdit = (row) => {
    setEditing(row.id);
    setForm({
      name: row.name || "",
      description: row.description || "",
      condition: row.condition || "",
      icon: row.icon || "🏆",
      color: row.color || "#667EEA",
    });
  };

  const saveAchievement = async () => {
    if (!form.name.trim()) return;
    const payload = {
      name: form.name.trim(),
      description: form.description.trim(),
      condition: form.condition.trim(),
      icon: form.icon.trim() || "🏆",
      color: form.color.trim() || "#667EEA",
    };

    if (editing) {
      await updateDoc(doc(db, "achievements", editing), payload);
    } else {
      await addDoc(collection(db, "achievements"), {
        ...payload,
        unlockedCount: 0,
        createdAt: serverTimestamp(),
      });
    }

    openCreate();
    await loadAll();
  };

  const removeAchievement = async (id) => {
    await deleteDoc(doc(db, "achievements", id));
    await loadAll();
  };

  if (isLoading) {
    return <div className="achievements-container">Betöltés...</div>;
  }

  return (
    <div className="achievements-container">
      <h1>🏆 Achievement rendszer</h1>

      <section className="section">
        <h2>Kezelés</h2>
        <div className="editor-grid">
          <input value={form.name} onChange={(e) => setForm((p) => ({ ...p, name: e.target.value }))} placeholder="Név" />
          <input value={form.description} onChange={(e) => setForm((p) => ({ ...p, description: e.target.value }))} placeholder="Leírás" />
          <input value={form.condition} onChange={(e) => setForm((p) => ({ ...p, condition: e.target.value }))} placeholder="Feltétel" />
          <input value={form.icon} onChange={(e) => setForm((p) => ({ ...p, icon: e.target.value }))} placeholder="Ikon (emoji)" />
          <input value={form.color} onChange={(e) => setForm((p) => ({ ...p, color: e.target.value }))} placeholder="#szín" />
          <div className="editor-actions">
            <button className="btn-primary" onClick={saveAchievement}>{editing ? "Frissítés" : "Új achievement"}</button>
            <button className="btn-secondary" onClick={openCreate}>Törlés űrlapból</button>
          </div>
        </div>
      </section>

      <section className="section">
        <h2>Achievement típusok</h2>
        <div className="achievements-grid">
          {achievements.map((a) => (
            <div key={a.id} className="achievement-card" style={{ borderLeft: `4px solid ${a.color || "#667EEA"}` }}>
              <div className="achievement-icon">{a.icon || "🏆"}</div>
              <h3>{a.name}</h3>
              <p>{a.description}</p>
              <p className="condition">{a.condition}</p>
              <div className="card-actions">
                <button className="btn-edit" onClick={() => openEdit(a)}>Szerkesztés</button>
                <button className="btn-delete" onClick={() => removeAchievement(a.id)}>Törlés</button>
              </div>
            </div>
          ))}
        </div>
      </section>

      <section className="section">
        <h2>Top feloldók</h2>
        <div className="leaderboard">
          {leaderboard.length === 0 ? <p>Nincs még feloldás.</p> : leaderboard.map((row, idx) => (
            <div key={row.id} className="leaderboard-item">
              <span className="rank">#{idx + 1}</span>
              <span className="name">{row.name}</span>
              <span className="count">{row.count} db</span>
            </div>
          ))}
        </div>
      </section>

      <section className="section">
        <h2>Felhasználó achievement állapot</h2>
        <input className="search-input" value={userFilter} onChange={(e) => setUserFilter(e.target.value)} placeholder="Keresés név/email" />
        {filteredUsers.map((u) => {
          const unlocked = unlockedByUser.get(u.id) || new Set();
          return (
            <div key={u.id} className="user-achievement-item">
              <div className="user-info">
                <h4>{u.displayName || u.name || "Ismeretlen"}</h4>
                <p>{u.email || ""}</p>
              </div>
              <div className="user-achievements">
                {achievements.map((a) => (
                  <div key={`${u.id}-${a.id}`} className={`achievement-badge ${unlocked.has(a.id) ? "unlocked" : "locked"}`} title={a.name}>
                    {a.icon || "🏆"}
                  </div>
                ))}
              </div>
            </div>
          );
        })}
      </section>
    </div>
  );
}

export default Achievements;
