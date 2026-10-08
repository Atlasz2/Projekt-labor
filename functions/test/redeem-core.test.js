import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import {
  redeemQrCore,
  reconcileAchievementsCore,
  qrMappingDocId,
  haversineMeters,
  checkLocation,
  DEFAULT_LOCATION_RADIUS_M,
} from '../lib/redeem-core.js';
import { FakeFirestore, FakeFieldValue } from './fake-firestore.js';

const uid = 'user-1';
let db;

function redeem(code, location, projectId) {
  return redeemQrCore({
    db,
    FieldValue: FakeFieldValue,
    uid,
    code,
    location,
    projectId,
  });
}

beforeEach(() => {
  db = new FakeFirestore();
  db.seed(`user_progress/${uid}`, {
    name: 'Teszt Elek',
    totalPoints: 0,
    completedStations: [],
    completedEvents: [],
    completedTripIds: [],
  });
});

test('ismeretlen kódra found:false-t ad vissza (nem dob)', async () => {
  const result = await redeem('NEMLETEZIK');
  assert.deepEqual(result, { found: false });
});

test('állomás jóváírása a qr_codes leképezésen keresztül', async () => {
  db.seed('stations/st1', { name: 'Kinizsi vár', points: 25 });
  db.seed(`qr_codes/${qrMappingDocId('VAR-001')}`, {
    kind: 'station',
    targetId: 'st1',
  });

  const result = await redeem('VAR-001');

  assert.equal(result.found, true);
  assert.equal(result.kind, 'station');
  assert.equal(result.alreadyDone, false);
  assert.equal(result.updatedPoints, 25);
  assert.equal(result.completedStationsCount, 1);

  const progress = db.read(`user_progress/${uid}`);
  assert.equal(progress.totalPoints, 25);
  assert.deepEqual(progress.completedStations, ['st1']);

  const lb = db.read(`public_leaderboard/${uid}`);
  assert.equal(lb.points, 25);
  assert.equal(lb.displayName, 'Teszt Elek');
});

test('legacy fallback: qrCode mező alapján is megtalálja az állomást', async () => {
  db.seed('stations/st1', { name: 'Malom', qrCode: 'MALOM-1', points: 10 });

  const result = await redeem('MALOM-1');

  assert.equal(result.found, true);
  assert.equal(result.targetId, 'st1');
  assert.equal(result.updatedPoints, 10);
});

test('legacy fallback: doc-id alapján is megtalálja a célt', async () => {
  db.seed('stations/st-direct', { name: 'Templom', points: 5 });

  const result = await redeem('st-direct');

  assert.equal(result.found, true);
  assert.equal(result.targetId, 'st-direct');
  assert.equal(result.updatedPoints, 5);
});

test("'/'-t tartalmazó kód nem okoz hibát, found:false", async () => {
  const result = await redeem('https://example.com/x');
  assert.deepEqual(result, { found: false });
});

test('esemény jóváírása a completedEvents listát bővíti', async () => {
  db.seed(`user_progress/${uid}`, {
    name: 'Teszt Elek',
    totalPoints: 5,
    completedStations: ['st0'],
    completedEvents: [],
    completedTripIds: [],
  });
  db.seed('events/ev1', { name: 'Várjátékok', points: 15 });
  db.seed(`qr_codes/${qrMappingDocId('EVENT-2026')}`, {
    kind: 'event',
    targetId: 'ev1',
  });

  const result = await redeem('EVENT-2026');

  assert.equal(result.kind, 'event');
  assert.equal(result.updatedPoints, 20);
  assert.equal(result.completedEventsCount, 1);
  assert.equal(result.completedStationsCount, 1);

  const progress = db.read(`user_progress/${uid}`);
  assert.deepEqual(progress.completedEvents, ['ev1']);
  assert.deepEqual(progress.completedStations, ['st0']);
  assert.equal(progress.totalPoints, 20);
});

test('ismételt beolvasás alreadyDone, a pont nem változik', async () => {
  db.seed(`user_progress/${uid}`, {
    totalPoints: 25,
    completedStations: ['st1'],
    completedEvents: [],
  });
  db.seed('stations/st1', { name: 'Kinizsi vár', qrCode: 'VAR-001', points: 25 });

  const result = await redeem('VAR-001');

  assert.equal(result.alreadyDone, true);
  assert.equal(result.updatedPoints, 25);
  assert.equal(db.read(`user_progress/${uid}`).totalPoints, 25);
  // Ismételt beolvasásnál a leaderboard-ot sem írjuk.
  assert.equal(db.read(`public_leaderboard/${uid}`), undefined);
});

