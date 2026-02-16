import React, { useState, useEffect } from "react";
import { db } from "../firebaseConfig";
import { collection, getDocs } from "firebase/firestore";
import "../styles/Users.css";

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
      
      const usersSnapshot = await getDocs(collection(db, "user_progress"));
      const usersData = await Promise.all(
        usersSnapshot.docs.map(async (doc) => {
          const userData = doc.data();
          const completedStations = userData.completedStations?.length || 0;
          const totalStations = userData.totalStations || 0;
          const progress = totalStations > 0 ? Math.round((completedStations / totalStations) * 100) : 0;
          const points = completedStations * 10;

          return {
            id: doc.id,
            userId: userData.userId || doc.id,
            userName: userData.userName || "Ismeretlen",
            tripId: userData.tripId || "N/A",
            completedStations,
            totalStations,
            progress,
            points,
            lastUpdated: userData.lastUpdated?.toDate?.() || new Date(),
          };
        })
      );

      usersData.sort((a, b) => b.points - a.points);
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
        <h1>?? Felhasználók Haladása</h1>
        <p>Betöltés...</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="users-page">
        <h1>?? Felhasználók Haladása</h1>
        <p className="error">{error}</p>
      </div>
    );
  }

  const getRankBadge = (index) => {
    if (index === 0) return "??";
    if (index === 1) return "??";
    if (index === 2) return "??";
    return "#" + (index + 1);
  };

  return (
    <div className="users-page">
      <div className="page-header">
        <h1>?? Felhasználók Haladása</h1>
        <p>Az aktív felhasználók és az elért pontjaik</p>
      </div>

      {users.length === 0 ? (
        <div style={{ textAlign: "center", padding: "40px", color: "#999" }}>
          <p>Még nincsenek aktív felhasználók.</p>
        </div>
      ) : (
        <div className="users-ranking">
          <div className="users-header">
            <div className="rank-col">Rang</div>
            <div className="name-col">Felhasználó</div>
            <div className="points-col">Pontok</div>
            <div className="progress-col">Haladás</div>
            <div className="trips-col">Túra</div>
          </div>

          {users.map((user, index) => (
            <div key={user.id} className="user-row">
              <div className="rank-col">
                <div className="rank-badge">{getRankBadge(index)}</div>
              </div>
              <div className="name-col">
                <strong>{user.userName}</strong>
                <small>{user.userId}</small>
              </div>
              <div className="points-col">
                <span className="points-badge">{user.points} pont</span>
              </div>
              <div className="progress-col">
                <div className="progress-info">
                  <span className="progress-text">
                    {user.completedStations}/{user.totalStations}
                  </span>
                  <div className="progress-bar">
                    <div
                      className="progress-fill"
                      style={{ width: user.progress + "%" }}
                    ></div>
                  </div>
                  <span className="progress-percent">{user.progress}%</span>
                </div>
              </div>
              <div className="trips-col">
                {user.tripId !== "N/A" ? (
                  <span className="trip-tag">{user.tripId}</span>
                ) : (
                  <span className="trip-tag inactive">Nincs túra</span>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      <div className="users-stats">
        <div className="stat-box">
          <div className="stat-number">{users.length}</div>
          <div className="stat-label">Aktív felhasználó</div>
        </div>
        <div className="stat-box">
          <div className="stat-number">
            {Math.max(...users.map((u) => u.points), 0)}
          </div>
          <div className="stat-label">Max pontok</div>
        </div>
        <div className="stat-box">
          <div className="stat-number">
            {Math.round(
              users.reduce((sum, u) => sum + u.points, 0) / Math.max(users.length, 1)
            )}
          </div>
          <div className="stat-label">Átlag pontok</div>
        </div>
      </div>
    </div>
  );
}

export default Users;
