// Fejlesztői (developer) fiók létrehozása vagy frissítése az admin panelhez.
//
// A developer a platform-szintű szerep: mindent lát, amit az admin, plusz a
// "Fejlesztő" fülön több települést (projektet) kezelhet.
//
// FONTOS: a jelszó NEM kerül a repóba – környezeti változóból vagy parancssori
// argumentumból jön, hogy ne legyen verziókövetve.
//
// Futtatás (a functions/ mappából, service accounttal):
//   GOOGLE_APPLICATION_CREDENTIALS=<service-account.json> \
//   DEV_EMAIL=valaki@example.com DEV_PASSWORD='titkos-jelszo' \
//   node scripts/create-developer.mjs
//
// Vagy argumentumként:
//   node scripts/create-developer.mjs valaki@example.com 'titkos-jelszo'
//
// Idempotens: ha a fiók már létezik, a jelszót frissíti és a szerepet
// developer-re állítja.

import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const email = (process.env.DEV_EMAIL ?? process.argv[2] ?? '').trim();
const password = process.env.DEV_PASSWORD ?? process.argv[3] ?? '';

if (!email || !password) {
  console.error(
    'Hiányzó adat.\n' +
      'Használat: DEV_EMAIL=... DEV_PASSWORD=... node scripts/create-developer.mjs\n' +
      '      vagy: node scripts/create-developer.mjs <email> <jelszo>',
  );
  process.exit(1);
}
if (password.length < 6) {
  console.error('A jelszónak legalább 6 karakteresnek kell lennie.');
  process.exit(1);
}

initializeApp({
  credential: applicationDefault(),
  projectId: process.env.GCLOUD_PROJECT ?? 'projekt-labor-a4b1c',
});

const auth = getAuth();
const db = getFirestore();

async function ensureAuthUser() {
  try {
    const existing = await auth.getUserByEmail(email);
    await auth.updateUser(existing.uid, { password, emailVerified: true });
    console.log(`Auth: meglévő fiók frissítve (${email})`);
    return existing.uid;
  } catch (err) {
    if (err?.code !== 'auth/user-not-found') throw err;
    const created = await auth.createUser({
      email,
      password,
      emailVerified: true,
      displayName: 'Developer',
    });
    console.log(`Auth: új fiók létrehozva (${email})`);
    return created.uid;
  }
}

async function run() {
  const uid = await ensureAuthUser();

  // A firestore.rules a users/{uid}.role mezőt nézi (elsődleges, nem hamisítható).
  await db.collection('users').doc(uid).set(
    {
      uid,
      email,
      name: 'Developer',
      displayName: 'Developer',
      role: 'developer',
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  console.log(`Firestore: users/${uid} -> role: 'developer'`);
  console.log('\nKész. Jelentkezz be az admin panelbe ezzel az email-címmel.');
}

run().catch((err) => {
  console.error('Hiba a developer fiók létrehozásakor:', err);
  process.exitCode = 1;
});