test('hiányzó user_progress doksit nullázott alapokkal hozza létre', async () => {
  db = new FakeFirestore(); // nincs seed-elt progress
  db.seed('stations/st1', { name: 'Kinizsi vár', qrCode: 'VAR-001', points: 25 });
  db.seed('users/user-1', { displayName: 'Új Ember' });

  const result = await redeem('VAR-001');

  assert.equal(result.updatedPoints, 25);
  const progress = db.read(`user_progress/${uid}`);
  assert.equal(progress.totalPoints, 25);
  assert.deepEqual(progress.completedEvents, []);
  assert.deepEqual(progress.completedTripIds, []);

  // displayName a users doksiból jön, ha a progress-ben nincs név.
  assert.equal(db.read(`public_leaderboard/${uid}`).displayName, 'Új Ember');
});

test('0 pontos cél 0 pontot ér (nem esik vissza 10-re)', async () => {
  db.seed('stations/st1', { name: 'Ingyenes', qrCode: 'FREE', points: 0 });

  const result = await redeem('FREE');

  assert.equal(result.updatedPoints, 0);
  assert.equal(db.read(`user_progress/${uid}`).totalPoints, 0);
});

test('event_count jutalom feloldódik, unlockedCount nő, banner beáll', async () => {
  db.seed('events/ev1', { name: 'Várjátékok', qrCode: 'EVENT-2026', points: 15 });
  db.seed('achievements/event_hunter', {
    name: 'Eseményvadász',
    description: 'Vegyél részt 1 eseményen',
    conditionType: 'event_count',
    conditionValue: 1,
    unlockedCount: 3,
  });

  const result = await redeem('EVENT-2026');

  assert.equal(result.newAchievements.length, 1);
  assert.equal(result.newAchievements[0].id, 'event_hunter');

  assert.ok(db.read(`user_progress/${uid}/unlocked_achievements/event_hunter`));
  assert.equal(db.read('achievements/event_hunter').unlockedCount, 4);
  assert.equal(
    db.read(`user_progress/${uid}`).pendingAchievementBanner.title,
    'Eseményvadász',
  );
});

test('már feloldott jutalom nem oldódik fel újra', async () => {
  db.seed('events/ev1', { name: 'Várjátékok', qrCode: 'EVENT-2026', points: 15 });
  db.seed('achievements/event_hunter', {
    name: 'Eseményvadász',
    conditionType: 'event_count',
    conditionValue: 1,
    unlockedCount: 3,
  });
  db.seed(`user_progress/${uid}/unlocked_achievements/event_hunter`, {
    unlockedAt: new Date(),
  });

  const result = await redeem('EVENT-2026');

  assert.equal(result.newAchievements.length, 0);
  assert.equal(db.read('achievements/event_hunter').unlockedCount, 3);
});

test('túra-teljesítés: az utolsó állomással a completedTripIds bővül és a trip_complete jutalom feloldódik', async () => {
  db.seed(`user_progress/${uid}`, {
    name: 'Teszt Elek',
    totalPoints: 10,
    completedStations: ['st1'],
    completedEvents: [],
    completedTripIds: [],
  });
  db.seed('trips/trip1', { name: 'Vár-túra' });
  db.seed('stations/st1', { name: 'Első', tripId: 'trip1', points: 10 });
  db.seed('stations/st2', { name: 'Második', qrCode: 'ST2', tripId: 'trip1', points: 10 });
  db.seed('stations/other', { name: 'Másik túráé', tripId: 'trip2', points: 10 });
  db.seed('achievements/local_legend', {
    name: 'Helyi legenda',
    conditionType: 'trip_complete',
    conditionValue: 1,
  });

  const result = await redeem('ST2');

  assert.deepEqual(db.read(`user_progress/${uid}`).completedTripIds, ['trip1']);
  assert.equal(result.newAchievements.length, 1);
  assert.equal(result.newAchievements[0].id, 'local_legend');
});

