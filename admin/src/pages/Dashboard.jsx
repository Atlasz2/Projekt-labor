import PropTypes from 'prop-types';
import React, { useState, useEffect, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { db } from '../firebaseConfig';
import {
  collection, getDocs, query, doc, setDoc, orderBy, limit,
  getCountFromServer, getAggregateFromServer, sum, count,
} from 'firebase/firestore';
import StateCard from '../components/StateCard';
import '../styles/Dashboard.css';

const TREND_METRICS = [
  { key: 'totalPoints', label: 'Összpontszám', color: '#5b6f4c' },
  { key: 'users',       label: 'Felhasználók', color: '#2563eb' },
  { key: 'stations',    label: 'Állomások',    color: '#d97706' },
];

function TrendChart({ points, color }) {
  if (points.length < 2) return null;

  const W = 560;
  const H = 150;
  const P = 14;
  const values = points.map((p) => p.value);
  const max = Math.max(...values);
  const min = Math.min(...values);
  const range = max - min || 1;
  const stepX = (W - P * 2) / (points.length - 1);

  const coords = points.map((p, i) => {
    const x = P + i * stepX;
    const y = H - P - ((p.value - min) / range) * (H - P * 2);
    return [x, y];
  });

  const line = coords
    .map(([x, y], i) => `${i === 0 ? 'M' : 'L'}${x.toFixed(1)},${y.toFixed(1)}`)
    .join(' ');
  const area = `${line} L${coords[coords.length - 1][0].toFixed(1)},${H - P} L${coords[0][0].toFixed(1)},${H - P} Z`;
  const last = coords[coords.length - 1];

  return (
    <svg className="trend-svg" viewBox={`0 0 ${W} ${H}`} role="img" aria-label="Trend grafikon">
      <defs>
        <linearGradient id="trendFill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity="0.28" />
          <stop offset="100%" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={area} fill="url(#trendFill)" />
      <path d={line} fill="none" stroke={color} strokeWidth="2.5" strokeLinejoin="round" strokeLinecap="round" />
      <circle cx={last[0]} cy={last[1]} r="4.5" fill={color} />
    </svg>
  );
}

TrendChart.propTypes = {
  points: PropTypes.arrayOf(PropTypes.object).isRequired,
  color: PropTypes.string.isRequired,
};

function Dashboard() {
  const [stats, setStats] = useState({
    trips: 0, stations: 0, users: 0, trackedUsers: 0,
    activeTrips: 0, achievements: 0, totalPoints: 0, averagePoints: 0,
    assignedStations: 0,
  });
  const [topAchievements, setTopAchievements] = useState([]);
  const [topPlayers, setTopPlayers] = useState([]);
  const [trendData, setTrendData] = useState([]);
  const [trendMetric, setTrendMetric] = useState('totalPoints');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const fetchStats = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const progressCol = collection(db, 'user_progress');

      // Counts and the points sum are computed server-side, so the dashboard does
      // not download every user / progress document — this scales to thousands of
      // users. Only the top 5 progress docs are fetched (for the leaderboard).
      const [
        tripsSnapshot,
        stationsSnapshot,
        achievementsSnapshot,
        usersCount,
        progressAgg,
        topPlayersSnapshot,
      ] = await Promise.all([
        getDocs(collection(db, 'trips')),
        getDocs(collection(db, 'stations')),
        getDocs(collection(db, 'achievements')),
        getCountFromServer(collection(db, 'users')),
        getAggregateFromServer(progressCol, { total: sum('totalPoints'), n: count() }),
        getDocs(query(progressCol, orderBy('totalPoints', 'desc'), limit(5))),
      ]);

      const activeTrips = tripsSnapshot.docs.filter((d) => d.data().isActive === true).length;
      const totalPts = progressAgg.data().total || 0;
      const trackedUsers = progressAgg.data().n || 0;
      const usersTotal = usersCount.data().count;
      const avgPts = trackedUsers > 0 ? Math.round(totalPts / trackedUsers) : 0;
      const assignedStations = stationsSnapshot.docs.filter((d) => d.data().tripId).length;

      setStats({
        trips: tripsSnapshot.size,
        stations: stationsSnapshot.size,
        users: usersTotal,
        trackedUsers,
        activeTrips,
        achievements: achievementsSnapshot.size,
        totalPoints: totalPts,
        averagePoints: avgPts,
        assignedStations,
      });

      const achData = achievementsSnapshot.docs
        .map((d) => ({ id: d.id, ...d.data() }))
        .sort((a, b) => (b.unlockedCount || 0) - (a.unlockedCount || 0))
        .slice(0, 3);
      setTopAchievements(achData);

      const playerData = topPlayersSnapshot.docs.map((d) => {
        const data = d.data();
        return {
          id: d.id,
          name: data.userName || data.email || 'Ismeretlen játékos',
          email: data.email || '',
          points: Number(data.totalPoints ?? data.points ?? 0),
        };
      });
      setTopPlayers(playerData);

      // Persist a once-per-day snapshot so the dashboard can show real trends over time.
      // Non-blocking: if security rules forbid the write, the trend simply stays empty.
      const today = new Date().toISOString().slice(0, 10);
      try {
        await setDoc(
          doc(db, 'stats_daily', today),
          {
            date: today,
            trips: tripsSnapshot.size,
            stations: stationsSnapshot.size,
            users: usersTotal,
            trackedUsers,
            totalPoints: totalPts,
            achievements: achievementsSnapshot.size,
            updatedAt: Date.now(),
          },
          { merge: true },
        );
      } catch {
        // ignore — trends are optional
      }

      try {
        const trendSnapshot = await getDocs(
          query(collection(db, 'stats_daily'), orderBy('date', 'desc'), limit(14)),
        );
        setTrendData(trendSnapshot.docs.map((d) => d.data()).reverse());
      } catch {
        setTrendData([]);
      }
    } catch (err) {
      setError('Nem sikerült betölteni az adatokat: ' + err.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    const timer = setTimeout(() => {
      void fetchStats();
    }, 0);

    return () => clearTimeout(timer);
  }, [fetchStats]);

  const statItems = [
    { key: 'trips', label: 'Összes túra', value: stats.trips, hint: 'Létrehozott utak', tone: 'mint', badge: 'T' },
    { key: 'stations', label: 'Állomások', value: stats.stations, hint: 'Pontok a térképen', tone: 'sky', badge: 'A' },
    { key: 'activeTrips', label: 'Aktív túrák', value: stats.activeTrips, hint: 'Most aktív', tone: 'sun', badge: 'V' },
    { key: 'users', label: 'Felhasználók', value: stats.users, hint: 'Regisztrált fiókok', tone: 'sand', badge: 'F' },
    { key: 'trackedUsers', label: 'Követett haladás', value: stats.trackedUsers, hint: 'Haladási rekordok', tone: 'rose', badge: 'H' },
    { key: 'achievements', label: 'Jutalmak', value: stats.achievements, hint: 'Létrehozott jutalmak', tone: 'mint', badge: 'J' },
    { key: 'totalPoints', label: 'Össz. pontok', value: stats.totalPoints, hint: 'Minden felhasználótól', tone: 'sky', badge: 'P' },
    { key: 'avgPoints', label: 'Átlag pont', value: stats.averagePoints, hint: 'Felhasználónként', tone: 'sun', badge: '~' },
  ];

  const quickActions = [
    { to: '/trips', title: 'Túrák', desc: 'Útvonalak, állomások, szakaszok', badge: 'U' },
    { to: '/stations', title: 'Állomások', desc: 'Helyszínek, pontok, leírások', badge: 'A' },
    { to: '/map', title: 'Térkép', desc: 'Teljes térképáttekintés', badge: 'T' },
    { to: '/users', title: 'Felhasználók', desc: 'Haladás és statisztikák', badge: 'F' },
  ];

  const activeMetric = TREND_METRICS.find((m) => m.key === trendMetric) || TREND_METRICS[0];
  const metricPoints = trendData.map((row) => ({
    date: row.date,
    value: Number(row[trendMetric] || 0),
  }));
  const currentValue = metricPoints.length ? metricPoints[metricPoints.length - 1].value : 0;
  const previousValue = metricPoints.length > 1
    ? metricPoints[metricPoints.length - 2].value
    : currentValue;
  const trendDelta = currentValue - previousValue;

  return (
    <div className="dashboard-shell">
      <header className="dashboard-hero">
        <div className="hero-copy">
          <p className="hero-kicker">Admin irányítópult</p>
          <h1>Dashboard</h1>
        </div>
        <div className="hero-cta">
          <button className="cta ghost" onClick={() => void fetchStats()} disabled={loading} style={{ cursor: loading ? 'not-allowed' : 'pointer' }}>
            {loading ? '⟳ Frissítés...' : '⟳ Frissítés'}
          </button>
          <Link className="cta primary" to="/trips">Új túra</Link>
          <Link className="cta ghost" to="/stations">Új állomás</Link>
        </div>
      </header>

      {loading && (
        <StateCard
          variant="loading"
          icon="📊"
          title="Dashboard betöltése..."
          description="A statisztikák és gyorsműveletek előkészítése folyamatban van."
        />
      )}

      {error && (
        <StateCard
          variant="empty"
          icon="⚠️"
          title="Nem sikerült betölteni a Dashboardot"
          description={error}
          actionLabel="Újrapróbálás"
          onAction={() => {
            void fetchStats();
          }}
        />
      )}

      {!loading && !error && (
        <div className="dashboard-grid">
          <section className="card trend-card">
            <div className="card-header">
              <div>
                <h2>📈 Trend</h2>
                <p>Az utóbbi {trendData.length} napi pillanatkép alapján</p>
              </div>
              <div className="trend-metric-tabs">
                {TREND_METRICS.map((m) => (
                  <button
                    key={m.key}
                    type="button"
                    className={`trend-tab${trendMetric === m.key ? ' active' : ''}`}
                    onClick={() => setTrendMetric(m.key)}
                  >
                    {m.label}
                  </button>
                ))}
              </div>
            </div>

            {trendData.length < 2 ? (
              <p className="trend-empty">
                📅 A trend épül — legalább két különböző nap pillanatképe szükséges.
                A rendszer naponta automatikusan ment egyet, nézz vissza holnap!
              </p>
            ) : (
              <>
                <div className="trend-headline">
                  <span className="trend-current">
                    {currentValue.toLocaleString('hu-HU')}
                  </span>
                  <span className={`trend-delta ${trendDelta >= 0 ? 'up' : 'down'}`}>
                    {trendDelta >= 0 ? '▲' : '▼'} {Math.abs(trendDelta).toLocaleString('hu-HU')}
                    <span className="trend-delta-label"> a tegnapihoz képest</span>
                  </span>
                </div>
                <TrendChart points={metricPoints} color={activeMetric.color} />
              </>
            )}
          </section>

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

          {topPlayers.length > 0 && (
            <section className="card achievement-card">
              <div className="card-header">
                <div>
                  <h2>🥇 Legaktívabb játékosok</h2>
                  <p>Legtöbb pontot gyűjtő felhasználók</p>
                </div>
                <Link className="card-chip" to="/users">Összes</Link>
              </div>
              <div className="achievement-list">
                {topPlayers.map((player, i) => (
                  <div key={player.id} className="achievement-row">
                    <span className="achievement-rank">{['🥇', '🥈', '🥉'][i] || `#${i + 1}`}</span>
                    <span className="achievement-icon">👤</span>
                    <div className="achievement-info">
                      <p className="achievement-name">{player.name}</p>
                      <p className="achievement-desc">{player.email || 'Nincs email'}</p>
                    </div>
                    <span className="achievement-count">{player.points} pont</span>
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
                <p>{stats.trips === 0 ? 'Még nincs túra az adatbázisban.' : `${stats.trips} túra regisztrálva, ${stats.activeTrips} aktív.`}</p>
              </div>
              <div className="activity-row"><span className="activity-dot"></span>
                <p>{stats.stations === 0 ? 'Nincsenek állomások feltöltve.' : `${stats.stations} állomás, ebből ${stats.assignedStations} túrához rendelve.`}</p>
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


