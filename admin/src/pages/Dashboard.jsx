import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
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

        const tripsSnapshot = await getDocs(collection(db, 'trips'));
        const tripsCount = tripsSnapshot.size;

        const activeTripsQuery = query(collection(db, 'trips'), where('isActive', '==', true));
        const activeTripsSnapshot = await getDocs(activeTripsQuery);
        const activeTripsCount = activeTripsSnapshot.size;

        const stationsSnapshot = await getDocs(collection(db, 'stations'));
        const stationsCount = stationsSnapshot.size;

        const usersSnapshot = await getDocs(collection(db, 'user_progress'));
        const usersCount = usersSnapshot.size;

        setStats({
          trips: tripsCount,
          stations: stationsCount,
          users: usersCount,
          activeTrips: activeTripsCount
        });
      } catch (err) {
        console.error('Hiba a betolteskor:', err);
        setError('Nem sikerult betolteni az adatokat: ' + err.message);
      } finally {
        setLoading(false);
      }
    };

    fetchStats();
  }, []);

  const statItems = [
    { key: 'trips', label: 'Osszes tura', value: stats.trips, hint: 'Letrehozott utak', tone: 'mint', badge: 'T' },
    { key: 'stations', label: 'Allomasok', value: stats.stations, hint: 'Pontok a terkepen', tone: 'sky', badge: 'A' },
    { key: 'users', label: 'Felhasznalok', value: stats.users, hint: 'Aktiv kovetes', tone: 'sand', badge: 'F' },
    { key: 'activeTrips', label: 'Aktiv turak', value: stats.activeTrips, hint: 'Most fut', tone: 'sun', badge: 'V' }
  ];

  const quickActions = [
    { to: '/trips', title: 'Turak', desc: 'Utvonalak, allomasok, szakaszok', badge: 'U' },
    { to: '/stations', title: 'Allomasok', desc: 'Helyszinek, pontok, leirasok', badge: 'A' },
    { to: '/map', title: 'Terkep', desc: 'Teljes terkep attekintes', badge: 'T' },
    { to: '/users', title: 'Felhasznalok', desc: 'Haladas, statisztikak', badge: 'F' }
  ];

  return (
    <div className="dashboard-shell">
      <header className="dashboard-hero">
        <div className="hero-copy">
          <p className="hero-kicker">Admin iranyitopult</p>
          <h1>Dashboard</h1>
        </div>
        <div className="hero-cta">
          <Link className="cta primary" to="/trips">Uj tura</Link>
          <Link className="cta ghost" to="/stations">Uj allomas</Link>
        </div>
      </header>

      {loading && (
        <div className="status-panel">
          <div className="status-card loading">
            <div className="pulse-line"></div>
            <div className="pulse-line short"></div>
            <div className="pulse-line"></div>
          </div>
        </div>
      )}

      {error && (
        <div className="status-panel">
          <div className="status-card error">
            <p>Hiba: {error}</p>
          </div>
        </div>
      )}

      {!loading && !error && (
        <div className="dashboard-grid">
          <section className="card kpi-card">
            <div className="card-header">
              <div>
                <h2>Statisztikak</h2>
                <p>Osszkep az adatbazisrol</p>
              </div>
              <span className="card-chip">Most</span>
            </div>
            <div className="kpi-grid">
              {statItems.map((item, index) => (
                <div key={item.key} className={`kpi-item tone-${item.tone}`} style={{ animationDelay: `${index * 90}ms` }}>
                  <div className="kpi-badge">{item.badge}</div>
                  <div className="kpi-meta">
                    <p className="kpi-label">{item.label}</p>
                    <p className="kpi-value">{item.value}</p>
                    <p className="kpi-hint">{item.hint}</p>
                  </div>
                </div>
              ))}
            </div>
          </section>

          <section className="card quick-card">
            <div className="card-header">
              <div>
                <h2>Gyors muveletek</h2>
                <p>Ugorj oda, ahova mennel</p>
              </div>
            </div>
            <div className="quick-grid">
              {quickActions.map((item) => (
                <Link key={item.to} to={item.to} className="quick-tile">
                  <span className="quick-badge">{item.badge}</span>
                  <div>
                    <p className="quick-title">{item.title}</p>
                    <p className="quick-desc">{item.desc}</p>
                  </div>
                </Link>
              ))}
            </div>
          </section>

          <section className="card activity-card">
            <div className="card-header">
              <div>
                <h2>Friss aktivitas</h2>
                <p>Azonnali statusz a rendszerrol</p>
              </div>
            </div>
            <div className="activity-list">
              <div className="activity-row">
                <span className="activity-dot"></span>
                <p>{stats.trips === 0 ? 'Meg nincs tura az adatbazisban.' : `${stats.trips} tura regisztralt.`}</p>
              </div>
              <div className="activity-row">
                <span className="activity-dot"></span>
                <p>{stats.stations === 0 ? 'Nincsenek allomasok feltoltve.' : `${stats.stations} allomas aktiv.`}</p>
              </div>
              <div className="activity-row">
                <span className="activity-dot"></span>
                <p>{stats.users === 0 ? 'Nincs aktiv felhasznalo a naplo szerint.' : `${stats.users} felhasznalo kovet.`}</p>
              </div>
            </div>
          </section>
        </div>
      )}
    </div>
  );
}

export default Dashboard;