test('túra-teljesítés: hiányzó állomásnál nem íródik completedTripIds', async () => {
  db.seed('stations/st1', { name: 'Első', qrCode: 'ST1', tripId: 'trip1', points: 10 });
  db.seed('stations/st2', { name: 'Második', tripId: 'trip1', points: 10 });

  await redeem('ST1');

  assert.deepEqual(db.read(`user_progress/${uid}`).completedTripIds ?? [], []);
});

test('túra-teljesítés: egy állomás két túrának is megállója (tripIds) – mindkét túra befejeződhet', async () => {
  db.seed(`user_progress/${uid}`, {
    name: 'Teszt Elek',
    totalPoints: 10,
    completedStations: ['rovid1', 'hosszu1'],
    completedEvents: [],
    completedTripIds: [],
  });
  // A "kozos" állomás mindkét túrának (rövid és hosszú) is megállója.
  db.seed('trips/rovid', { name: 'Rövid' });
  db.seed('trips/hosszu', { name: 'Hosszú' });
  db.seed('stations/rovid1', { name: 'Rövid-1', tripIds: ['rovid'] });
  db.seed('stations/kozos', {
    name: 'Közös',
    qrCode: 'KOZOS',
    tripIds: ['rovid', 'hosszu'],
  });
  db.seed('stations/hosszu1', { name: 'Hosszú-1', tripIds: ['hosszu'] });
  db.seed('stations/hosszu2', { name: 'Hosszú-2', tripIds: ['hosszu'] });

  const result = await redeem('KOZOS');

  // A rövid túra (rovid1 + kozos) ezzel kész, a hosszú (hosszu1+hosszu2+kozos) még nem.
  assert.deepEqual(db.read(`user_progress/${uid}`).completedTripIds, ['rovid']);
  assert.equal(result.found, true);
});

test('túra-teljesítés: a közös állomás mindkét túrát lezárhatja, ha épp az utolsó mindkettőn', async () => {
  db.seed(`user_progress/${uid}`, {
    name: 'Teszt Elek',
    totalPoints: 10,
    completedStations: ['rovid1', 'hosszu1', 'hosszu2'],
    completedEvents: [],
    completedTripIds: [],
  });
  db.seed('trips/rovid', { name: 'Rövid' });
  db.seed('trips/hosszu', { name: 'Hosszú' });
  db.seed('stations/rovid1', { name: 'Rövid-1', tripIds: ['rovid'] });
  db.seed('stations/kozos', {
    name: 'Közös',
    qrCode: 'KOZOS2',
    tripIds: ['rovid', 'hosszu'],
  });
  db.seed('stations/hosszu1', { name: 'Hosszú-1', tripIds: ['hosszu'] });
  db.seed('stations/hosszu2', { name: 'Hosszú-2', tripIds: ['hosszu'] });

  await redeem('KOZOS2');

  const tripIds = db.read(`user_progress/${uid}`).completedTripIds;
  assert.equal(tripIds.length, 2);
  assert.ok(tripIds.includes('rovid'));
  assert.ok(tripIds.includes('hosszu'));
});

test('top_n jutalom: a friss pontszámmal top 2-be kerülve feloldódik', async () => {
  db.seed('stations/st1', { name: 'Kinizsi vár', qrCode: 'VAR-001', points: 50 });
  // A top_n a település SAJÁT ranglistáján értékelődik ki.
  db.seed('leaderboards/nagyvazsony/entries/masik-1', {
    displayName: 'Éllovas',
    points: 100,
  });
  db.seed('leaderboards/nagyvazsony/entries/masik-2', {
    displayName: 'Második',
    points: 30,
  });
  db.seed('achievements/podium', {
    name: 'Dobogós',
    conditionType: 'top_n',
    conditionValue: 2,
  });

  const result = await redeem('VAR-001');

  // 50 ponttal a 100 mögött, a 30 előtt: 2. hely -> top 2 teljesül.
  assert.equal(result.newAchievements.length, 1);
  assert.equal(result.newAchievements[0].id, 'podium');
});

