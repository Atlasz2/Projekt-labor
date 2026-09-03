// Migráció: a Firestore dokumentumokba ágyazott base64 (data:) képek átmozgatása
// Firebase Storage-ba, és a mezők lecserélése a letöltési URL-re.
//
// MIÉRT: a beágyazott képek miatt egy állomás-dokumentum ~460 KB is lehet
// (ráadásul a photos / photoUrls / imageUrl mezőkben háromszorosan duplikálva),
// ami minden admin-oldalbetöltésnél letöltődik. Migráció után ~0,2 KB.
//
// Nem kell service account: a developer fiók bejelentkezésével (REST) dolgozik.
//
// Futtatás a functions/ mappából:
//   FIREBASE_API_KEY=... DEV_EMAIL=... DEV_PASSWORD=... \
//     node scripts/migrate-inline-images.mjs --dry-run
//   FIREBASE_API_KEY=... DEV_EMAIL=... DEV_PASSWORD=... \
//     node scripts/migrate-inline-images.mjs --backup-dir ./backup
//
// A --dry-run csak jelent, nem ír. Éles futtatáskor a --backup-dir mappába
// minden érintett dokumentum eredeti állapota lementődik (visszaállíthatóság).

import fs from 'node:fs';
import path from 'node:path';

const DRY = process.argv.includes('--dry-run');
const backupIdx = process.argv.indexOf('--backup-dir');
const BACKUP_DIR = backupIdx !== -1 ? process.argv[backupIdx + 1] : null;

const PROJECT = process.env.FIREBASE_PROJECT ?? 'projekt-labor-a4b1c';
const BUCKET = process.env.STORAGE_BUCKET ?? `${PROJECT}.firebasestorage.app`;
const API_KEY = process.env.FIREBASE_API_KEY;
const EMAIL = process.env.DEV_EMAIL;
const PASSWORD = process.env.DEV_PASSWORD;

// Ezekben a kollekciókban keresünk beágyazott képet.
const COLLECTIONS = ['stations', 'events', 'restaurants', 'accommodations', 'about'];

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

const isDataUrl = (s) => typeof s === 'string' && s.startsWith('data:');

// Egy Firestore REST érték összes data: URL-jének begyűjtése (rekurzívan).
function collectDataUrls(value, acc = []) {
  if (!value || typeof value !== 'object') return acc;
  if ('stringValue' in value && isDataUrl(value.stringValue)) acc.push(value.stringValue);
  if ('arrayValue' in value) {
    for (const v of value.arrayValue.values ?? []) collectDataUrls(v, acc);
  }
  if ('mapValue' in value) {
    for (const v of Object.values(value.mapValue.fields ?? {})) collectDataUrls(v, acc);
  }
  return acc;
}

// Ugyanaz a szerkezet, de a data: URL-ek lecserélve a térkép szerint.
function replaceDataUrls(value, map) {
  if (!value || typeof value !== 'object') return value;
  if ('stringValue' in value && isDataUrl(value.stringValue)) {
    return { stringValue: map.get(value.stringValue) ?? value.stringValue };
  }
  if ('arrayValue' in value) {
    return {
      arrayValue: {
        values: (value.arrayValue.values ?? []).map((v) => replaceDataUrls(v, map)),
      },
    };
  }
  if ('mapValue' in value) {
    const fields = {};
    for (const [k, v] of Object.entries(value.mapValue.fields ?? {})) {
      fields[k] = replaceDataUrls(v, map);
    }
    return { mapValue: { fields } };
  }
  return value;
}

function decodeDataUrl(dataUrl) {
  const m = dataUrl.match(/^data:([^;,]+)?(;base64)?,([\s\S]*)$/);
  if (!m) return null;
  const mime = m[1] || 'image/jpeg';
  const buf = m[2]
    ? Buffer.from(m[3], 'base64')
    : Buffer.from(decodeURIComponent(m[3]), 'utf8');
  const ext = (mime.split('/')[1] || 'jpg').split('+')[0];
  return { buf, mime, ext };
}

async function uploadToStorage(token, buf, mime, objectPath) {
  const url = `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o?uploadType=media&name=${encodeURIComponent(objectPath)}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': mime },
    body: buf,
  });
  const json = await res.json();
  if (json.error) throw new Error(`Storage feltöltés: ${json.error.message}`);
  const dlToken = (json.downloadTokens ?? '').split(',')[0];
  return `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(objectPath)}?alt=media&token=${dlToken}`;
}

async function patchDoc(token, col, id, fields) {
  const mask = Object.keys(fields)
    .map((f) => `updateMask.fieldPaths=${encodeURIComponent(f)}`)
    .join('&');
  const res = await fetch(`${FS_BASE}/${col}/${id}?${mask}`, {
    method: 'PATCH',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields }),
  });
  const json = await res.json();
  if (json.error) throw new Error(`Firestore írás: ${json.error.message}`);
}

async function run() {
  const token = await signIn();
  if (BACKUP_DIR && !DRY) fs.mkdirSync(BACKUP_DIR, { recursive: true });

  let totalDocs = 0;
  let totalImages = 0;
  let sizeDelta = 0;

  for (const col of COLLECTIONS) {
    const docs = await listDocs(token, col);
    for (const doc of docs) {
      const id = doc.name.split('/').pop();
      const fields = doc.fields ?? {};
      const before = JSON.stringify(doc).length;

      // Egyedi data: URL-ek (a duplikátumokat csak egyszer töltjük fel).
      const unique = [
        ...new Set(Object.values(fields).flatMap((v) => collectDataUrls(v))),
      ];
      if (unique.length === 0) continue;

      totalDocs += 1;
      totalImages += unique.length;

      if (DRY) {
        console.log(
          `  [DRY] ${col}/${id}: ${unique.length} beágyazott kép, doksi ${(before / 1024).toFixed(1)} KB`,
        );
        sizeDelta += before;
        continue;
      }

      if (BACKUP_DIR) {
        fs.writeFileSync(
          path.join(BACKUP_DIR, `${col}__${id}.json`),
          JSON.stringify(doc, null, 2),
        );
      }

      const map = new Map();
      for (let i = 0; i < unique.length; i += 1) {
        const dec = decodeDataUrl(unique[i]);
        if (!dec) continue;
        const objectPath = `migrated/${col}/${id}_${i}.${dec.ext}`;
        map.set(unique[i], await uploadToStorage(token, dec.buf, dec.mime, objectPath));
      }

      const updated = {};
      for (const [k, v] of Object.entries(fields)) {
        if (collectDataUrls(v).length > 0) updated[k] = replaceDataUrls(v, map);
      }
      await patchDoc(token, col, id, updated);

      const after = JSON.stringify({ fields: { ...fields, ...updated } }).length;
      sizeDelta += before - after;
      console.log(
        `  ${col}/${id}: ${unique.length} kép -> Storage, ${(before / 1024).toFixed(1)} KB -> ${(after / 1024).toFixed(1)} KB`,
      );
    }
  }

  console.log(
    `\n${DRY ? '[SZÁRAZ FUTTATÁS] ' : ''}Érintett dokumentum: ${totalDocs}, kép: ${totalImages}`,
  );
  console.log(
    `${DRY ? 'Jelenlegi összméret' : 'Megtakarítás'}: ${(sizeDelta / 1024).toFixed(1)} KB`,
  );
}

run().catch((err) => {
  console.error('Migrációs hiba:', err.message);
  process.exitCode = 1;
});
