// Egyszeri tisztítás: a megszűnt állomás-mezők eltávolítása a stations
// dokumentumokból. Ezek a fogalmak kikerültek az appból, csak a feloldott
// tartalom (unlockContent / unlockContentImageUrl) maradt:
//   - funFact, funFactImageUrl  (régi "érdekesség")
//   - extraInfo                 (régi "extra információ" panel a scan-eredményben)
//
// Futtatás (a functions/ mappából, admin hitelesítéssel):
//   GOOGLE_APPLICATION_CREDENTIALS=<service-account.json> node scripts/cleanup-obsolete-station-fields.mjs
// vagy az emulátor ellen:
//   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/cleanup-obsolete-station-fields.mjs
//
// Idempotens: többszöri futtatás ártalmatlan (a hiányzó mezők törlése no-op).

import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

initializeApp({
  credential: applicationDefault(),
  projectId: process.env.GCLOUD_PROJECT ?? 'projekt-labor-a4b1c',
});

const db = getFirestore();

const OBSOLETE_FIELDS = ['funFact', 'funFactImageUrl', 'extraInfo'];

async function cleanup() {
  const snap = await db.collection('stations').get();
  console.log(`stations: ${snap.docs.length} dokumentum`);

  let cleaned = 0;
  for (const doc of snap.docs) {
    const data = doc.data();
    const present = OBSOLETE_FIELDS.filter((f) => f in data);
    if (present.length === 0) continue;

    const update = {};
    for (const field of present) update[field] = FieldValue.delete();
    await doc.ref.update(update);

    cleaned += 1;
    console.log(
      `  törölve: ${doc.id} (${data.name ?? 'névtelen'}) – ${present.join(', ')}`,
    );
  }

  console.log(`Kész: ${cleaned} állomásból eltávolítva a megszűnt mező(k).`);
}

cleanup().catch((err) => {
  console.error('Tisztítás hiba:', err);
  process.exitCode = 1;
});
