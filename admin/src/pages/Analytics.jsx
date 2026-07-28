import { useState, useEffect, useCallback } from 'react';
import { httpsCallable } from 'firebase/functions';
import { functions } from '../firebaseConfig';
import StateCard from '../components/StateCard';
import '../styles/Analytics.css';

const pct = (rate) => `${Math.round((rate || 0) * 100)}%`;

// A callable hibáiból felhasználóbarát üzenet – kiemelten a "nincs deployolva"
// esetet (a függvényt még nem telepítették).
const friendlyError = (err) => {
  const code = err?.code || '';
  if (code.includes('not-found') || code.includes('unavailable')) {
    return 'Az analitika függvény (tripAnalytics) még nincs telepítve. Futtasd: firebase deploy --only functions:tripAnalytics';
  }
  if (code.includes('permission-denied')) {
    return 'Ehhez a nézethez admin jogosultság szükséges.';
  }
  return err?.message || 'Ismeretlen hiba történt az analitika betöltésekor.';
};

function Analytics() {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const callable = httpsCallable(functions, 'tripAnalytics');
      const res = await callable();
      setData(res.data);
    } catch (err) {
      setError(friendlyError(err));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    // A betöltés a következő tick-re halasztva, hogy ne hívjunk setState-et
    // szinkron az effekt törzsében (React lint: set-state-in-effect).
    const timer = setTimeout(() => {
      void load();
    }, 0);
    return () => clearTimeout(timer);
  }, [load]);

  if (loading) {
    return (
      <div className="analytics-page">
        <StateCard variant="loading" icon="⏳" title="Analitika betöltése..." description="A számítás szerveroldalon fut." />
      </div>
    );
  }

  if (error) {
    return (
      <div className="analytics-page">
        <StateCard
          icon="📉"
          title="Nem sikerült betölteni az analitikát"
          description={error}
          actionLabel="Újrapróbálás"
          onAction={load}
        />
      </div>
    );
  }

  const totals = data?.totals ?? {};
  const trips = data?.trips ?? [];
  const stations = (data?.stations ?? []).filter((s) => s.completions > 0).slice(0, 10);
  const maxStationCompletions = stations.reduce((m, s) => Math.max(m, s.completions), 0) || 1;

  return (
    <div className="analytics-page">
      <div className="analytics-header">
        <div>
          <h1>Viselkedési analitika</h1>
          <p>Túra-tölcsér és állomás-népszerűség a felhasználók haladása alapján</p>
        </div>
        <button className="analytics-refresh" type="button" onClick={load}>
          ↻ Frissítés
        </button>
      </div>

      <div className="analytics-totals">
        <div className="analytics-stat">
          <span className="analytics-stat-value">{totals.participants ?? 0}</span>
          <span className="analytics-stat-label">Résztvevő (≥1 állomás)</span>
        </div>
        <div className="analytics-stat">
          <span className="analytics-stat-value">{totals.totalStationCompletions ?? 0}</span>
          <span className="analytics-stat-label">Összes állomás-teljesítés</span>
        </div>
        <div className="analytics-stat">
          <span className="analytics-stat-value">{totals.trackedUsers ?? 0}</span>
          <span className="analytics-stat-label">Követett felhasználó</span>
        </div>
      </div>

      <section className="analytics-card">
        <h2>🎯 Túra-tölcsér</h2>
        <p className="analytics-sub">Hányan kezdték el (≥1 állomás) és hányan fejezték be teljesen az egyes túrákat</p>
        {trips.length === 0 ? (
          <p className="analytics-empty">Még nincs adat a túrákhoz.</p>
        ) : (
          <div className="funnel-list">
            {trips.map((t) => {
              const partW = totals.trackedUsers > 0 ? (t.participants / Math.max(totals.trackedUsers, 1)) * 100 : 0;
              const finW = t.participants > 0 ? (t.finishers / t.participants) * 100 : 0;
              return (
                <div key={t.id} className="funnel-row">
                  <div className="funnel-top">
                    <span className="funnel-name">{t.name}</span>
                    <span className="funnel-rate">{pct(t.completionRate)} befejezés</span>
                  </div>
                  <div className="funnel-bars">
                    <div className="funnel-bar-track" title={`${t.participants} résztvevő`}>
                      <div className="funnel-bar participants" style={{ width: `${Math.max(partW, 3)}%` }}>
                        <span>{t.participants} résztvevő</span>
                      </div>
                    </div>
                    <div className="funnel-bar-track" title={`${t.finishers} befejező`}>
                      <div className="funnel-bar finishers" style={{ width: `${Math.max(finW, 3)}%` }}>
                        <span>{t.finishers} befejező</span>
                      </div>
                    </div>
                  </div>
                  <div className="funnel-meta">
                    {t.stationCount} állomás · átlag {t.avgStationsPerParticipant.toFixed(1)} teljesítve / résztvevő
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </section>

      <section className="analytics-card">
        <h2>📍 Legnépszerűbb állomások</h2>
        <p className="analytics-sub">Hány felhasználó teljesítette (a top 10)</p>
        {stations.length === 0 ? (
          <p className="analytics-empty">Még egyetlen állomást sem teljesítettek.</p>
        ) : (
          <div className="popularity-list">
            {stations.map((s, i) => (
              <div key={s.id} className="popularity-row">
                <span className="popularity-rank">#{i + 1}</span>
                <div className="popularity-body">
                  <div className="popularity-top">
                    <span className="popularity-name">{s.name}</span>
                    <span className="popularity-count">{s.completions}</span>
                  </div>
                  <div className="popularity-track">
                    <div
                      className="popularity-bar"
                      style={{ width: `${(s.completions / maxStationCompletions) * 100}%` }}
                    />
                  </div>
                  {s.tripName && <span className="popularity-trip">{s.tripName}</span>}
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      {data?.generatedAt && (
        <p className="analytics-generated">
          Frissítve: {new Date(data.generatedAt).toLocaleString('hu-HU')}
        </p>
      )}
    </div>
  );
}

export default Analytics;