test('top_n jutalom: rangon kívül nem oldódik fel', async () => {
  db.seed('stations/st1', { name: 'Kinizsi vár', qrCode: 'VAR-001', points: 5 });
  db.seed('leaderboards/nagyvazsony/entries/masik-1', { displayName: 'A', points: 100 });
  db.seed('leaderboards/nagyvazsony/entries/masik-2', { displayName: 'B', points: 90 });
  db.seed('achievements/podium', {
    name: 'Dobogós',
    conditionType: 'top_n',
    conditionValue: 2,
  });

  const result = await redeem('VAR-001');

  assert.equal(result.newAchievements.length, 0);
});

test('árva qr_codes leképezés (törölt cél) found:false-ra fut', async () => {
  db.seed(`qr_codes/${qrMappingDocId('ARVA')}`, {
    kind: 'station',
    targetId: 'torolt-allomas',
  });

  const result = await redeem('ARVA');
  assert.deepEqual(result, { found: false });
});

// ── Helyszín-ellenőrzés (Haversine) ────────────────────────────────────────

test('haversineMeters: ismert távolság kb. helyes (Nagyvázsony ~1 km)', () => {
  // Két pont, ~0.01° hosszúságkülönbség ~47° szélességen ≈ 758 m.
  const d = haversineMeters(47.06, 17.715, 47.06, 17.725);
  assert.ok(d > 700 && d < 800, `váratlan táv: ${d}`);
  assert.equal(haversineMeters(47.06, 17.715, 47.06, 17.715), 0);
});

test('checkLocation: koordináta nélküli célnál nincs ellenőrzés (null)', () => {
  assert.equal(checkLocation({ name: 'Esemény' }, { lat: 0, lng: 0 }), null);
  assert.equal(checkLocation({ latitude: 0, longitude: 0 }, { lat: 47, lng: 17 }), null);
});

test('checkLocation: pozíció nélkül átengedi (null)', () => {
  const station = { latitude: 47.06, longitude: 17.715 };
  assert.equal(checkLocation(station, null), null);
  assert.equal(checkLocation(station, { lat: 'x', lng: 'y' }), null);
});

test('checkLocation: közel -> null, távol -> {distance, threshold}', () => {
  const station = { latitude: 47.06, longitude: 17.715 };
  assert.equal(checkLocation(station, { lat: 47.0601, lng: 17.7151 }), null);

  const far = checkLocation(station, { lat: 47.08, lng: 17.75 });
  assert.ok(far);
  assert.equal(far.threshold, DEFAULT_LOCATION_RADIUS_M);
  assert.ok(far.distance > DEFAULT_LOCATION_RADIUS_M);
});

test('checkLocation: az állomás saját radius mezője felülírja az alapértelmezettet', () => {
  const station = { latitude: 47.06, longitude: 17.715, radius: 1000 };
  // ~758 m — az alap 150 m-en kívül, de az 1000 m-es radiuson belül.
  assert.equal(checkLocation(station, { lat: 47.06, lng: 17.725 }), null);
});

test('redeem: távoli pozíció -> out_of_range, a pont NEM íródik jóvá', async () => {
  db.seed('stations/st1', {
    name: 'Kinizsi vár',
    qrCode: 'VAR-001',
    points: 25,
    latitude: 47.06,
    longitude: 17.715,
  });

  const result = await redeem('VAR-001', { lat: 47.2, lng: 17.9 });

  assert.equal(result.found, true);
  assert.equal(result.rejected, 'out_of_range');
  assert.ok(result.distance > result.threshold);
  assert.equal(result.target.name, 'Kinizsi vár');

  const progress = db.read(`user_progress/${uid}`);
  assert.equal(progress.totalPoints, 0, 'távolról nem járhat pont');
  assert.deepEqual(progress.completedStations, []);
});

test('redeem: helyszínen lévő pozícióval a jóváírás megtörténik', async () => {
  db.seed('stations/st1', {
    name: 'Kinizsi vár',
    qrCode: 'VAR-001',
    points: 25,
    latitude: 47.06,
    longitude: 17.715,
  });

  const result = await redeem('VAR-001', { lat: 47.0601, lng: 17.7151 });

  assert.equal(result.found, true);
  assert.equal(result.rejected, undefined);
  assert.equal(result.updatedPoints, 25);
  assert.equal(db.read(`user_progress/${uid}`).totalPoints, 25);
});

