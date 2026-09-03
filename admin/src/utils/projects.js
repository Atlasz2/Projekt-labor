// White-label: a tartalom projektenként (településenként) van particionálva egy
// `projectId` mezővel. A régi (projectId nélküli) dokumentumok az alapértelmezett
// projekthez tartoznak, így a szűrés a backfill előtt is helyesen működik.

export const DEFAULT_PROJECT_ID = 'nagyvazsony';

/// Egy dokumentum projektje – hiányzó/üres mező az alapértelmezettet jelenti.
export function docProjectId(doc) {
  const id = doc?.projectId;
  return typeof id === 'string' && id.trim() !== '' ? id : DEFAULT_PROJECT_ID;
}

/// A dokumentumok szűrése az aktív projektre (a hiányzó projectId = alapértelmezett).
export function filterByProject(docs, projectId) {
  const target = projectId || DEFAULT_PROJECT_ID;
  return (docs ?? []).filter((d) => docProjectId(d) === target);
}

/// Egy név „slug"-osítása projekt-azonosítóvá (ékezet nélküli, kisbetűs, kötőjeles).
export function slugifyProjectId(name) {
  const base = (name ?? '')
    .toString()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '') // ékezetek (kombináló jelek) eltávolítása
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return base || `projekt-${Date.now()}`;
}
