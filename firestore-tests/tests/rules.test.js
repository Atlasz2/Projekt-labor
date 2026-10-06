// A firestore.rules támadási forgatókönyv-tesztjei (Firestore-emulátor ellen).
// Futtatás a gyökérből: `npm run rules:test` (JDK 21+ szükséges).
//
// A fenyegetésmodell vektorai (docs/SZAKDOLGOZAT_BIZTONSAG.md):
// T1 pontfelfújás létrehozáskor, T2 pontfelfújás módosítással, T3 rongálás,
// T4 idegen adat írása, T5 jogosultság-eszkaláció, T6 ranglista-hamisítás,
// T7 QR-enumeráció, T8 tartalom írása – plusz a white-label tenant-izoláció.

import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';

import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { deleteDoc, deleteField, doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';

let env;

const ALICE = 'alice-uid';
const BOB = 'bob-uid';
const ADMIN = 'admin-uid';
const OTHER_ADMIN = 'mencshely-admin-uid';
const DEV = 'dev-uid';

const dbAs = (uid, email) => env.authenticatedContext(uid, email ? { email } : {}).firestore();
const aliceDb = () => dbAs(ALICE, 'alice@example.com');
const adminDb = () => dbAs(ADMIN, 'admin@example.com');
const otherAdminDb = () => dbAs(OTHER_ADMIN, 'm@example.com');
const devDb = () => dbAs(DEV, 'dev@example.com');

async function seed(path, data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), path), data);
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-rules',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});

after(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await seed(`users/${ADMIN}`, { email: 'admin@example.com', role: 'admin' });
  await seed(`users/${OTHER_ADMIN}`, { email: 'm@example.com', role: 'admin', projectId: 'mencshely' });
  await seed(`users/${DEV}`, { email: 'dev@example.com', role: 'developer' });
});

// ── user_progress: csak a szerver ír pontot ─────────────────────────────────

test('nem bejelentkezett látogató nem olvashat user_progress-t', async () => {
  await seed(`user_progress/${ALICE}`, { totalPoints: 10 });
  const db = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, `user_progress/${ALICE}`)));
});