test('redeem: pozíció nélkül a helyhez kötött állomás alapból location_required', async () => {
  db.seed('stations/st1', {
    name: 'Kinizsi vár',
    qrCode: 'VAR-001',
    points: 25,
    latitude: 47.06,
    longitude: 17.715,
  });

  const result = await redeem('VAR-001'); // nincs location (kikapcsolt GPS)
  assert.equal(result.rejected, 'location_required');
  assert.equal(db.read(`user_progress/${uid}`).totalPoints, 0);
});

test('redeem: a pozíció nélküli beváltást kifejezetten engedő állomás jóváíródik', async () => {
  db.seed('stations/st1', {
    name: 'Akadálymentes állomás',
    qrCode: 'VAR-001',
    points: 25,
    latitude: 47.06,
    longitude: 17.715,
    requireLocation: false,
  });

  const result = await redeem('VAR-001'); // nincs location
  assert.equal(result.updatedPoints, 25);
});

test('redeem: másik település QR-kódja -> wrong_project, nincs jóváírás', async () => {
  db.seed('stations/st-masik', {
    name: 'Idegen állomás',
    qrCode: 'MASIK-001',
    points: 25,
    projectId: 'masik-telepules',
  });

  const result = await redeem('MASIK-001', null, 'nagyvazsony');

  assert.equal(result.found, true);
  assert.equal(result.rejected, 'wrong_project');
  assert.equal(result.targetProjectId, 'masik-telepules');
  const progress = db.read(`user_progress/${uid}`);
  assert.equal(progress.totalPoints, 0);
  assert.deepEqual(progress.completedStations, []);
});

test('redeem: a saját település kódja jóváíródik', async () => {
  db.seed('stations/st1', {
    name: 'Kinizsi vár',
    qrCode: 'VAR-001',
    points: 25,
    projectId: 'nagyvazsony',
  });

  const result = await redeem('VAR-001', null, 'nagyvazsony');

  assert.equal(result.found, true);
  assert.equal(result.rejected, undefined);
  assert.equal(db.read(`user_progress/${uid}`).totalPoints, 25);
});

test('redeem: projectId nélküli állomás az alapértelmezett településhez tartozik', async () => {
  db.seed('stations/st-regi', { name: 'Régi', qrCode: 'REGI-001', points: 10 });

  const result = await redeem('REGI-001', null, 'nagyvazsony');

  assert.equal(result.rejected, undefined);
  assert.equal(db.read(`user_progress/${uid}`).totalPoints, 10);
});

test('redeem: régi kliens (nincs projectId) esetén nincs település-szűrés', async () => {
  db.seed('stations/st-masik', {
    name: 'Idegen',
    qrCode: 'MASIK-001',
    points: 15,
    projectId: 'masik-telepules',
  });

  const result = await redeem('MASIK-001');

  assert.equal(result.rejected, undefined);
  assert.equal(db.read(`user_progress/${uid}`).totalPoints, 15);
});

test('ranglista: a település saját bejegyzése jön létre a szerzett ponttal', async () => {
  db.seed('stations/st1', {
    name: 'Kinizsi vár',
    qrCode: 'VAR-001',
    points: 25,
    projectId: 'nagyvazsony',
  });

  await redeem('VAR-001', null, 'nagyvazsony');

  const entry = db.read(`leaderboards/nagyvazsony/entries/${uid}`);
  assert.equal(entry.points, 25);
  assert.equal(entry.completedStationsCount, 1);
  assert.equal(entry.projectId, 'nagyvazsony');
  // A régi globális ranglista is frissül (átmeneti kettős írás).
  assert.equal(db.read(`public_leaderboard/${uid}`).points, 25);
});

test('jutalom: másik település jutalma nem oldódik fel a szerveres úton', async () => {
  db.seed('stations/st1', { name: 'Kinizsi vár', qrCode: 'VAR-001', points: 10 });
  db.seed('achievements/sajat', { name: 'Első', conditionType: 'station_count', conditionValue: 1 });
  db.seed('achievements/idegen', {
    name: 'Más falu',
    conditionType: 'station_count',
    conditionValue: 1,
    projectId: 'mencshely',
  });

  const result = await redeem('VAR-001');

  assert.deepEqual(result.newAchievements.map((a) => a.id), ['sajat']);
  assert.equal(db.read(`user_progress/${uid}/unlocked_achievements/idegen`), undefined);
});

function reconcile(projectId) {
  return reconcileAchievementsCore({ db, FieldValue: FakeFieldValue, uid, projectId });
}

