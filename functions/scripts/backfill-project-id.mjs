// White-label migráció: a meglévő tartalom-dokumentumokra ráírja az
// alapértelmezett `projectId: 'nagyvazsony'` mezőt, ahol még hiányzik.
//
// Az admin/mobil kliens a hiányzó projectId-t is az alapértelmezett projektnek
// tekinti, ezért ez a script NEM kötelező a helyes működéshez – rendbe teszi az
// adatot, hogy a szabályok és a későbbi szerveroldali szűrés egyértelmű legyen.
//
// Nem kell service account: a developer fiók bejelentkezésével (REST) dolgozik –
// ugyanaz a minta, mint a migrate-inline-images.mjs-ben.
//
// Futtatás a functions/ mappából:
//   FIREBASE_API_KEY=... DEV_EMAIL=... DEV_PASSWORD=... \
//     node scripts/backfill-project-id.mjs --dry-run
//   FIREBASE_API_KEY=... DEV_EMAIL=... DEV_PASSWORD=... \
//     node scripts/backfill-project-id.mjs
//
// Idempotens: a meglévő projectId-t nem írja felül.

const DRY = process.argv.includes('--dry-run');

const PROJECT = process.env.FIREBASE_PROJECT ?? 'projekt-labor-a4b1c';
const API_KEY = process.env.FIREBASE_API_KEY;
const EMAIL = process.env.DEV_EMAIL;
const PASSWORD = process.env.DEV_PASSWORD;

const DEFAULT_PROJECT_ID = process.env.DEFAULT_PROJECT_ID ?? 'nagyvazsony';

// A projektenként particionált tartalom-kollekciók.
const CONTENT_COLLECTIONS = [
  'trips',
  'stations',
  'events',
  'accommodations',
  'restaurants',
  'achievements',
  'about',
  'contact',
];

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

async function setProjectId(token, col, id) {
  const url = `${FS_BASE}/${col}/${id}?updateMask.fieldPaths=projectId`;
  const res = await fetch(url, {
    method: 'PATCH',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields: { projectId: { stringValue: DEFAULT_PROJECT_ID } } }),
  });
  const json = await res.json();
  if (json.error) throw new Error(`${col}/${id}: ${json.error.message}`);
}

async function run() {
  const token = await signIn();
  let total = 0;

  for (const col of CONTENT_COLLECTIONS) {
    let docs;
    try {
      docs = await listDocs(token, col);
    } catch (err) {
      console.log(`  ${col}: kihagyva (${err.message})`);
      continue;
    }

    let updated = 0;
    for (const doc of docs) {
      const id = doc.name.split('/').pop();
      const current = doc.fields?.projectId?.stringValue;
      if (typeof current === 'string' && current.trim() !== '') continue;
      if (!DRY) await setProjectId(token, col, id);
      updated += 1;
    }
    total += updated;
    console.log(`  ${col}: ${updated}/${docs.length} ${DRY ? 'frissítendő' : 'frissítve'}`);
  }

  console.log(
    `\n${DRY ? '[SZÁRAZ FUTTATÁS] ' : ''}Összesen ${total} dokumentum kap(ott) projectId-t ('${DEFAULT_PROJECT_ID}').`,
  );
}

run().catch((err) => {
  console.error('Backfill hiba:', err.message);
  process.exitCode = 1;
});
