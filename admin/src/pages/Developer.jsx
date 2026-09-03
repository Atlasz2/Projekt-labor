import { useState } from 'react';
import { useProject } from '../context/ProjectContext';
import StateCard from '../components/StateCard';
import '../styles/Developer.css';

/// Fejlesztői (platform-szintű) nézet: több település kezelése. A sima admin
/// csak a saját településén dolgozik, ezért a váltó szándékosan CSAK itt él.
function Developer() {
  const {
    projects,
    activeProjectId,
    activeProject,
    loading,
    setActiveProjectId,
    createProject,
  } = useProject();

  const [newName, setNewName] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const handleCreate = async (e) => {
    e.preventDefault();
    const name = newName.trim();
    if (!name) return;
    setBusy(true);
    setError('');
    try {
      await createProject(name);
      setNewName('');
    } catch (err) {
      setError(err?.message || 'Nem sikerült létrehozni a települést.');
    } finally {
      setBusy(false);
    }
  };

  if (loading) {
    return (
      <StateCard
        variant="loading"
        icon="🛠️"
        title="Települések betöltése..."
        description="Kérlek várj."
      />
    );
  }

  return (
    <div className="developer-page">
      <div className="developer-header">
        <div>
          <h1>Települések kezelése</h1>
          <p>
            Platform-szintű nézet: itt hozhatsz létre új települést, és itt
            válthatsz közöttük. A sima adminok mindig a saját településükön
            dolgoznak — nekik nincs váltó.
          </p>
        </div>
        <div className="developer-active">
          <span className="developer-active-label">Jelenleg szerkesztve</span>
          <strong>{activeProject?.name || activeProjectId}</strong>
        </div>
      </div>

      {error && <div className="developer-error">{error}</div>}

      <section className="developer-card">
        <h2>Települések</h2>
        <p className="developer-sub">
          Kattints egy településre, hogy arra válts. A tartalom-oldalak (túrák,
          állomások, rendezvények…) ezután az itt kiválasztott településhez
          tartoznak.
        </p>
        <ul className="project-list">
          {projects.map((p) => {
            const isActive = p.id === activeProjectId;
            return (
              <li key={p.id}>
                <button
                  type="button"
                  className={`project-item${isActive ? ' active' : ''}`}
                  onClick={() => setActiveProjectId(p.id)}
                  aria-current={isActive ? 'true' : undefined}
                >
                  <span className="project-item-name">{p.name || p.id}</span>
                  <span className="project-item-id">{p.id}</span>
                  {isActive && <span className="project-item-badge">aktív</span>}
                </button>
              </li>
            );
          })}
        </ul>
      </section>

      <section className="developer-card">
        <h2>Új település</h2>
        <p className="developer-sub">
          A név alapján generálódik az azonosító (pl. {'„Tapolca”'} → <code>tapolca</code>).
          Létrehozás után automatikusan átváltunk rá.
        </p>
        <form className="project-create" onSubmit={handleCreate}>
          <input
            type="text"
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
            placeholder="pl. Tapolca"
            disabled={busy}
            aria-label="Új település neve"
          />
          <button type="submit" className="btn-primary" disabled={busy || !newName.trim()}>
            {busy ? 'Létrehozás...' : 'Létrehozás'}
          </button>
        </form>
      </section>
    </div>
  );
}

export default Developer;
