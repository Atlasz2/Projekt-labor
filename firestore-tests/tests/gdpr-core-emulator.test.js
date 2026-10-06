// A GDPR-mag (functions/lib/gdpr-core.js) futtatása VALÓS Firestore
// (emulátor) ellen — bizonyítja, hogy a where('reported_by.user_id')
// beágyazott-mező szűrés, a batch-törlés és a subcollection-bejárás a valódi
// Firestore szemantikájával is a várt módon működik (nem csak a stubbal).

import { test, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

import { collectUserData, deleteUserData } from '../../functions/lib/gdpr-core.js';
import { renameUserCore } from '../../functions/lib/profile-core.js';

const PROJECT = 'demo-gdpr-core';
const uid = 'user-1';
let db;

before(() => {
  initializeApp({ projectId: PROJECT });
  db = getFirestore();
});

beforeEach(async () => {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  await fetch(
    `http://${host}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`,
    { method: 'DELETE' },
  );
});

async function seedFullUser() {
  await db.doc(`users/${uid}`).set({ email: 'teszt@example.com', name: 'Teszt Elek' });
  await db.doc(`user_progress/${uid}`).set({ totalPoints: 35, completedStations: ['st1'] });
  await db.doc(`user_progress/${uid}/unlocked_achievements/first_steps`).set({ at: new Date() });
  await db.doc(`user_progress/${uid}/completed_stations/st1`).set({ at: new Date() });
  await db.doc(`public_leaderboard/${uid}`).set({ displayName: 'Teszt Elek', points: 35 });
  await db.doc('usernames/tesztelek').set({ uid, normalized: 'tesztelek' });
  await db.doc('bug_reports/r1').set({
    message: 'Nem tölt a térkép',
    reported_by: { user_id: uid, email: 'teszt@example.com', name: 'Teszt Elek' },
  });
  // Idegen adat
  await db.doc('users/masik').set({ email: 'masik@example.com' });
  await db.doc('bug_reports/r2').set({
    message: 'Másik hibája',
    reported_by: { user_id: 'masik-uid' },
  });
}

test('collectUserData valós Firestore-on: teljes, saját adatokra szűkített export', async () => {
  await seedFullUser();

  const data = await collectUserData({ db, uid });

  assert.equal(data.profile.email, 'teszt@example.com');
  assert.equal(data.progress.totalPoints, 35);
  assert.equal(data.progressDetails.unlocked_achievements.length, 1);
  assert.equal(data.reservedUsernames.length, 1);
  assert.equal(data.bugReports.length, 1);
  assert.equal(data.bugReports[0].id, 'r1'); // az idegen r2 nincs benne
});

test('deleteUserData valós Firestore-on: saját adat törlődik, idegen érintetlen, bugreport anonim', async () => {
  await seedFullUser();

  const result = await deleteUserData({ db, uid, deleteAuthUser: async () => {} });

  // Saját adat eltűnt
  assert.equal((await db.doc(`users/${uid}`).get()).exists, false);
  assert.equal((await db.doc(`user_progress/${uid}`).get()).exists, false);
  assert.equal(
    (await db.doc(`user_progress/${uid}/unlocked_achievements/first_steps`).get()).exists,
    false,
  );
  assert.equal((await db.doc(`public_leaderboard/${uid}`).get()).exists, false);
  assert.equal((await db.doc('usernames/tesztelek').get()).exists, false);

  // Bugreport anonimizálva, nem törölve
  const r1 = (await db.doc('bug_reports/r1').get()).data();
  assert.equal(r1.message, 'Nem tölt a térkép');
  assert.equal(r1.reported_by.user_id, '[törölt fiók]');
  assert.equal(result.anonymizedBugReports, 1);

  // Idegen adat érintetlen
  assert.equal((await db.doc('users/masik').get()).exists, true);
  assert.equal((await db.doc('bug_reports/r2').get()).data().reported_by.user_id, 'masik-uid');
});

test('települési ranglista valós collectionGroup-pal: törléskor eltűnik, idegené marad', async () => {
  await db.doc(`users/${uid}`).set({ name: 'Teszt Elek' });
  await db.doc(`leaderboards/nagyvazsony/entries/${uid}`).set({ uid, displayName: 'Teszt Elek', points: 10 });
  await db.doc(`leaderboards/tapolca/entries/${uid}`).set({ uid, displayName: 'Teszt Elek', points: 4 });
  await db.doc('leaderboards/nagyvazsony/entries/masik').set({ uid: 'masik', displayName: 'Más', points: 3 });

  const exported = await collectUserData({ db, uid });
  assert.equal(exported.projectLeaderboardEntries.length, 2);

  await deleteUserData({ db, uid });
  assert.equal((await db.doc(`leaderboards/nagyvazsony/entries/${uid}`).get()).exists, false);
  assert.equal((await db.doc(`leaderboards/tapolca/entries/${uid}`).get()).exists, false);
  assert.equal((await db.doc('leaderboards/nagyvazsony/entries/masik').get()).exists, true);
});

test('névmódosítás valós Firestore-on: foglalás, profil és minden ranglista frissül', async () => {
  await db.doc('usernames/teszt elek').set({ uid, normalized: 'teszt elek' });
  await db.doc(`users/${uid}`).set({ name: 'Teszt Elek', displayName: 'Teszt Elek' });
  await db.doc(`user_progress/${uid}`).set({ name: 'Teszt Elek', totalPoints: 10 });
  await db.doc(`leaderboards/nagyvazsony/entries/${uid}`).set({ uid, displayName: 'Teszt Elek', points: 10 });

  await renameUserCore({ db, FieldValue, uid, name: 'Kinizsi Pál' });

  assert.equal((await db.doc('usernames/teszt elek').get()).exists, false);
  assert.equal((await db.doc('usernames/kinizsi pál').get()).data().uid, uid);
  assert.equal((await db.doc(`users/${uid}`).get()).data().displayName, 'Kinizsi Pál');
  assert.equal((await db.doc(`user_progress/${uid}`).get()).data().name, 'Kinizsi Pál');
  assert.equal(
    (await db.doc(`leaderboards/nagyvazsony/entries/${uid}`).get()).data().displayName,
    'Kinizsi Pál',
  );
});
