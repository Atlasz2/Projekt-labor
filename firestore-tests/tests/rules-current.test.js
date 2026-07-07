// A JELENLEGI firestore.rules támadási forgatókönyv-tesztjei.
// Futtatás: a gyökérből `npm run rules:test` (Firestore-emulátort igényel,
// JDK 11+). A tesztek dokumentálják, mely vektorok zártak most, és melyik
// marad nyitva a lockdown-ig (lásd rules-lockdown.test.js).

import { test, before, after } from 'node:test';
import { readFileSync } from 'node:fs';

import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';

let env;

const ALICE = 'alice-uid';
const BOB = 'bob-uid';
const ADMIN = 'admin-uid';

function aliceDb() {
  return env.authenticatedContext(ALICE, { email: 'alice@example.com' }).firestore();
}

function adminDb() {
  return env.authenticatedContext(ADMIN, { email: 'admin@example.com' }).firestore();
}

async function seed(path, data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), path), data);
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-rules-current',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});

after(async () => {
  await env.cleanup();
});

test('nem bejelentkezett látogató nem olvashat user_progress-t', async () => {
  await seed(`user_progress/${ALICE}`, { totalPoints: 10 });
  const db = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, `user_progress/${ALICE}`)));
});

test('user létrehozhatja a saját progress doksiját nullázott számlálókkal', async () => {
  await env.clearFirestore();
  await assertSucceeds(
    setDoc(doc(aliceDb(), `user_progress/${ALICE}`), {
      name: 'Alice',
      totalPoints: 0,
      completedStations: [],
      completedEvents: [],
      completedTripIds: [],
    }),
  );
});

test('TÁMADÁS: hamis kezdőpontokkal való létrehozás tiltva', async () => {
  await env.clearFirestore();
  await assertFails(
    setDoc(doc(aliceDb(), `user_progress/${ALICE}`), {
      totalPoints: 999999,
      completedStations: [],
      completedEvents: [],
    }),
  );
  await assertFails(
    setDoc(doc(aliceDb(), `user_progress/${ALICE}`), {
      totalPoints: 0,
      completedStations: ['st1', 'st2', 'st3'],
      completedEvents: [],
    }),
  );
});

test('TÁMADÁS: pontcsökkentés (monoton szabály) tiltva', async () => {
  await seed(`user_progress/${ALICE}`, { totalPoints: 100, completedStations: [] });
  await assertFails(
    updateDoc(doc(aliceDb(), `user_progress/${ALICE}`), { totalPoints: 50 }),
  );
});

test('TÁMADÁS: teljesített állomás eltávolítása tiltva', async () => {
  await seed(`user_progress/${ALICE}`, {
    totalPoints: 20,
    completedStations: ['st1', 'st2'],
  });
  await assertFails(
    updateDoc(doc(aliceDb(), `user_progress/${ALICE}`), {
      completedStations: ['st1'],
    }),
  );
});

test('ISMERT KORLÁT: a pontnövelés update-tel jelenleg átmegy — ezt a lockdown zárja', async () => {
  await seed(`user_progress/${ALICE}`, { totalPoints: 10, completedStations: [] });
  // Ez a dokumentált, tudatosan vállalt maradék kockázat a Cloud Function
  // deploy-ja előtt (lásd docs/SERVER_VALIDATION.md és a lockdown teszteket).
  await assertSucceeds(
    updateDoc(doc(aliceDb(), `user_progress/${ALICE}`), { totalPoints: 999999 }),
  );
});

test('TÁMADÁS: más felhasználó progress doksijának írása tiltva', async () => {
  await seed(`user_progress/${BOB}`, { totalPoints: 5 });
  await assertFails(
    updateDoc(doc(aliceDb(), `user_progress/${BOB}`), { totalPoints: 500 }),
  );
  await assertFails(
    setDoc(doc(aliceDb(), 'user_progress/uj-aldozat'), { totalPoints: 0 }),
  );
});

test('TÁMADÁS: role-eszkaláció a saját users doksin tiltva', async () => {
  await env.clearFirestore();
  // create role: admin
  await assertFails(
    setDoc(doc(aliceDb(), `users/${ALICE}`), {
      email: 'alice@example.com',
      role: 'admin',
    }),
  );
  // létrehozás user-ként, majd önkinevezés
  await assertSucceeds(
    setDoc(doc(aliceDb(), `users/${ALICE}`), {
      email: 'alice@example.com',
      role: 'user',
    }),
  );
  await assertFails(
    updateDoc(doc(aliceDb(), `users/${ALICE}`), { role: 'admin' }),
  );
});

test('TÁMADÁS: nem admin nem írhat tartalmi kollekciókat', async () => {
  await assertFails(
    setDoc(doc(aliceDb(), 'stations/hamis'), { name: 'Hamis állomás', points: 1000 }),
  );
  await assertFails(
    setDoc(doc(aliceDb(), 'achievements/hamis'), { conditionValue: 0 }),
  );
});

test('admin írhat tartalmi kollekciókat', async () => {
  await seed(`users/${ADMIN}`, { email: 'admin@example.com', role: 'admin' });
  await assertSucceeds(
    setDoc(doc(adminDb(), 'stations/uj'), { name: 'Új állomás', points: 10 }),
  );
});

test('TÁMADÁS: leaderboard-hamisítás nem egyező ponttal tiltva', async () => {
  await seed(`user_progress/${ALICE}`, { totalPoints: 10, completedStations: [] });
  await assertFails(
    setDoc(doc(aliceDb(), `public_leaderboard/${ALICE}`), {
      displayName: 'Alice',
      points: 999999,
    }),
  );
  // user_progress doksi nélkül sem megy (bypass-védelem)
  const bobDb = env.authenticatedContext(BOB).firestore();
  await assertFails(
    setDoc(doc(bobDb, `public_leaderboard/${BOB}`), {
      displayName: 'Bob',
      points: 0,
    }),
  );
});

test('leaderboard a user_progress-szel egyező ponttal engedett', async () => {
  await seed(`user_progress/${ALICE}`, { totalPoints: 10, completedStations: [] });
  await assertSucceeds(
    setDoc(doc(aliceDb(), `public_leaderboard/${ALICE}`), {
      displayName: 'Alice',
      points: 10,
    }),
  );
});

test('TÁMADÁS: qr_codes enumeráció userként tiltva', async () => {
  await seed('qr_codes/TITKOS-KOD', { kind: 'station', targetId: 'st1' });
  await assertFails(getDoc(doc(aliceDb(), 'qr_codes/TITKOS-KOD')));
  await assertFails(
    setDoc(doc(aliceDb(), 'qr_codes/HAMIS'), { kind: 'station', targetId: 'x' }),
  );
});

test('bug_reports: más felhasználó jelentése nem olvasható', async () => {
  await seed('bug_reports/r1', {
    message: 'Bob hibája',
    reported_by: { user_id: BOB },
  });
  await assertFails(getDoc(doc(aliceDb(), 'bug_reports/r1')));
});