test('reconcile: utólag létrehozott, már teljesült jutalom feloldódik', async () => {
  db.seed(`user_progress/${uid}`, {
    name: 'Teszt Elek',
    totalPoints: 40,
    completedStations: ['st1', 'st2'],
    completedEvents: [],
    completedTripIds: [],
  });
  db.seed('achievements/ket-allomas', { name: 'Két állomás', conditionType: 'station_count', conditionValue: 2 });
  db.seed('achievements/sok-pont', { name: 'Sok pont', conditionType: 'points_threshold', conditionValue: 100 });

  const { newAchievements } = await reconcile('nagyvazsony');

  assert.deepEqual(newAchievements.map((a) => a.id), ['ket-allomas']);
  assert.ok(db.read(`user_progress/${uid}/unlocked_achievements/ket-allomas`));
  assert.equal(db.read('achievements/ket-allomas').unlockedCount, 1);
  assert.equal(db.read(`user_progress/${uid}`).pendingAchievementBanner.title, 'Két állomás');
});

test('reconcile: a már feloldott jutalom nem oldódik fel újra', async () => {
  db.seed(`user_progress/${uid}`, { totalPoints: 10, completedStations: ['st1'] });
  db.seed('achievements/elso', { name: 'Első', conditionType: 'station_count', conditionValue: 1 });
  db.seed(`user_progress/${uid}/unlocked_achievements/elso`, { unlockedAt: 1 });

  const { newAchievements } = await reconcile('nagyvazsony');

  assert.equal(newAchievements.length, 0);
  assert.equal(db.read('achievements/elso').unlockedCount, undefined);
});

test('reconcile: haladás-dokumentum nélkül üres eredmény, írás nélkül', async () => {
  db = new FakeFirestore();
  db.seed('achievements/elso', { name: 'Első', conditionType: 'station_count', conditionValue: 0 });

  const { newAchievements } = await reconcile('');

  assert.deepEqual(newAchievements, []);
  assert.equal(db.read(`user_progress/${uid}/unlocked_achievements/elso`), undefined);
});

// ── Indulás előtti megerősítések ───────────────────────────────────────────

test('túra-teljesítés: törölt túrára mutató hivatkozás nem teljesül', async () => {
  db.seed(`user_progress/${uid}`, {
    name: 'Teszt Elek',
    totalPoints: 0,
    completedStations: [],
    completedEvents: [],
    completedTripIds: [],
  });
  // A 'torolt' túra dokumentuma nincs meg, az állomás mégis hivatkozik rá.
  db.seed('stations/egyedul', { name: 'Egyetlen', qrCode: 'EGY', tripIds: ['torolt'] });

  await redeem('EGY');

  assert.deepEqual(db.read(`user_progress/${uid}`).completedTripIds, []);
});

test('túra-teljesítés: más település túrája nem teljesül ezen az állomáson', async () => {
  db.seed('trips/idegen', { name: 'Idegen', projectId: 'tapolca' });
  db.seed('stations/st1', { name: 'Egy', qrCode: 'ST1', tripIds: ['idegen'] });

  await redeem('ST1');

  assert.deepEqual(db.read(`user_progress/${uid}`).completedTripIds, []);
});

test('önjavítás: ismételt beolvasás pótolja a korábban elmaradt túra-teljesítést', async () => {
  // Az állomás már jóvá van írva, de a túra-teljesítés egy megszakadt kérés
  // miatt nem íródott be.
  db.seed(`user_progress/${uid}`, {
    name: 'Teszt Elek',
    totalPoints: 20,
    completedStations: ['a', 'b'],
    completedEvents: [],
    completedTripIds: [],
  });
  db.seed('trips/t1', { name: 'Túra' });
  db.seed('stations/a', { name: 'A', tripIds: ['t1'] });
  db.seed('stations/b', { name: 'B', qrCode: 'B', tripIds: ['t1'] });

  const result = await redeem('B');

  assert.equal(result.alreadyDone, true);
  assert.equal(db.read(`user_progress/${uid}`).totalPoints, 20, 'pont nem változik');
  assert.deepEqual(db.read(`user_progress/${uid}`).completedTripIds, ['t1']);
});

