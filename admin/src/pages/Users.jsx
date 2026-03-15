import React, { useState, useEffect } from "react";
import { db } from "../firebaseConfig";
import { collection, getDocs } from "firebase/firestore";
import "../styles/Users.css";

const formatDate = (value) => {
  if (!value) return "N/A";
  try {
    const date = value?.toDate ? value.toDate() : new Date(value);
    if (Number.isNaN(date.getTime())) return "N/A";
    return date.toLocaleString("hu-HU");
  } catch {
    return "N/A";
  }
};

function Users() {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetchUsers();
  }, []);

  const fetchUsers = async () => {
    try {
      setLoading(true);
      setError(null);

      const [usersSnapshot, progressSnapshot] = await Promise.all([
        getDocs(collection(db, "users")),
        getDocs(collection(db, "user_progress")),
      ]);

      const progressRows = await Promise.all(
        progressSnapshot.docs.map(async (progressDoc) => {
          const progressData = progressDoc.data();

          let completedStations = 0;
          if (Array.isArray(progressData.completedStations)) {
            completedStations = progressData.completedStations.length;
          } else {
            try {
              const completedSnapshot = await getDocs(
                collection(db, "user_progress", progressDoc.id, "completed_stations")
              );
              completedStations = completedSnapshot.size;
            } catch {
              completedStations = Number(progressData.completedStationsCount || 0);
            }
          }

          const totalStations = Number(progressData.totalStations || 0);
          const progress =
            totalStations > 0
              ? Math.round((completedStations / totalStations) * 100)
              : 0;

          return {
            id: progressDoc.id,
            userId: progressData.userId || progressDoc.id,
            uid: progressData.userId || progressDoc.id,
            email: progressData.email || "",
            userName: progressData.userName || "Ismeretlen",
            role: "user",
            tripId: progressData.tripId || "N/A",
            completedStations,
            totalStations,
            progress,
            points: Number(progressData.points || completedStations * 10),
            lastUpdated: progressData.lastUpdated || null,
            createdAt: progressData.createdAt || null,
          };
        })
      );

      const combinedByKey = new Map();

      usersSnapshot.docs.forEach((userDoc) => {
        const userData = userDoc.data();
        const docId = userDoc.id;
        const email = (userData.email || (docId.includes("@") ? docId : "")).trim();
        const uid = (userData.uid || userData.userId || "").trim();
        const key = uid || email || docId;

        combinedByKey.set(key, {
          id: docId,
          userId: uid || docId,
          uid,
          email,
          userName: userData.name || userData.userName || email || "Ismeretlen",
          role: userData.role || "user",
          tripId: "N/A",
          completedStations: 0,
          totalStations: 0,
          progress: 0,
          points: 0,
          lastUpdated: userData.lastUpdated || null,
          createdAt: userData.createdAt || null,
        });
      });

      progressRows.forEach((progressUser) => {
        const possibleKeys = [
          progressUser.uid,
          progressUser.email,
          progressUser.id,
        ].filter(Boolean);

        const foundKey = possibleKeys.find((item) => combinedByKey.has(item));

        if (!foundKey) {
          const key = progressUser.uid || progressUser.email || progressUser.id;
          combinedByKey.set(key, {
            ...progressUser,
            role: "user",
            userName: progressUser.userName || progressUser.email || "Ismeretlen",
          });
          return;
        }

        const existing = combinedByKey.get(foundKey);
        combinedByKey.set(foundKey, {
          ...existing,
          ...progressUser,
          id: existing.id || progressUser.id,
          role: existing.role || progressUser.role || "user",
          userName:
            existing.userName !== "Ismeretlen"
              ? existing.userName
              : progressUser.userName,
          email: existing.email || progressUser.email,
          uid: existing.uid || progressUser.uid,
        });
      });

      const usersData = [...combinedByKey.values()].sort((a, b) => {
        if (b.points !== a.points) return b.points - a.points;
        return (a.email || a.userName).localeCompare(b.email || b.userName, "hu");
      });

      setUsers(usersData);
    } catch (err) {
      console.error("Hiba a felhasználók betöltésénél:", err);
      setError("Nem sikerült betölteni az adatokat");
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="users-page">
        <h1>👥 Felhasználók és szerver adatok</h1>
        <p>Betöltés...</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="users-page">
        <h1>👥 Felhasználók és szerver adatok</h1>
        <p className="error">{error}</p>
      </div>
    );
  }

  const getRankBadge = (index) => {
    if (index === 0) return "🥇";
    if (index === 1) return "🥈";
    if (index === 2) return "🥉";
    return "#" + (index + 1);
  };

  const adminCount = users.filter((item) => item.role === "admin").length;

  return (
    <div className="users-page">
      <div className="page-header">
        <h1>👥 Felhasználók és szerver adatok</h1>
        <p>Minden felhasználó (admin + app user) egy helyen, teljes áttekintéssel</p>
      </div>

      {users.length === 0 ? (
        <div style={{ textAlign: "center", padding: "40px", color: "#999" }}>
          <p>Még nincsenek felhasználói adatok.</p>
        </div>
      ) : (
        <div className="users-ranking">
          <div className="users-header">
            <div className="rank-col">Rang</div>
            <div className="name-col">Felhasználó</div>
            <div className="role-col">Szerepkör</div>
            <div className="points-col">Pontok</div>
            <div className="progress-col">Haladás</div>
            <div className="server-col">Szerver infó</div>
          </div>

          {users.map((user, index) => (
            <div key={user.id || user.userId} className="user-row">
              <div className="rank-col">
                <div className="rank-badge">{getRankBadge(index)}</div>
              </div>

              <div className="name-col">
                <strong>{user.userName}</strong>
                <small>{user.email || "Nincs email"}</small>
                <small>Túra: {user.tripId !== "N/A" ? user.tripId : "nincs"}</small>
              </div>

              <div className="role-col">
                <span className={`role-badge ${user.role === "admin" ? "admin" : "user"}`}>
                  {user.role === "admin" ? "admin" : "user"}
                </span>
              </div>

              <div className="points-col">
                <span className="points-badge">{user.points} pont</span>
              </div>

              <div className="progress-col">
                <span className="progress-text">
                  {user.completedStations}/{user.totalStations || "?"}
                </span>
                <div className="progress-bar">
                  <div
                    className="progress-fill"
                    style={{ width: `${Math.max(0, Math.min(100, user.progress))}%` }}
                  ></div>
                </div>
                <span className="progress-percent">{user.progress}%</span>
              </div>

              <div className="server-col">
                <code>uid: {user.uid || "N/A"}</code>
                <small>doc: {user.id || "N/A"}</small>
                <small>last: {formatDate(user.lastUpdated)}</small>
              </div>
            </div>
          ))}
        </div>
      )}

      <div className="users-stats">
        <div className="stat-box">
          <div className="stat-number">{users.length}</div>
          <div className="stat-label">Összes felhasználó</div>
        </div>
        <div className="stat-box">
          <div className="stat-number">{adminCount}</div>
          <div className="stat-label">Admin felhasználó</div>
        </div>
        <div className="stat-box">
          <div className="stat-number">{Math.max(...users.map((u) => u.points), 0)}</div>
          <div className="stat-label">Max pontszám</div>
        </div>
      </div>
    </div>
  );
}

export default Users;
