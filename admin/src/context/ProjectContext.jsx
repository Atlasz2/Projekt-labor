import PropTypes from 'prop-types';
import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { collection, deleteDoc, getDocs, doc, getDoc, setDoc, serverTimestamp } from 'firebase/firestore';
import { describeUsage, projectUsage } from '../utils/projectUsage';
import { db } from '../firebaseConfig';
import { useAdminAuth } from './AdminAuthContext';
import { DEFAULT_PROJECT_ID, slugifyProjectId } from '../utils/projects';

const STORAGE_KEY = 'activeProjectId';

// Az alapértelmezett projekt mindig szerepel a listában, akkor is, ha még
// nincs külön dokumentuma a `projects` kollekcióban (a régi, egy-települési adat).
const DEFAULT_PROJECT = {
  id: DEFAULT_PROJECT_ID,
  name: 'Nagyvázsony',
  isActive: true,
};

const ProjectContext = createContext(null);

function readStoredProjectId() {
  try {
    return localStorage.getItem(STORAGE_KEY) || DEFAULT_PROJECT_ID;
  } catch {
    return DEFAULT_PROJECT_ID;
  }
}

export function ProjectProvider({ children }) {
  const { userRole, userUid } = useAdminAuth();
  // Csak a developer kezelhet több települést. A sima admin a saját
  // településén dolgozik – neki nincs váltó, és a tárolt választás sem
  // befolyásolja (közös böngésző esetén sem).
  const isDeveloper = userRole === 'developer';

  const [projects, setProjects] = useState([DEFAULT_PROJECT]);
  const [storedProjectId, setStoredProjectId] = useState(readStoredProjectId);
  const [assignedProjectId, setAssignedProjectId] = useState(null);
  const [loading, setLoading] = useState(true);

  // A sima admin települése a saját users/{uid}.projectId mezőjéből jön –
  // ezt a developer rendeli hozzá a Felhasználók nézetben.
  useEffect(() => {
    let cancelled = false;
    // A következő tick-re halasztva (React lint: set-state-in-effect).
    const timer = setTimeout(async () => {
      if (!userUid) {
        if (!cancelled) setAssignedProjectId(null);
        return;
      }
      try {
        const snap = await getDoc(doc(db, 'users', userUid));
        const assigned = snap.exists() ? snap.data()?.projectId : null;
        if (!cancelled) {
          setAssignedProjectId(
            typeof assigned === 'string' && assigned.trim() ? assigned : null,
          );
        }
      } catch {
        // Hiba esetén marad az alapértelmezett település.
        if (!cancelled) setAssignedProjectId(null);
      }
    }, 0);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [userUid]);

  // Developer: a saját választása. Admin: a hozzárendelt település (ha nincs
  // beállítva, az alapértelmezett).
  const activeProjectId = isDeveloper
    ? storedProjectId
    : assignedProjectId || DEFAULT_PROJECT_ID;

  const loadProjects = useCallback(async () => {
    setLoading(true);
    try {
      const snap = await getDocs(collection(db, 'projects'));
      const fromDb = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
      // Az alapértelmezett projekt mindig legyen elöl, duplikátum nélkül.
      const merged = [
        DEFAULT_PROJECT,
        ...fromDb.filter((p) => p.id !== DEFAULT_PROJECT_ID),
      ];
      setProjects(merged);
    } catch {
      // Hálózati/jogosultsági hiba esetén legalább az alapértelmezett elérhető.
      setProjects([DEFAULT_PROJECT]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    // A következő tick-re halasztva, hogy ne hívjunk setState-et szinkron az
    // effekt törzsében (React lint: set-state-in-effect).
    const timer = setTimeout(() => {
      void loadProjects();
    }, 0);
    return () => clearTimeout(timer);
  }, [loadProjects]);

  const setActiveProjectId = useCallback(
    (id) => {
      if (!isDeveloper) return; // váltani csak a developer tud
      const next = id || DEFAULT_PROJECT_ID;
      setStoredProjectId(next);
      try {
        localStorage.setItem(STORAGE_KEY, next);
      } catch {
        // némán: a választás enélkül is működik az adott munkamenetben
      }
    },
    [isDeveloper],
  );

  const createProject = useCallback(
    async (name) => {
      const clean = (name ?? '').trim();
      if (!clean) throw new Error('A projekt neve kötelező.');
      const id = slugifyProjectId(clean);
      // Létező azonosítóra a setDoc némán felülírná a meglévő települést.
      const existing = await getDoc(doc(db, 'projects', id));
      if (id === DEFAULT_PROJECT_ID || existing.exists()) {
        throw new Error(`Már létezik település ezzel az azonosítóval (${id}).`);
      }
      await setDoc(doc(db, 'projects', id), {
        name: clean,
        isActive: true,
        createdAt: serverTimestamp(),
      });
      await loadProjects();
      setActiveProjectId(id);
      return id;
    },
    [loadProjects, setActiveProjectId],
  );

  // Átnevezés: csak a megjelenített név változik, az azonosító (és vele minden
  // tartalom hozzárendelése) változatlan marad.
  const renameProject = useCallback(
    async (id, name) => {
      const clean = (name ?? '').trim();
      if (!clean) throw new Error('A település neve kötelező.');
      await setDoc(
        doc(db, 'projects', id),
        { name: clean, updatedAt: serverTimestamp() },
        { merge: true },
      );
      await loadProjects();
    },
    [loadProjects],
  );

  // Törlés csak üres településre: ha tartalom vagy admin tartozik hozzá, a
  // törlés elmarad, és a hibaüzenet felsorolja, mi van még hozzárendelve.
  const deleteProject = useCallback(
    async (id) => {
      if (id === DEFAULT_PROJECT_ID) {
        throw new Error('Az alapértelmezett település nem törölhető.');
      }
      const inUse = describeUsage(await projectUsage(db, id));
      if (inUse) {
        throw new Error(
          `A település nem törölhető, mert még hozzá tartozik: ${inUse}. Előbb ezeket töröld vagy rendeld át.`,
        );
      }
      await deleteDoc(doc(db, 'projects', id));
      if (id === activeProjectId) setActiveProjectId(DEFAULT_PROJECT_ID);
      await loadProjects();
    },
    [activeProjectId, loadProjects, setActiveProjectId],
  );

  const activeProject =
    projects.find((p) => p.id === activeProjectId) || DEFAULT_PROJECT;

  return (
    <ProjectContext.Provider
      value={{
        projects,
        activeProjectId,
        activeProject,
        loading,
        canSwitchProject: isDeveloper,
        setActiveProjectId,
        createProject,
        renameProject,
        deleteProject,
        reloadProjects: loadProjects,
      }}
    >
      {children}
    </ProjectContext.Provider>
  );
}

ProjectProvider.propTypes = {
  children: PropTypes.node,
};

export const useProject = () => {
  const context = useContext(ProjectContext);
  if (!context) {
    throw new Error('useProject must be used within ProjectProvider');
  }
  return context;
};
