import { collection, getCountFromServer, query, where } from 'firebase/firestore';

/** A településhez (projectId) köthető kollekciók és olvasható nevük. */
export const PROJECT_LINKED_COLLECTIONS = [
  ['trips', 'túra'],
  ['stations', 'állomás'],
  ['events', 'rendezvény'],
  ['accommodations', 'szállás'],
  ['restaurants', 'vendéglátóhely'],
  ['about', 'történeti bejegyzés'],
  ['achievements', 'jutalom'],
  ['contact', 'elérhetőség'],
  ['bug_reports', 'hibabejelentés'],
  ['users', 'hozzárendelt admin'],
];

/**
 * Mennyi tartalom és admin tartozik egy településhez. Csak számlálást kér a
 * szervertől (nem tölti le a dokumentumokat).
 * @returns {Promise<Array<{collection: string, label: string, count: number}>>}
 */
export async function projectUsage(db, projectId) {
  return Promise.all(
    PROJECT_LINKED_COLLECTIONS.map(async ([name, label]) => {
      const snap = await getCountFromServer(
        query(collection(db, name), where('projectId', '==', projectId)),
      );
      return { collection: name, label, count: snap.data().count };
    }),
  );
}

/** A nem üres tételek olvasható felsorolása, pl. „3 túra, 1 hozzárendelt admin”. */
export function describeUsage(usage) {
  return (usage ?? [])
    .filter((u) => u.count > 0)
    .map((u) => `${u.count} ${u.label}`)
    .join(', ');
}
