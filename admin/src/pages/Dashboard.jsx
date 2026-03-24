import React, { useState, useEffect, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { db } from '../firebaseConfig';
import { collection, getDocs, query, where } from 'firebase/firestore';
import '../styles/Dashboard.css';

function Dashboard() {
  const [stats, setStats] = useState({
    trips: 0, stations: 0, users: 0, trackedUsers: 0,
    activeTrips: 0, achievements: 0, totalPoints: 0, averagePoints: 0
  });
  const [topAchievements, setTopAchievements] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const fetchStats = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const [
        tripsSnapshot, activeTripsSnapshot, stationsSnapshot,
        usersSnapshot, userProgressSnapshot, achievementsSnapshot,
      ] = await Promise.all([
        getDocs(collection(db, 'trips')),
        getDocs(query(collection(db, 'trips'), where('isActive', '==', true))),
        getDocs(collection(db, 'stations')),
        getDocs(collection(db, 'users')),
        getDocs(collection(db, 'user_progress')),
        getDocs(collection(db, 'achievements')),
      ]);

      const totalPts = userProgressSnapshot.docs.reduce((sum, doc) => sum + (doc.data().totalPoints || 0), 0);
      const avgPts = userProgressSnapshot.size > 0 ? Math.round(totalPts / userProgressSnapshot.size) : 0;

      setStats({
        trips: tripsSnapshot.size, stations: stationsSnapshot.size,
        users: usersSnapshot.size, trackedUsers: userProgressSnapshot.size,
        activeTrips: activeTripsSnapshot.size, achievements: achievementsSnapshot.size,
        totalPoints: totalPts, averagePoints: avgPts,
      });

      const achData = achievementsSnapshot.docs
        .map(d => ({ id: d.id, ...d.data() }))
        .sort((a, b) => (b.unlockedCount || 0) - (a.unlockedCount || 0))
        .slice(0, 3);
      setTopAchievements(achData);
    } catch (err) {
      console.error('Dashboard fetch error:', err);
      setError('Nem sikerült betölteni az adatokat: ' + err.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchStats(); }, [fetchStats]);

  const statItems = [
    { key: 'trips',        label: 'Összes túra',    value: stats.trips,        hint: 'Létrehozott utak',         tone: 'mint', badge: 'T' },
    { key: 'stations',     label: 'Állomások',      value: stats.stations,     hint: 'Pontok a térképen',        tone: 'sky',  badge: 'A' },
    { key: 'activeTrips',  label: 'Aktív túrák',    value: stats.activeTrips,  hint: 'Most aktív',               tone: 'sun',  badge: 'V' },
    { key: 'users',        label: 'Felhasználók',   value: stats.users,        hint: 'users collection',         tone: 'sand', badge: 'F' },
    { key: 'trackedUsers', label: 'Haladást követ', value: stats.trackedUsers, hint: 'user_progress rekord',     tone: 'rose', badge: 'H' },
    { key: 'achievements', label: 'Jutalmak',       value: stats.achievements, hint: 'Létrehozott jutalmak',     tone: 'mint', badge: 'J' },
    { key: 'totalPoints',  label: 'Össz. pontok',    value: stats.totalPoints,  hint: 'Minden felhasználótól',    tone: 'sky',  badge: 'P' },
    { key: 'avgPoints',    label: 'Átlag pont',     value: stats.averagePoints,hint: 'Felhasználónként',         tone: 'sun',  badge: '~' },
  ];

  const quickActions = [
    { to: '/trips',    title: 'Túrák',        desc: 'Útvonalak, állomások, szakaszok', badge: 'U' },
    { to: '/stations', title: 'Állomások',    desc: 'Helyszínek, pontok, leírások',    badge: 'A' },
    { to: '/map',      title: 'Térkép',       desc: 'Teljes térkép áttekintés',        badge: 'T' },
    { to: '/users',    title: 'Felhasználók', desc: 'Haladás, statisztikák',           badge: 'F' },
  ];

  return (
    <div className="dashboard-shell">
      <header className="dashboard-hero">
        <div className="hero-copy">
          <p className="hero-kicker">Admin irányítópult</p>
          <h1>Dashboard</h1>
        </div>
        <div className="hero-cta">
          <button className="cta ghost" onClick={fetchStats} disabled={loading} style={{ cursor: loading ? 'not-allowed' : 'pointer' }}>
            {loading ? '⟳ Frissítés...' : '⟳ Frissítés'}
          </button>
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
            <button className="cta ghost" onClick={fetchStats} style={{ marginTop: '8px' }}>Ujraprobalas</button>
          </div>
        </div>
      )}

      {!loading && !error && (
        <div className="dashboard-grid">
          <section className="card kpi-card">
            <div className="card-header">
              <div>
                <h2>Statisztikák</h2>
                <p>Összkép az adatbázisról</p>
              </div>
              <span className="card-chip">Most</span>
            </div>
            <div className="kpi-grid">
              {statItems.map((item, index) => (
                <div key={item.key} className={`kpi-item tone-${item.tone}`} style={{ animationDelay: `${index * 60}ms` }}>
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
                <h2>Gyors műveletek</h2>
                <p>Ugorj oda, ahová mennél</p>
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

          {topAchievements.length > 0 && (
            <section className="card achievement-card">
              <div className="card-header">
                <div>
                  <h2>🏆 Legnépszerűbb jutalmak</h2>
                  <p>Legtöbbet feloldott jutalmak</p>
                </div>
                <Link className="card-chip" to="/achievements">Összes</Link>
              </div>
              <div className="achievement-list">
                {topAchievements.map((a, i) => (
                  <div key={a.id} className="achievement-row">
                    <span className="achievement-rank">#{i + 1}</span>
                    <span className="achievement-icon">{a.icon || '🏆'}</span>
                    <div className="achievement-info">
                      <p className="achievement-name">{a.name}</p>
                      <p className="achievement-desc">{a.description}</p>
                    </div>
                    <span className="achievement-count">{a.unlockedCount || 0}x</span>
                  </div>
                ))}
              </div>
            </section>
          )}

          <section className="card activity-card">
            <div className="card-header">
              <div>
                <h2>Friss aktivitás</h2>
                <p>Azonnali státusz a rendszerről</p>
              </div>
            </div>
            <div className="activity-list">
              <div className="activity-row"><span className="activity-dot"></span>
                <p>{stats.trips === 0 ? 'Még nincs túra az adatbázisban.' : `${stats.trips} tura regisztralt, ${stats.activeTrips} aktiv.`}</p>
              </div>
              <div className="activity-row"><span className="activity-dot"></span>
                <p>{stats.stations === 0 ? 'Nincsenek állomások feltöltve.' : `${stats.stations} állomás aktív.`}</p>
              </div>
              <div className="activity-row"><span className="activity-dot"></span>
                <p>{stats.trackedUsers === 0 ? 'Nincs haladási rekord.' : `${stats.trackedUsers} játékos követ haladást, átlag ${stats.averagePoints} ponttal.`}</p>
              </div>
              <div className="activity-row"><span className="activity-dot"></span>
                <p>{stats.achievements === 0 ? 'Nincsenek jutalmak beállítva.' : `${stats.achievements} jutalom létrehozva.`}</p>
              </div>
            </div>
          </section>
        </div>
      )}
    </div>
  );
}

export default Dashboard;
