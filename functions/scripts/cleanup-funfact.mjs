// Egyszeri tisztítás: a régi `funFact` és `funFactImageUrl` mezők eltávolítása
// a stations dokumentumokból (az érdekesség-fogalom megszűnt, csak a feloldott
// tartalom maradt).
//
// Futtatás (a functions/ mappából, admin hitelesítéssel):
//   GOOGLE_APPLICATION_CREDENTIALS=<service-account.json> node scripts/cleanup-funfact.mjs
// vagy az emulátor ellen:
//   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/cleanup-funfact.mjs
//
// Idempotens: többszöri futtatás ártalmatlan (a hiányzó mezők törlése no-op).

import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

initializeApp({
  credential: applicationDefault(),
  projectId: process.env.GCLOUD_PROJECT ?? 'projekt-labor-a4b1c',
});

const db = getFirestore();

async function cleanup() {
  const snap = await db.collection('stations').get();
  console.log(`stations: ${snap.docs.length} dokumentum`);

  let cleaned = 0;
  for (const doc of snap.docs) {
    const data = doc.data();
    if (!('funFact' in data) && !('funFactImageUrl' in data)) continue;

    await doc.ref.update({
      funFact: FieldValue.delete(),
      funFactImageUrl: FieldValue.delete(),
    });
    cleaned += 1;
    console.log(`  törölve: ${doc.id} (${data.name ?? 'névtelen'})`);
  }

  console.log(`Kész: ${cleaned} állomásból eltávolítva a régi érdekesség-mező.`);
}

cleanup().catch((err) => {
  console.error('Tisztítás hiba:', err);
  process.exitCode = 1;
});
