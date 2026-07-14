// A redeemQr mag (functions/lib/redeem-core.js) futtatása VALÓS Firestore
// (emulátor) ellen — a functions/test alatti stub-tesztek kiegészítése:
// itt a tényleges tranzakció-, arrayUnion/increment- és orderBy-szemantika
// ellen bizonyítunk.

import { test, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

import { redeemQrCore, qrMappingDocId } from '../../functions/lib/redeem-core.js';

const PROJECT = 'demo-redeem-core';
const uid = 'user-1';
let db;

before(() => {
  initializeApp({ projectId: PROJECT });
  db = getFirestore();
});

beforeEach(async () => {
  // Az emulátor REST végpontja az egész projekt adatait törli.
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  await fetch(
    `http://${host}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`,
    { method: 'DELETE' },
  );
});

function redeem(code, location) {
  return redeemQrCore({ db, FieldValue, uid, code, location });
}

test('állomás-jóváírás valós tranzakcióval: pont, lista, leaderboard', async () => {
  await db.doc(`user_progress/${uid}`).set({
    name: 'Teszt Elek',
    totalPoints: 5,
    completedStations: ['st0'],
    completedEvents: [],
    completedTripIds: [],
  });
  await db.doc('stations/st1').set({ name: 'Kinizsi vár', points: 25 });
  await db.doc(`qr_codes/${qrMappingDocId('VAR-001')}`).set({
    kind: 'station',
    targetId: 'st1',
  });

  const result = await redeem('VAR-001');

  assert.equal(result.updatedPoints, 30);
  const progress = (await db.doc(`user_progress/${uid}`).get()).data();
  assert.equal(progress.totalPoints, 30);
  assert.deepEqual(progress.completedStations, ['st0', 'st1']);

  const lb = (await db.doc(`public_leaderboard/${uid}`).get()).data();
  assert.equal(lb.points, 30);
  assert.equal(lb.displayName, 'Teszt Elek');
});

test('ismételt beolvasás valós Firestore-on sem duplázódik', async () => {
  await db.doc(`user_progress/${uid}`).set({
    totalPoints: 25,
    completedStations: ['st1'],
    completedEvents: [],
  });
  await db.doc('stations/st1').set({ name: 'Vár', qrCode: 'VAR-001', points: 25 });

  const result = await redeem('VAR-001');

  assert.equal(result.alreadyDone, true);
  const progress = (await db.doc(`user_progress/${uid}`).get()).data();
  assert.equal(progress.totalPoints, 25);
});

test('párhuzamos jóváírások: N konkurens hívásból pontosan egy ír', async () => {
  await db.doc(`user_progress/${uid}`).set({
    totalPoints: 0,
    completedStations: [],
    completedEvents: [],
  });
  await db.doc('stations/st1').set({ name: 'Vár', qrCode: 'VAR-001', points: 25 });

  const results = await Promise.all([
    redeem('VAR-001'),
    redeem('VAR-001'),
    redeem('VAR-001'),
    redeem('VAR-001'),
  ]);

  const progress = (await db.doc(`user_progress/${uid}`).get()).data();
  assert.equal(progress.totalPoints, 25, 'a pont nem duplázódhat');
  assert.deepEqual(progress.completedStations, ['st1']);
  const awarded = results.filter((r) => !r.alreadyDone);
  assert.equal(awarded.length, 1, 'pontosan egy hívás írhat jóvá');
});

test('esemény + event_count jutalom + túra-teljesítés valós lekérdezésekkel', async () => {
  await db.doc(`user_progress/${uid}`).set({
    totalPoints: 10,
    completedStations: ['stA'],
    completedEvents: [],
    completedTripIds: [],
  });
  await db.doc('stations/stA').set({ name: 'A', tripId: 'trip1', points: 10 });
  await db.doc('stations/stB').set({ name: 'B', qrCode: 'STB', tripId: 'trip1', points: 10 });
  await db.doc('achievements/local_legend').set({
    name: 'Helyi legenda',
    conditionType: 'trip_complete',
    conditionValue: 1,
    unlockedCount: 0,
  });

  const result = await redeem('STB');

  const progress = (await db.doc(`user_progress/${uid}`).get()).data();
  assert.deepEqual(progress.completedTripIds, ['trip1']);
  assert.equal(result.newAchievements[0].id, 'local_legend');
  const ach = (await db.doc('achievements/local_legend').get()).data();
  assert.equal(ach.unlockedCount, 1);
});

test('top_n valós orderBy-jal: a friss pontszám top 2-be kerül', async () => {
  await db.doc(`user_progress/${uid}`).set({
    totalPoints: 0,
    completedStations: [],
    completedEvents: [],
  });
  await db.doc('stations/st1').set({ name: 'Vár', qrCode: 'VAR-001', points: 50 });
  await db.doc('public_leaderboard/masik-1').set({ displayName: 'A', points: 100 });
  await db.doc('public_leaderboard/masik-2').set({ displayName: 'B', points: 30 });
  await db.doc('achievements/podium').set({
    name: 'Dobogós',
    conditionType: 'top_n',
    conditionValue: 2,
  });

  const result = await redeem('VAR-001');

  assert.equal(result.newAchievements.length, 1);
  assert.equal(result.newAchievements[0].id, 'podium');
});

test('helyszín-ellenőrzés valós Firestore-on: távoli pozíció elutasítva, közeli jóváír', async () => {
  await db.doc(`user_progress/${uid}`).set({
    totalPoints: 0,
    completedStations: [],
    completedEvents: [],
  });
  await db.doc('stations/st1').set({
    name: 'Kinizsi vár',
    qrCode: 'VAR-001',
    points: 25,
    latitude: 47.06,
    longitude: 17.715,
  });

  const rejected = await redeem('VAR-001', { lat: 47.2, lng: 17.9 });
  assert.equal(rejected.rejected, 'out_of_range');
  assert.equal((await db.doc(`user_progress/${uid}`).get()).data().totalPoints, 0);

  const ok = await redeem('VAR-001', { lat: 47.0601, lng: 17.7151 });
  assert.equal(ok.updatedPoints, 25);
  assert.equal((await db.doc(`user_progress/${uid}`).get()).data().totalPoints, 25);
});
