import { useState } from 'react';
import { useProject } from '../context/ProjectContext';
import ConfirmDialog from '../components/ConfirmDialog';
import { DEFAULT_PROJECT_ID } from '../utils/projects';
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
    renameProject,
    deleteProject,
  } = useProject();

  const [editing, setEditing] = useState({ id: null, name: '' });
  const [deleteTarget, setDeleteTarget] = useState(null);

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

  const runSafely = async (action, fallbackMessage) => {
    setBusy(true);
    setError('');
    try {
      await action();
      return true;
    } catch (err) {
      setError(err?.message || fallbackMessage);
      return false;
    } finally {
      setBusy(false);
    }
  };

  const handleRename = async (e) => {
    e.preventDefault();
    const ok = await runSafely(
      () => renameProject(editing.id, editing.name),
      'Nem sikerült átnevezni a települést.',
    );
    if (ok) setEditing({ id: null, name: '' });
  };

  const handleDelete = async () => {
    const target = deleteTarget;
    setDeleteTarget(null);
    if (target) {
      await runSafely(() => deleteProject(target.id), 'Nem sikerült törölni a települést.');
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
            const isEditing = editing.id === p.id;
            return (
              <li key={p.id} className="project-row">
                {isEditing ? (
                  <form className="project-rename" onSubmit={handleRename}>
                    <input
                      type="text"
                      value={editing.name}
                      onChange={(e) => setEditing({ id: p.id, name: e.target.value })}
                      aria-label={`${p.name || p.id} új neve`}
                      disabled={busy}
                      autoFocus
                    />
                    <button
                      type="button"
                      className="btn-secondary"
                      onClick={() => setEditing({ id: null, name: '' })}
                      disabled={busy}
                    >
                      Mégse
                    </button>
                    <button type="submit" className="btn-primary" disabled={busy || !editing.name.trim()}>
                      Mentés
                    </button>
                  </form>
                ) : (
                  <>
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
                    <div className="project-row-actions">
                      <button
                        type="button"
                        className="btn-edit"
                        onClick={() => setEditing({ id: p.id, name: p.name || p.id })}
                        disabled={busy}
                      >
                        Átnevezés
                      </button>
                      {p.id !== DEFAULT_PROJECT_ID && (
                        <button
                          type="button"
                          className="btn-delete"
                          onClick={() => setDeleteTarget(p)}
                          disabled={busy}
                        >
                          Törlés
                        </button>
                      )}
                    </div>
                  </>
                )}
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

      <ConfirmDialog
        open={Boolean(deleteTarget)}
        title="Település törlése"
        message={`Biztosan törlöd: ${deleteTarget?.name || deleteTarget?.id || ''}? Csak olyan település törölhető, amelyhez már nem tartozik tartalom vagy admin.`}
        confirmText="Törlés"
        onConfirm={handleDelete}
        onClose={() => setDeleteTarget(null)}
      />
    </div>
  );
}

export default Developer;
