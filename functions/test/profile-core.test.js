import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import {
  renameUserCore,
  normalizeDisplayName,
  passwordFromName,
  NameTakenError,
  InvalidNameError,
} from '../lib/profile-core.js';
import { FakeFirestore, FakeFieldValue } from './fake-firestore.js';

const uid = 'user-1';
let db;

const rename = (name, updatePassword) =>
  renameUserCore({ db, FieldValue: FakeFieldValue, uid, name, updatePassword });

beforeEach(() => {
  db = new FakeFirestore();
  db.seed('usernames/teszt elek', { uid, displayName: 'Teszt Elek', normalized: 'teszt elek' });
  db.seed(`users/${uid}`, { name: 'Teszt Elek', displayName: 'Teszt Elek', role: 'user' });
  db.seed(`user_progress/${uid}`, { name: 'Teszt Elek', totalPoints: 30 });
  db.seed(`public_leaderboard/${uid}`, { displayName: 'Teszt Elek', points: 30 });
  db.seed(`leaderboards/nagyvazsony/entries/${uid}`, { uid, displayName: 'Teszt Elek', points: 30 });
  db.seed('leaderboards/nagyvazsony/entries/masik', { uid: 'masik', displayName: 'Más Valaki', points: 5 });
});

test('a név mindenhol frissül, a régi foglalás felszabadul', async () => {
  const result = await rename('  Kinizsi   Pál ');

  assert.equal(result.displayName, 'Kinizsi Pál');
  assert.equal(db.read('usernames/teszt elek'), undefined);
  assert.equal(db.read('usernames/kinizsi pál').uid, uid);
  assert.equal(db.read(`users/${uid}`).displayName, 'Kinizsi Pál');
  assert.equal(db.read(`users/${uid}`).role, 'user', 'a szerepkör érintetlen');
  assert.equal(db.read(`user_progress/${uid}`).name, 'Kinizsi Pál');
  assert.equal(db.read(`user_progress/${uid}`).totalPoints, 30, 'a pont érintetlen');
  assert.equal(db.read(`public_leaderboard/${uid}`).displayName, 'Kinizsi Pál');
  assert.equal(db.read(`leaderboards/nagyvazsony/entries/${uid}`).displayName, 'Kinizsi Pál');
  assert.equal(db.read('leaderboards/nagyvazsony/entries/masik').displayName, 'Más Valaki');
});

test('más által foglalt név elutasítva, semmi nem változik', async () => {
  db.seed('usernames/más valaki', { uid: 'masik', displayName: 'Más Valaki' });
  await assert.rejects(rename('Más   valaki'), NameTakenError);
  assert.equal(db.read(`users/${uid}`).displayName, 'Teszt Elek');
  assert.ok(db.read('usernames/teszt elek'));
});

test('a saját név kis-nagybetűs változata megengedett', async () => {
  const result = await rename('TESZT elek');
  assert.equal(result.displayName, 'TESZT elek');
  assert.equal(db.read('usernames/teszt elek').uid, uid);
});

test('túl rövid, túl hosszú vagy „/”-t tartalmazó név elutasítva', async () => {
  await assert.rejects(rename(' a '), InvalidNameError);
  await assert.rejects(rename('x'.repeat(41)), InvalidNameError);
  await assert.rejects(rename('a/b'), InvalidNameError);
});

test('e-mailhez kötött fióknál a visszaállítási jelszó is frissül', async () => {
  let password;
  await rename('Kinizsi Pál', async (p) => { password = p; });
  assert.equal(password, 'nvkey:kinizsi pál');
  assert.equal(passwordFromName('  Kinizsi  PÁL '), 'nvkey:kinizsi pál');
  assert.equal(normalizeDisplayName(' A  B '), 'a b');
});
