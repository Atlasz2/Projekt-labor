// Egyszeri migráció: a meglévő stations/events dokumentumok QR-értékeiből
// feltölti a privát qr_codes leképező kollekciót.
//
// Futtatás (a functions/ mappából, admin hitelesítéssel):
//   GOOGLE_APPLICATION_CREDENTIALS=<service-account.json> node scripts/backfill-qr-codes.mjs
// vagy az emulátor ellen:
//   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/backfill-qr-codes.mjs
//
// Idempotens: többszöri futtatás ugyanazt az állapotot adja. Ütközésnél
// (két elem ugyanazzal a QR-értékkel) figyelmeztet és az elsőt hagyja meg.

import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

import { qrMappingDocId } from '../lib/redeem-core.js';

initializeApp({
  credential: applicationDefault(),
  projectId: process.env.GCLOUD_PROJECT ?? 'projekt-labor-a4b1c',
});

const db = getFirestore();

async function backfill() {
  const seen = new Map(); // code -> { kind, id }
  let written = 0;
  let skipped = 0;

  for (const [coll, kind] of [['stations', 'station'], ['events', 'event']]) {
    const snap = await db.collection(coll).get();
    console.log(`${coll}: ${snap.docs.length} dokumentum`);

    for (const docSnap of snap.docs) {
      const data = docSnap.data();
      const code = String(data.qrCode ?? '').trim() || docSnap.id;

      const prior = seen.get(code);
      if (prior) {
        console.warn(
          `ÜTKÖZÉS: "${code}" már ${prior.kind}/${prior.id}-hez tartozik, ` +
            `${kind}/${docSnap.id} kimarad — oldd fel az admin felületen!`,
        );
        skipped += 1;
        continue;
      }
      seen.set(code, { kind, id: docSnap.id });

      await db.collection('qr_codes').doc(qrMappingDocId(code)).set({
        code,
        kind,
        targetId: docSnap.id,
        updatedAt: FieldValue.serverTimestamp(),
      });
      written += 1;
    }
  }

  console.log(`Kész: ${written} leképezés írva, ${skipped} ütközés kihagyva.`);
}

backfill().catch((err) => {
  console.error('Backfill hiba:', err);
  process.exitCode = 1;
});