test('ranglista: ismételt beolvasás nem növeli újra a települési pontot', async () => {
  db.seed('stations/st1', { name: 'Vár', qrCode: 'VAR', points: 30 });

  await redeem('VAR');
  await redeem('VAR');

  const entry = db.read(`leaderboards/nagyvazsony/entries/${uid}`);
  assert.equal(entry.points, 30);
  assert.equal(entry.completedStationsCount, 1);
  assert.equal(entry.displayName, 'Teszt Elek');
  assert.equal(db.read(`public_leaderboard/${uid}`).points, 30);
});

test('ranglista: profil nélküli haladásnál a users dokumentum neve kerül ki', async () => {
  db.seed(`user_progress/${uid}`, {
    totalPoints: 0,
    completedStations: [],
    completedEvents: [],
    completedTripIds: [],
  });
  db.seed(`users/${uid}`, { displayName: 'Kinizsi Pál' });
  db.seed('stations/st1', { name: 'Vár', qrCode: 'VAR', points: 5 });

  await redeem('VAR');

  assert.equal(db.read(`leaderboards/nagyvazsony/entries/${uid}`).displayName, 'Kinizsi Pál');
});

test('kötelező helymeghatározás: pozíció nélkül location_required, nincs pont', async () => {
  db.seed('stations/st1', {
    name: 'Kilátó',
    qrCode: 'KILATO',
    points: 10,
    requireLocation: true,
    location: { latitude: 47.06, longitude: 17.715 },
  });

  const result = await redeem('KILATO', null);

  assert.equal(result.rejected, 'location_required');
  assert.equal(db.read(`user_progress/${uid}`).totalPoints, 0);
  assert.equal(db.read(`leaderboards/nagyvazsony/entries/${uid}`), undefined);
});

test('kötelező helymeghatározás: helyszíni pozícióval jóváíródik', async () => {
  db.seed('stations/st1', {
    name: 'Kilátó',
    qrCode: 'KILATO',
    points: 10,
    requireLocation: true,
    location: { latitude: 47.06, longitude: 17.715 },
  });

  const result = await redeem('KILATO', { lat: 47.0601, lng: 17.7151 });

  assert.equal(result.rejected, undefined);
  assert.equal(db.read(`user_progress/${uid}`).totalPoints, 10);
});

test('QR-migráció után: a nyilvános mezőkön át nem oldható fel kód (T7)', async () => {
  db.seed('stations/st1', { name: 'Vár', qrCode: 'VAR-001', points: 10 });
  db.seed('stations/st2', { name: 'Kút', points: 10 });

  const byField = await redeemQrCore({
    db, FieldValue: FakeFieldValue, uid, code: 'VAR-001', legacyFallback: false,
  });
  const byId = await redeemQrCore({
    db, FieldValue: FakeFieldValue, uid, code: 'st2', legacyFallback: false,
  });

  assert.deepEqual(byField, { found: false });
  assert.deepEqual(byId, { found: false });
  assert.equal(db.read(`user_progress/${uid}`).totalPoints, 0);
});

test('QR-migráció után: a privát leképezésen át a jóváírás működik', async () => {
  db.seed('stations/st1', { name: 'Vár', points: 10 });
  db.seed(`qr_codes/${qrMappingDocId('NV-8K2M4Q7X9C3T5W1R')}`, {
    kind: 'station',
    targetId: 'st1',
  });

  const result = await redeemQrCore({
    db, FieldValue: FakeFieldValue, uid, code: 'NV-8K2M4Q7X9C3T5W1R', legacyFallback: false,
  });

  assert.equal(result.found, true);
  assert.equal(db.read(`user_progress/${uid}`).totalPoints, 10);
});

test('QR: más település célját feloldó (eltérített) leképezés érvénytelen', async () => {
  db.seed('stations/st1', { name: 'Mencshelyi', projectId: 'mencshely', points: 10 });
  db.seed(`qr_codes/${qrMappingDocId('NV-ELTERITETT-KOD1')}`, {
    kind: 'station',
    targetId: 'st1',
    projectId: 'nagyvazsony',
  });

  const result = await redeemQrCore({
    db, FieldValue: FakeFieldValue, uid, code: 'NV-ELTERITETT-KOD1', legacyFallback: false,
  });

  assert.deepEqual(result, { found: false });
  assert.equal(db.read(`user_progress/${uid}`).totalPoints, 0);
});
