// Migráció: az állomások régi, EGYETLEN túrához kötő mezőit
// (`tripId`, `orderIndex`) átalakítja a több túrát is megengedő alakra:
//   station.tripIds  : string[]              — melyik túráknak megállója
//   station.tripOrder: { [tripId]: number }  — sorrend AZ ADOTT túrán belül
//
// Ezután egy állomás akár 0, 1 vagy TÖBB túrának is megállója lehet (lásd
// functions/lib/station-trips-core.js) – pl. egy közös várbeli állomás egy
// rövid és egy hosszú túrán is szerepelhet.
//
// Nem kell service account: a developer fiók bejelentkezésével (REST)
// dolgozik – ugyanaz a minta, mint a backfill-project-id.mjs-ben.
//
// Futtatás a functions/ mappából:
//   FIREBASE_API_KEY=... DEV_EMAIL=... DEV_PASSWORD=... \
//     node scripts/migrate-station-trip-memberships.mjs --dry-run
//   FIREBASE_API_KEY=... DEV_EMAIL=... DEV_PASSWORD=... \
//     node scripts/migrate-station-trip-memberships.mjs
//
// Idempotens: a már migrált (tripIds mezővel rendelkező) állomásokat kihagyja.

const DRY = process.argv.includes('--dry-run');

const PROJECT = process.env.FIREBASE_PROJECT ?? 'projekt-labor-a4b1c';
const API_KEY = process.env.FIREBASE_API_KEY;
const EMAIL = process.env.DEV_EMAIL;
const PASSWORD = process.env.DEV_PASSWORD;

if (!API_KEY || !EMAIL || !PASSWORD) {
  console.error('Hiányzó FIREBASE_API_KEY / DEV_EMAIL / DEV_PASSWORD.');
  process.exit(1);
}

const FS_BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

async function signIn() {
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: EMAIL, password: PASSWORD, returnSecureToken: true }),
    },
  );
  const json = await res.json();
  if (json.error) throw new Error(`Bejelentkezés: ${json.error.message}`);
  return json.idToken;
}

async function listDocs(token, col) {
  const out = [];
  let pageToken = null;
  do {
    const url = `${FS_BASE}/${col}?pageSize=300${pageToken ? `&pageToken=${pageToken}` : ''}`;
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    const json = await res.json();
    if (json.error) throw new Error(`${col}: ${json.error.message}`);
    for (const d of json.documents ?? []) out.push(d);
    pageToken = json.nextPageToken;
  } while (pageToken);
  return out;
}

/** A Firestore REST dokumentum egy mezőjét sima JS-értékké alakítja
 *  (csak azt, amire itt szükség van: string és integer). */
function plainValue(fieldValue) {
  if (!fieldValue) return undefined;
  if ('stringValue' in fieldValue) return fieldValue.stringValue;
  if ('integerValue' in fieldValue) return Number(fieldValue.integerValue);
  return undefined;
}

async function migrateStation(token, id, fields) {
  const tripId = plainValue(fields.tripId);
  if (!tripId || typeof tripId !== 'string' || tripId.trim() === '') {
    return { skipped: 'nincs tripId' };
  }
  const orderIndex = plainValue(fields.orderIndex) ?? 0;

  // updateMask: a tripIds/tripOrder mezőket írjuk, a régi tripId/orderIndex-et
  // pedig TÖRÖLJÜK (a mask-ban szerepelnek, de a body-ból hiányoznak).
  const mask = [
    'updateMask.fieldPaths=tripIds',
    'updateMask.fieldPaths=tripOrder',
    'updateMask.fieldPaths=tripId',
    'updateMask.fieldPaths=orderIndex',
  ].join('&');
  const url = `${FS_BASE}/stations/${id}?${mask}`;
  const body = {
    fields: {
      tripIds: { arrayValue: { values: [{ stringValue: tripId }] } },
      tripOrder: {
        mapValue: { fields: { [tripId]: { integerValue: String(orderIndex) } } },
      },
    },
  };

  if (!DRY) {
    const res = await fetch(url, {
      method: 'PATCH',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const json = await res.json();
    if (json.error) throw new Error(`stations/${id}: ${json.error.message}`);
  }
  return { migrated: tripId };
}

async function run() {
  const token = await signIn();
  const docs = await listDocs(token, 'stations');

  let migrated = 0;
  let alreadyDone = 0;
  let skipped = 0;

  for (const doc of docs) {
    const id = doc.name.split('/').pop();
    const fields = doc.fields ?? {};
    if (fields.tripIds) {
      alreadyDone += 1;
      continue;
    }
    const result = await migrateStation(token, id, fields);
    if (result.migrated) migrated += 1;
    else skipped += 1;
  }

  console.log(
    `${DRY ? '[SZÁRAZ FUTTATÁS] ' : ''}${migrated} állomás migrálva, ` +
      `${alreadyDone} már migrált volt, ${skipped} kihagyva (nincs tripId) ` +
      `– összesen ${docs.length} állomás.`,
  );
}

run().catch((err) => {
  console.error('Migráció hiba:', err.message);
  process.exitCode = 1;
});
