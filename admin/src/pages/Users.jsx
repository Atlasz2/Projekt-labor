import React, { useState, useEffect } from "react";
import { db } from "../firebaseConfig";
import { collection, getDocs } from "firebase/firestore";
import "../styles/Users.css";
import StateCard from "../components/StateCard";

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
  async function fetchUsers() {
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
            // Avoid N+1 subcollection query: use the denormalized count field if available
            completedStations = Number(progressData.completedStationsCount || 0);
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
            points: Number(progressData.totalPoints ?? progressData.points ?? 0),
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
    } catch {
      setError("Nem sikerült betölteni az adatokat");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    const timer = setTimeout(() => {
      void fetchUsers();
    }, 0);

    return () => clearTimeout(timer);
  }, []);

  if (loading) {
    return (
      <div className="users-page">
        <div className="page-header">
          <h1>👥 Felhasználók</h1>
          <p>Regisztrált fiókok és haladásuk áttekintése</p>
        </div>
        <StateCard
          variant="loading"
          icon="⏳"
          title="Felhasználók betöltése..."
          description="A rendszer összegyűjti a users és user_progress adatait."
        />
      </div>
    );
  }

  if (error) {
    return (
      <div className="users-page">
        <div className="page-header">
          <h1>👥 Felhasználók</h1>
          <p>Regisztrált fiókok és haladásuk áttekintése</p>
        </div>
        <StateCard
          icon="⚠️"
          title="Nem sikerült betölteni a felhasználókat"
          description={error}
          actionLabel="Újrapróbálás"
          onAction={() => {
            void fetchUsers();
          }}
        />
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
        <h1>👥 Felhasználók</h1>
        <p>Regisztrált fiókok és haladásuk áttekintése</p>
      </div>

      <div className="users-stats">
        <div className="stat-box">
          <div className="stat-number">{users.length}</div>
          <div className="stat-label">Összes felhasználó</div>
        </div>
        <div className="stat-box">
          <div className="stat-number">{adminCount}</div>
          <div className="stat-label">Admin</div>
        </div>
        <div className="stat-box">
          <div className="stat-number">{Math.max(...users.map((u) => u.points), 0)}</div>
          <div className="stat-label">Legtöbb pont</div>
        </div>
      </div>

      {users.length === 0 ? (
        <StateCard
          icon="👥"
          title="Nincsenek még felhasználók"
          description="Az alkalmazás még nem kapott felhasználói adatot. Amint érkezik új rekord, itt jelenik meg a ranglista."
        />
      ) : (
        <div className="users-ranking">
          <div className="users-header">
            <div className="rank-col">Rang</div>
            <div className="name-col">Felhasználó</div>
            <div className="role-col">Szerepkör</div>
            <div className="points-col">Pontok</div>
            <div className="progress-col">Haladás</div>
            <div className="activity-col">Utolsó aktivitás</div>
          </div>

          {users.map((user, index) => (
            <div
              key={user.id || user.userId}
              className={`user-row${index < 3 ? " top" : ""}`}
            >
              <div className="rank-col">
                <div className="rank-badge">{getRankBadge(index)}</div>
              </div>

              <div className="name-col">
                <strong title={user.uid ? `uid: ${user.uid}` : undefined}>
                  {user.userName}
                </strong>
                <small>{user.email || "Nincs email"}</small>
              </div>

              <div className="role-col">
                <span className={`role-badge ${user.role === "admin" ? "admin" : "user"}`}>
                  {user.role === "admin" ? "Admin" : "Felhasználó"}
                </span>
              </div>

              <div className="points-col">
                <span className="points-badge">{user.points} pont</span>
              </div>

              <div className="progress-col">
                <div className="progress-bar">
                  <div
                    className="progress-fill"
                    style={{ width: `${Math.max(0, Math.min(100, user.progress))}%` }}
                  ></div>
                </div>
                <span className="progress-text">
                  {user.completedStations}/{user.totalStations || "?"} állomás · {user.progress}%
                </span>
              </div>

              <div className="activity-col" title={`doc: ${user.id || "N/A"}`}>
                {formatDate(user.lastUpdated)}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export default Users;