test('regisztráció: a saját progress doksi nullázott számlálókkal létrehozható', async () => {
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

test('TÁMADÁS (T1): hamis kezdőértékekkel való létrehozás tiltva', async () => {
  await assertFails(
    setDoc(doc(aliceDb(), `user_progress/${ALICE}`), { totalPoints: 999999 }),
  );
  await assertFails(
    setDoc(doc(aliceDb(), `user_progress/${ALICE}`), {
      totalPoints: 0,
      completedStations: ['st1', 'st2', 'st3'],
    }),
  );
});

test('TÁMADÁS (T2): pontnövelés update-tel tiltva', async () => {
  await seed(`user_progress/${ALICE}`, { totalPoints: 10, completedStations: [] });
  await assertFails(
    updateDoc(doc(aliceDb(), `user_progress/${ALICE}`), { totalPoints: 999999 }),
  );
});

test('TÁMADÁS (T2): teljesített állomás kliensoldali hozzáadása tiltva', async () => {
  await seed(`user_progress/${ALICE}`, { totalPoints: 10, completedStations: [] });
  await assertFails(
    updateDoc(doc(aliceDb(), `user_progress/${ALICE}`), { completedStations: ['st1'] }),
  );
});

test('TÁMADÁS (T3): pontcsökkentés és állomás eltávolítása tiltva', async () => {
  await seed(`user_progress/${ALICE}`, { totalPoints: 100, completedStations: ['st1', 'st2'] });
  await assertFails(updateDoc(doc(aliceDb(), `user_progress/${ALICE}`), { totalPoints: 50 }));
  await assertFails(
    updateDoc(doc(aliceDb(), `user_progress/${ALICE}`), { completedStations: ['st1'] }),
  );
});

test('a jutalom-értesítés nyugtázása (egyetlen kliens-update) engedett', async () => {
  await seed(`user_progress/${ALICE}`, {
    totalPoints: 10,
    pendingAchievementBanner: { title: 'Jutalom', subtitle: '' },
  });
  await assertSucceeds(
    updateDoc(doc(aliceDb(), `user_progress/${ALICE}`), {
      pendingAchievementBanner: deleteField(),
    }),
  );
});

test('TÁMADÁS: a banner-nyugtázásba csempészett pontmódosítás tiltva', async () => {
  await seed(`user_progress/${ALICE}`, {
    totalPoints: 10,
    pendingAchievementBanner: { title: 'Jutalom', subtitle: '' },
  });
  await assertFails(
    updateDoc(doc(aliceDb(), `user_progress/${ALICE}`), {
      pendingAchievementBanner: deleteField(),
      totalPoints: 500,
    }),
  );
});

test('TÁMADÁS: jutalom önfeloldása (unlocked_achievements írása) tiltva', async () => {
  await seed(`user_progress/${ALICE}`, { totalPoints: 0 });
  await assertFails(
    setDoc(doc(aliceDb(), `user_progress/${ALICE}/unlocked_achievements/kedvezmeny`), {
      unlockedAt: 1,
    }),
  );
  await assertFails(
    setDoc(doc(aliceDb(), `user_progress/${ALICE}/completed_stations/st1`), { at: 1 }),
  );
});

test('a saját feloldott jutalmak olvashatók, az idegenéi nem', async () => {
  await seed(`user_progress/${ALICE}/unlocked_achievements/a1`, { unlockedAt: 1 });
  await seed(`user_progress/${BOB}/unlocked_achievements/a1`, { unlockedAt: 1 });
  await assertSucceeds(getDoc(doc(aliceDb(), `user_progress/${ALICE}/unlocked_achievements/a1`)));
  await assertFails(getDoc(doc(aliceDb(), `user_progress/${BOB}/unlocked_achievements/a1`)));
});

test('admin kézzel odaítélhet jutalmat', async () => {
  await assertSucceeds(
    setDoc(doc(adminDb(), `user_progress/${ALICE}/unlocked_achievements/kezi`), { unlockedAt: 1 }),
  );
});

test('TÁMADÁS (T4): más felhasználó progress doksijának írása tiltva', async () => {
  await seed(`user_progress/${BOB}`, { totalPoints: 5 });
  await assertFails(updateDoc(doc(aliceDb(), `user_progress/${BOB}`), { totalPoints: 500 }));
  await assertFails(setDoc(doc(aliceDb(), 'user_progress/uj-aldozat'), { totalPoints: 0 }));
});

// ── users / szerepkörök ────────────────────────────────────────────────────

test('TÁMADÁS (T5): role-eszkaláció a saját users doksin tiltva', async () => {
  await assertFails(
    setDoc(doc(aliceDb(), `users/${ALICE}`), { email: 'alice@example.com', role: 'admin' }),
  );
  await assertSucceeds(
    setDoc(doc(aliceDb(), `users/${ALICE}`), { email: 'alice@example.com', role: 'user' }),
  );
  await assertFails(updateDoc(doc(aliceDb(), `users/${ALICE}`), { role: 'admin' }));
});

test('admin nem nevezhet ki adminisztrátort, a developer igen', async () => {
  await seed(`users/${ALICE}`, { email: 'alice@example.com', role: 'user' });
  await assertFails(updateDoc(doc(adminDb(), `users/${ALICE}`), { role: 'admin' }));
  await assertSucceeds(updateDoc(doc(devDb(), `users/${ALICE}`), { role: 'admin' }));
});

test('felhasználót csak developer törölhet', async () => {
  await seed(`users/${ALICE}`, { email: 'alice@example.com', role: 'user' });
  await assertFails(deleteDoc(doc(adminDb(), `users/${ALICE}`)));
  await assertSucceeds(deleteDoc(doc(devDb(), `users/${ALICE}`)));
});

// ── tartalom és tenant-izoláció ────────────────────────────────────────────

test('TÁMADÁS (T8): nem admin nem írhat tartalmi kollekciókat', async () => {
  await assertFails(setDoc(doc(aliceDb(), 'stations/hamis'), { name: 'Hamis', points: 1000 }));
  await assertFails(setDoc(doc(aliceDb(), 'achievements/hamis'), { conditionValue: 0 }));
});

test('admin a saját (alapértelmezett) településére írhat tartalmat', async () => {
  await assertSucceeds(setDoc(doc(adminDb(), 'stations/uj'), { name: 'Új állomás', points: 10 }));
  await assertSucceeds(
    setDoc(doc(adminDb(), 'stations/uj2'), { name: 'Új', projectId: 'nagyvazsony' }),
  );
});

test('TENANT: admin nem írhat másik település tartalmába', async () => {
  await assertFails(
    setDoc(doc(adminDb(), 'stations/idegen'), { name: 'Idegen', projectId: 'mencshely' }),
  );
  await seed('stations/m1', { name: 'Mencshelyi', projectId: 'mencshely' });
  await assertFails(updateDoc(doc(adminDb(), 'stations/m1'), { name: 'Átírva' }));
  await assertFails(deleteDoc(doc(adminDb(), 'stations/m1')));
  await assertSucceeds(updateDoc(doc(otherAdminDb(), 'stations/m1'), { name: 'Saját' }));
});

test('TENANT: admin nem mozgathat tartalmat másik településre', async () => {
  await seed('stations/n1', { name: 'Vár' });
  await assertFails(updateDoc(doc(adminDb(), 'stations/n1'), { projectId: 'mencshely' }));
});

test('developer bármely település tartalmát kezelheti, és települést hozhat létre', async () => {
  await assertSucceeds(
    setDoc(doc(devDb(), 'stations/m2'), { name: 'Mencshelyi 2', projectId: 'mencshely' }),
  );
  await assertSucceeds(setDoc(doc(devDb(), 'projects/mencshely'), { name: 'Mencshely' }));
  await assertFails(setDoc(doc(adminDb(), 'projects/hamis'), { name: 'Hamis' }));
});

// ── ranglisták, QR-leképezés, hibabejelentés ───────────────────────────────

test('TÁMADÁS (T6): leaderboard-hamisítás nem egyező ponttal tiltva', async () => {
  await seed(`user_progress/${ALICE}`, { totalPoints: 10 });
  await assertFails(
    setDoc(doc(aliceDb(), `public_leaderboard/${ALICE}`), { displayName: 'Alice', points: 999999 }),
  );
  await assertFails(
    setDoc(doc(dbAs(BOB), `public_leaderboard/${BOB}`), { displayName: 'Bob', points: 0 }),
  );
});

test('leaderboard a user_progress-szel egyező ponttal engedett', async () => {
  await seed(`user_progress/${ALICE}`, { totalPoints: 10 });
  await assertSucceeds(
    setDoc(doc(aliceDb(), `public_leaderboard/${ALICE}`), { displayName: 'Alice', points: 10 }),
  );
});

test('TÁMADÁS (T6): a települési ranglistát kliens nem írhatja, de olvashatja', async () => {
  await assertFails(
    setDoc(doc(aliceDb(), `leaderboards/nagyvazsony/entries/${ALICE}`), { points: 999 }),
  );
  await seed(`leaderboards/nagyvazsony/entries/${BOB}`, { points: 5 });
  await assertSucceeds(getDoc(doc(aliceDb(), `leaderboards/nagyvazsony/entries/${BOB}`)));
});

test('TÁMADÁS (T7): qr_codes enumeráció és írás userként tiltva', async () => {
  await seed('qr_codes/TITKOS-KOD', { kind: 'station', targetId: 'st1' });
  await assertFails(getDoc(doc(aliceDb(), 'qr_codes/TITKOS-KOD')));
  await assertFails(setDoc(doc(aliceDb(), 'qr_codes/HAMIS'), { kind: 'station', targetId: 'x' }));
  await assertSucceeds(getDoc(doc(adminDb(), 'qr_codes/TITKOS-KOD')));
});

test('bug_reports: saját jelentés olvasható, másé nem', async () => {
  await seed('bug_reports/r1', { title: 'Bob hibája', reported_by: { user_id: BOB } });
  await seed('bug_reports/r2', { title: 'Alice hibája', reported_by: { user_id: ALICE } });
  await assertFails(getDoc(doc(aliceDb(), 'bug_reports/r1')));
  await assertSucceeds(getDoc(doc(aliceDb(), 'bug_reports/r2')));
});

test('bug_reports: csak a saját nevében, korlátos hosszal küldhető', async () => {
  const report = (userId, description) => ({
    title: 'Hiba',
    description,
    projectId: 'nagyvazsony',
    reported_by: { user_id: userId, name: 'Alice' },
  });
  await assertSucceeds(setDoc(doc(aliceDb(), 'bug_reports/ok'), report(ALICE, 'Nem tölt be a térkép.')));
  await assertFails(setDoc(doc(aliceDb(), 'bug_reports/hamis'), report(BOB, 'Bob nevében')));
  await assertFails(setDoc(doc(aliceDb(), 'bug_reports/hosszu'), report(ALICE, 'x'.repeat(4001))));
});

test('bug_reports: a beküldő javíthatja a nyitott bejelentés leírását, mást nem', async () => {
  await seed('bug_reports/sajat', { description: 'Régi', status: 'open', admin_response: '', reported_by: { user_id: ALICE } });
  await assertSucceeds(updateDoc(doc(aliceDb(), 'bug_reports/sajat'), { description: 'Pontosított leírás' }));
  await assertFails(updateDoc(doc(aliceDb(), 'bug_reports/sajat'), { status: 'closed' }));
  await assertFails(updateDoc(doc(aliceDb(), 'bug_reports/sajat'), { admin_response: 'Kész' }));
  await assertFails(updateDoc(doc(aliceDb(), 'bug_reports/sajat'), { 'reported_by.user_id': BOB }));
});

test('bug_reports: lezárt bejelentés már nem szerkeszthető, de visszavonható', async () => {
  await seed('bug_reports/lezart', { description: 'Hiba', status: 'closed', reported_by: { user_id: ALICE } });
  await assertFails(updateDoc(doc(aliceDb(), 'bug_reports/lezart'), { description: 'Más' }));
  await assertSucceeds(deleteDoc(doc(aliceDb(), 'bug_reports/lezart')));
});

test('bug_reports: más bejelentését nem szerkesztheti és nem törölheti', async () => {
  await seed('bug_reports/idegen', { description: 'Bobé', status: 'open', reported_by: { user_id: BOB } });
  await assertFails(updateDoc(doc(aliceDb(), 'bug_reports/idegen'), { description: 'Átírva' }));
  await assertFails(deleteDoc(doc(aliceDb(), 'bug_reports/idegen')));
});
