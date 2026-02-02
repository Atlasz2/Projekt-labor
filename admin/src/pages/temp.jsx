import React, { useState, useEffect } from 'react';
import { db } from '../firebaseConfig';
import { collection, getDocs, query, where } from 'firebase/firestore';
import '../styles/Dashboard.css';

function Dashboard() {
  const [stats, setStats] = useState({
    trips: 0,
    stations: 0,
    users: 0,
    activeTrips: 0
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    const fetchStats = async () => {
      try {
        setLoading(true);
        setError(null);

        // Túrák száma
        const tripsSnapshot = await getDocs(collection(db, 'trips'));
        const tripsCount = tripsSnapshot.size;

        // Aktív túrák száma
        const activeTripsQuery = query(collection(db, 'trips'), where('isActive', '==', true));
        const activeTripsSnapshot = await getDocs(activeTripsQuery);
        const activeTripsCount = activeTripsSnapshot.size;

        // Állomások száma
        const stationsSnapshot = await getDocs(collection(db, 'stations'));
        const stationsCount = stationsSnapshot.size;

        // Felhasználók száma
        const usersSnapshot = await getDocs(collection(db, 'user_progress'));
        const usersCount = usersSnapshot.size;

        setStats({
          trips: tripsCount,
          stations: stationsCount,
          users: usersCount,
          activeTrips: activeTripsCount
        });
      } catch (err) {
        console.error('Hiba a statisztikák betöltésekor:', err);
        setError('Nem sikerült betölteni a statisztikákat');
      } finally {
        setLoading(false);
      }
    };

    fetchStats();
  }, []);

  if (loading) {
    return (
      <div className="dashboard">
        <h1>Dashboard</h1>
        <p>Betöltés...</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="dashboard">
        <h1>Dashboard</h1>
        <p className="error">{error}</p>
      </div>
    );
  }

  return (
    <div className="dashboard">
      <h1>Dashboard</h1>

      <div className="stats-grid">
        <div className="stat-card">
          <span className="stat-icon">🚶</span>
          <h3>Összes túra</h3>
          <p className="stat-value">{stats.trips}</p>
        </div>
        <div className="stat-card">
          <span className="stat-icon">📍</span>
          <h3>Összes állomás</h3>
          <p className="stat-value">{stats.stations}</p>
        </div>
        <div className="stat-card">
          <span className="stat-icon">👥</span>
          <h3>Felhasználók</h3>
          <p className="stat-value">{stats.users}</p>
        </div>
        <div className="stat-card">
          <span className="stat-icon">✅</span>
          <h3>Aktív túrák</h3>
          <p className="stat-value">{stats.activeTrips}</p>
        </div>
      </div>

      <div className="recent-activity">
        <h2>Friss aktivitás</h2>
        <div className="activity-timeline">
          {stats.trips === 0 && <p>Még nincsenek túrák az adatbázisban.</p>}
        </div>
      </div>
    </div>
  );
}

export default Dashboard;
