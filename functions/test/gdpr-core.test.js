import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { collectUserData, deleteUserData } from '../lib/gdpr-core.js';
import { FakeFirestore } from './fake-firestore.js';

const uid = 'user-1';
let db;

function seedFullUser() {
  db.seed(`users/${uid}`, { email: 'teszt@example.com', name: 'Teszt Elek', role: 'user' });
  db.seed(`user_progress/${uid}`, {
    name: 'Teszt Elek',
    totalPoints: 35,
    completedStations: ['st1'],
    completedEvents: ['ev1'],
  });
  db.seed(`user_progress/${uid}/unlocked_achievements/first_steps`, { unlockedAt: new Date() });
  db.seed(`user_progress/${uid}/completed_stations/st1`, { at: new Date() });
  db.seed(`public_leaderboard/${uid}`, { displayName: 'Teszt Elek', points: 35 });
  db.seed('usernames/tesztelek', { uid, normalized: 'tesztelek' });
  db.seed('bug_reports/r1', {
    message: 'Nem tölt a térkép',
    reported_by: { user_id: uid, email: 'teszt@example.com', name: 'Teszt Elek' },
  });
  // Más felhasználó adatai — ezekhez nem szabad nyúlni.
  db.seed('users/masik', { email: 'masik@example.com', role: 'user' });
  db.seed('usernames/masik', { uid: 'masik-uid' });
  db.seed('bug_reports/r2', {
    message: 'Másik hibája',
    reported_by: { user_id: 'masik-uid' },
  });
}

beforeEach(() => {
  db = new FakeFirestore();
});

test('collectUserData: minden saját adat bekerül az exportba', async () => {
  seedFullUser();

  const data = await collectUserData({ db, uid });

  assert.equal(data.uid, uid);
  assert.equal(data.profile.email, 'teszt@example.com');
  assert.equal(data.progress.totalPoints, 35);
  assert.equal(data.progressDetails.unlocked_achievements.length, 1);
  assert.equal(data.progressDetails.unlocked_achievements[0].id, 'first_steps');
  assert.equal(data.progressDetails.completed_stations.length, 1);
  assert.equal(data.leaderboardEntry.points, 35);
  assert.equal(data.reservedUsernames.length, 1);
  assert.equal(data.reservedUsernames[0].id, 'tesztelek');
  assert.equal(data.bugReports.length, 1);
  assert.equal(data.bugReports[0].id, 'r1');
  assert.ok(data.exportedAt);
});

test('collectUserData: idegen adat nem szivárog az exportba', async () => {
  seedFullUser();

  const data = await collectUserData({ db, uid });

  assert.ok(!data.reservedUsernames.some((u) => u.id === 'masik'));
  assert.ok(!data.bugReports.some((r) => r.id === 'r2'));
});

test('collectUserData: üres fiókra is értelmes (null-os) exportot ad', async () => {
  const data = await collectUserData({ db, uid });

  assert.equal(data.profile, null);
  assert.equal(data.progress, null);
  assert.deepEqual(data.reservedUsernames, []);
  assert.deepEqual(data.bugReports, []);
});

test('deleteUserData: minden saját dokumentum törlődik, az Auth-fiókkal együtt', async () => {
  seedFullUser();
  const authDeleted = [];

  const result = await deleteUserData({
    db,
    uid,
    deleteAuthUser: async (u) => authDeleted.push(u),
  });

  assert.equal(db.read(`users/${uid}`), undefined);
  assert.equal(db.read(`user_progress/${uid}`), undefined);
  assert.equal(db.read(`user_progress/${uid}/unlocked_achievements/first_steps`), undefined);
  assert.equal(db.read(`user_progress/${uid}/completed_stations/st1`), undefined);
  assert.equal(db.read(`public_leaderboard/${uid}`), undefined);
  assert.equal(db.read('usernames/tesztelek'), undefined);
  assert.deepEqual(authDeleted, [uid]);
  assert.ok(result.deleted.includes(`users/${uid}`));
});

test('deleteUserData: a hibabejelentés anonimizálódik, nem törlődik', async () => {
  seedFullUser();

  const result = await deleteUserData({ db, uid, deleteAuthUser: async () => {} });

  const report = db.read('bug_reports/r1');
  assert.ok(report, 'a bejelentés megmarad');
  assert.equal(report.message, 'Nem tölt a térkép');
  assert.equal(report.reported_by.user_id, '[törölt fiók]');
  assert.equal(report.reported_by.email, null);
  assert.equal(result.anonymizedBugReports, 1);
});

test('deleteUserData: idegen adatot nem érint', async () => {
  seedFullUser();

  await deleteUserData({ db, uid, deleteAuthUser: async () => {} });

  assert.ok(db.read('users/masik'));
  assert.ok(db.read('usernames/masik'));
  assert.equal(db.read('bug_reports/r2').reported_by.user_id, 'masik-uid');
});

test('deleteUserData: üres fiókra sem dob hibát', async () => {
  const result = await deleteUserData({ db, uid, deleteAuthUser: async () => {} });
  assert.equal(result.anonymizedBugReports, 0);
});
