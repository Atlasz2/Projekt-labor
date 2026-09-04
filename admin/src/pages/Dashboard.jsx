import PropTypes from 'prop-types';
import React, { useState, useEffect, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { db } from '../firebaseConfig';
import {
  collection, getDocs, getDoc, query, doc, setDoc, orderBy, limit,
  getCountFromServer,
} from 'firebase/firestore';
import StateCard from '../components/StateCard';
import { useProject } from '../context/ProjectContext';
import { docProjectId, DEFAULT_PROJECT_ID } from '../utils/projects';
import { stationTripIds } from '../utils/stationTrips';
import '../styles/Dashboard.css';

const TREND_METRICS = [
  { key: 'totalPoints', label: 'Összpontszám', color: '#5b6f4c' },
  { key: 'users',       label: 'Felhasználók', color: '#2563eb' },
  { key: 'stations',    label: 'Állomások',    color: '#d97706' },
];

const formatAxisNumber = (n) => {
  if (Math.abs(n) >= 1000) return `${(n / 1000).toFixed(n % 1000 === 0 ? 0 : 1)}k`;
  return `${Math.round(n)}`;
};

const formatAxisDate = (raw) => {
  const s = (raw ?? '').toString();
  // "YYYY-MM-DD" -> "MM.DD"; egyébként a nyers érték.
  const m = s.match(/(\d{2})-(\d{2})$/);
  return m ? `${m[1]}.${m[2]}` : s;
};

const formatFullDate = (raw) => {
  const s = (raw ?? '').toString();
  // "YYYY-MM-DD" -> "YYYY.MM.DD"; egyébként a nyers érték.
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  return m ? `${m[1]}.${m[2]}.${m[3]}` : s;
};

// Egyenletesen elosztott indexek az X tengely dátumcímkéihez (max `count`).
const tickIndices = (n, count) => {
  if (n <= count) return Array.from({ length: n }, (_, i) => i);
  const set = new Set();
  for (let k = 0; k < count; k += 1) {
    set.add(Math.round((k * (n - 1)) / (count - 1)));
  }
  return [...set].sort((a, b) => a - b);
};

function TrendChart({ points, color }) {
  const [hover, setHover] = useState(null);
  if (points.length < 2) return null;

  const W = 560;
  const H = 150;
  const ML = 30; // bal margó – Y tengely értékek
  const MR = 12;
  const MT = 10;
  const MB = 16; // alsó margó – X tengely dátumok
  const plotW = W - ML - MR;
  const plotH = H - MT - MB;

  const values = points.map((p) => p.value);
  const max = Math.max(...values);
  const min = Math.min(...values);
  const range = max - min || 1;
  const mid = (max + min) / 2;
  const stepX = plotW / (points.length - 1);

  const yFor = (v) => MT + plotH - ((v - min) / range) * plotH;
  const coords = points.map((p, i) => [ML + i * stepX, yFor(p.value)]);

  const line = coords
    .map(([x, y], i) => `${i === 0 ? 'M' : 'L'}${x.toFixed(1)},${y.toFixed(1)}`)
    .join(' ');
  const baseY = MT + plotH;
  const area = `${line} L${coords[coords.length - 1][0].toFixed(1)},${baseY} L${coords[0][0].toFixed(1)},${baseY} Z`;
  const last = coords[coords.length - 1];

  const yTicks = [
    { v: max, y: yFor(max) },
    { v: mid, y: yFor(mid) },
    { v: min, y: yFor(min) },
  ];
  const xTicks = tickIndices(points.length, 5);

  // Aktív (hover) pont + tooltip geometria.
  const active = hover != null ? coords[hover] : null;
  const tipW = 92;
  const tipH = 30;
  let tipX = 0;
  let tipY = 0;
  if (active) {
    tipX = Math.max(ML, Math.min(active[0] - tipW / 2, W - MR - tipW));
    tipY = active[1] - tipH - 8;
    if (tipY < MT) tipY = active[1] + 10;
  }

  return (
    <svg
      className="trend-svg"
      viewBox={`0 0 ${W} ${H}`}
      role="img"
      aria-label="Trend grafikon"
      onMouseLeave={() => setHover(null)}
    >
      <defs>
        <linearGradient id="trendFill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity="0.28" />
          <stop offset="100%" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>

      {/* Y tengely: rácsvonalak + értékek */}
      {yTicks.map((t, i) => (
        <g key={i}>
          <line x1={ML} y1={t.y} x2={W - MR} y2={t.y} stroke="currentColor" strokeOpacity="0.12" strokeWidth="1" />
          <text x={ML - 4} y={t.y + 2.5} textAnchor="end" fontSize="7.5" fill="currentColor" fillOpacity="0.55">
            {formatAxisNumber(t.v)}
          </text>
        </g>
      ))}

      <path d={area} fill="url(#trendFill)" />
      <path d={line} fill="none" stroke={color} strokeWidth="2.5" strokeLinejoin="round" strokeLinecap="round" />
      <circle cx={last[0]} cy={last[1]} r="4.5" fill={color} />

      {/* X tengely: több egyenletesen elosztott dátum */}
      {xTicks.map((idx) => {
        const anchor = idx === 0 ? 'start' : idx === points.length - 1 ? 'end' : 'middle';
        return (
          <text
            key={idx}
            x={coords[idx][0]}
            y={H - 5}
            textAnchor={anchor}
            fontSize="7.5"
            fill="currentColor"
            fillOpacity="0.55"
          >
            {formatAxisDate(points[idx].date)}
          </text>
        );
      })}

      {/* Hover: vezetővonal + kiemelt pont + tooltip */}
      {active && (
        <g pointerEvents="none">
          <line x1={active[0]} y1={MT} x2={active[0]} y2={baseY} stroke={color} strokeOpacity="0.35" strokeWidth="1" strokeDasharray="3 3" />
          <circle cx={active[0]} cy={active[1]} r="5" fill={color} stroke="#fff" strokeWidth="1.5" />
          <g>
            <rect x={tipX} y={tipY} width={tipW} height={tipH} rx="6" fill="#2b2720" opacity="0.92" />
            <text x={tipX + 8} y={tipY + 13} fontSize="9" fontWeight="700" fill="#fff">
              {points[hover].value.toLocaleString('hu-HU')}
            </text>
            <text x={tipX + 8} y={tipY + 24} fontSize="7.5" fill="#fff" fillOpacity="0.75">
              {formatFullDate(points[hover].date)}
            </text>
          </g>
        </g>
      )}

      {/* Átlátszó találati sávok – a pontok fölé húzva mutatják az értéket */}
      {coords.map(([x], i) => (
        <rect
          key={i}
          x={x - stepX / 2}
          y={MT}
          width={stepX}
          height={plotH}
          fill="transparent"
          onMouseEnter={() => setHover(i)}
          onMouseMove={() => setHover(i)}
          onClick={() => setHover(i)}
        />
      ))}
    </svg>
  );
}

TrendChart.propTypes = {
  points: PropTypes.arrayOf(PropTypes.object).isRequired,
  color: PropTypes.string.isRequired,
};

function Dashboard() {
  // A vezérlőpult településspecifikus: az admin csak a saját települése adatait
  // látja. A developer emellett kérhet összesített (minden település) nézetet.
  const { activeProjectId, activeProject, canSwitchProject } = useProject();
  const [scope, setScope] = useState('project');
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

      // A statisztika településspecifikus: a pontokat az adott település saját
      // állomásaiból számoljuk, ezért a haladás-dokumentumokat be kell olvasni.
      // (A user_progress kicsi; nagyobb méretnél a tripAnalytics-hez hasonló
      // szerveroldali aggregációra érdemes váltani.)
      const scopeAll = scope === 'all';
      const inScope = (d) => scopeAll || docProjectId(d) === activeProjectId;

      const [
        tripsSnapshot,
        stationsSnapshot,
        achievementsSnapshot,
        usersCount,
        progressSnapshot,
      ] = await Promise.all([
        getDocs(collection(db, 'trips')),
        getDocs(collection(db, 'stations')),
        getDocs(collection(db, 'achievements')),
        getCountFromServer(collection(db, 'users')),
        getDocs(progressCol),
      ]);

      // Tartalom az aktív településre szűrve (a hiányzó projectId az
      // alapértelmezett településhez tartozik).
      const toObj = (d) => ({ id: d.id, ...d.data() });
      const tripDocs = tripsSnapshot.docs.map(toObj).filter(inScope);
      const stationDocs = stationsSnapshot.docs.map(toObj).filter(inScope);
      const achDocs = achievementsSnapshot.docs.map(toObj).filter(inScope);

      // A pontokat a település SAJÁT állomásaiból számoljuk, így az "összpont"
      // valóban az adott településen szerzett pont (a totalPoints globális).
      const stationPoints = new Map(
        stationDocs.map((st) => [st.id, Number(st.points) || 10]),
      );

      let trackedUsers = 0;
      let totalPts = 0;
      const scopedPlayers = [];
      progressSnapshot.docs.forEach((d) => {
        const data = d.data();
        const completed = Array.isArray(data.completedStations)
          ? data.completedStations
          : [];
        let pts = 0;
        let hits = 0;
        completed.forEach((sid) => {
          if (stationPoints.has(sid)) {
            pts += stationPoints.get(sid);
            hits += 1;
          }
        });
        if (hits > 0) {
          trackedUsers += 1;
          totalPts += pts;
          scopedPlayers.push({ id: d.id, data, points: pts });
        }
      });

      const activeTrips = tripDocs.filter((t) => t.isActive === true).length;
      const usersTotal = scopeAll ? usersCount.data().count : trackedUsers;
      const avgPts = trackedUsers > 0 ? Math.round(totalPts / trackedUsers) : 0;
      const assignedStations = stationDocs.filter((st) => stationTripIds(st).length > 0).length;

      setStats({
        trips: tripDocs.length,
        stations: stationDocs.length,
        users: usersTotal,
        trackedUsers,
        activeTrips,
        achievements: achDocs.length,
        totalPoints: totalPts,
        averagePoints: avgPts,
        assignedStations,
      });

      const achData = [...achDocs]
        .sort((a, b) => (b.unlockedCount || 0) - (a.unlockedCount || 0))
        .slice(0, 3);
      setTopAchievements(achData);

      // A név gyakran a users kollekcióban van, nem a user_progress-ben, ezért
      // az 5 élen álló játékoshoz behúzzuk a users doksit is (csak 5 olvasás).
      const topPlayerRows = [...scopedPlayers]
        .sort((a, b) => b.points - a.points)
        .slice(0, 5);
      const topUserDocs = await Promise.all(
        topPlayerRows.map((r) => getDoc(doc(db, 'users', r.id)).catch(() => null)),
      );
      const playerData = topPlayerRows.map((row, idx) => {
        const data = row.data;
        const userDoc = topUserDocs[idx];
        const userData = userDoc && userDoc.exists() ? userDoc.data() : {};
        const name =
          data.name ||
          data.userName ||
          userData.name ||
          userData.userName ||
          data.email ||
          userData.email ||
          'Ismeretlen játékos';
        return {
          id: row.id,
          name,
          email: data.email || userData.email || '',
          points: row.points,
        };
      });
      setTopPlayers(playerData);

      // Persist a once-per-day snapshot so the dashboard can show real trends over time.
      // Non-blocking: if security rules forbid the write, the trend simply stays empty.
      const today = new Date().toISOString().slice(0, 10);
      // A pillanatkép településenként külön dokumentumba megy, különben a
      // különböző települések adminjai felülírnák egymás napi értékeit.
      const scopeKey = scopeAll ? 'all' : activeProjectId;
      try {
        await setDoc(
          doc(db, 'stats_daily', `${scopeKey}_${today}`),
          {
            date: today,
            projectId: scopeKey,
            trips: tripDocs.length,
            stations: stationDocs.length,
            users: usersTotal,
            trackedUsers,
            totalPoints: totalPts,
            achievements: achDocs.length,
            updatedAt: Date.now(),
          },
          { merge: true },
        );
      } catch {
        // ignore — trends are optional
      }

      try {
        // Több település pillanatképei egy kollekcióban vannak, ezért bővebben
        // olvasunk és az aktív hatókörre szűrünk (így nem kell összetett index).
        const trendSnapshot = await getDocs(
          query(collection(db, 'stats_daily'), orderBy('date', 'desc'), limit(90)),
        );
        const scoped = trendSnapshot.docs
          .map((d) => d.data())
          // A régi, projectId nélküli pillanatképek az alapértelmezett
          // településhez tartoznak (visszamenőleges kompatibilitás).
          .filter((row) => (row.projectId || DEFAULT_PROJECT_ID) === scopeKey)
          .slice(0, 14);
        setTrendData(scoped.reverse());
      } catch {
        setTrendData([]);
      }
    } catch (err) {
      setError('Nem sikerült betölteni az adatokat: ' + err.message);
    } finally {
      setLoading(false);
    }
  }, [scope, activeProjectId]);

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
          <p className="hero-kicker">
            {scope === 'all'
              ? 'Összesített áttekintés'
              : `${activeProject?.name || 'Nagyvázsony'} · irányítópult`}
          </p>
          <h1>Dashboard</h1>
          {canSwitchProject && (
            <div className="dashboard-scope">
              <button
                type="button"
                className={`dashboard-scope-btn${scope === 'project' ? ' active' : ''}`}
                onClick={() => setScope('project')}
              >
                {activeProject?.name || 'Ez a település'}
              </button>
              <button
                type="button"
                className={`dashboard-scope-btn${scope === 'all' ? ' active' : ''}`}
                onClick={() => setScope('all')}
              >
                Összesített (minden település)
              </button>
            </div>
          )}
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
                <h2>📈 {activeMetric.label}</h2>
                <p>Trend – az utóbbi {trendData.length} napi pillanatkép alapján</p>
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


