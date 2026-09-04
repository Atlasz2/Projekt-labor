import { test } from 'node:test';
import assert from 'node:assert/strict';

import { computeTripAnalytics } from '../lib/analytics-core.js';

const trips = [
  { id: 't1', name: 'Vár túra' },
  { id: 't2', name: 'Tó túra' },
];
const stations = [
  { id: 's1', name: 'Vár', tripId: 't1' },
  { id: 's2', name: 'Kápolna', tripId: 't1' },
  { id: 's3', name: 'Tópart', tripId: 't2' },
];

test('üres bemenetre nullázott összegzés, nincs hiba', () => {
  const out = computeTripAnalytics({});
  assert.equal(out.totals.participants, 0);
  assert.equal(out.totals.totalStationCompletions, 0);
  assert.deepEqual(out.trips, []);
  assert.deepEqual(out.stations, []);
});

test('állomás-népszerűség a teljesítések száma szerint csökkenő', () => {
  const progressDocs = [
    { completedStations: ['s1', 's2'] },
    { completedStations: ['s1'] },
    { completedStations: ['s1', 's3'] },
  ];
  const out = computeTripAnalytics({ trips, stations, progressDocs });
  const byId = Object.fromEntries(out.stations.map((s) => [s.id, s]));
  assert.equal(byId.s1.completions, 3);
  assert.equal(byId.s2.completions, 1);
  assert.equal(byId.s3.completions, 1);
  // Legnépszerűbb elöl.
  assert.equal(out.stations[0].id, 's1');
  // A túra neve is feloldva.
  assert.equal(byId.s1.tripName, 'Vár túra');
});

test('tölcsér: résztvevők és befejezők (minden állomás kész)', () => {
  const progressDocs = [
    { completedStations: ['s1', 's2'] }, // t1 befejezve
    { completedStations: ['s1'] }, // t1 résztvevő, nem befejező
    { completedStations: [] }, // nem résztvevő sehol
  ];
  const out = computeTripAnalytics({ trips, stations, progressDocs });
  const t1 = out.trips.find((t) => t.id === 't1');
  assert.equal(t1.stationCount, 2);
  assert.equal(t1.participants, 2);
  assert.equal(t1.finishers, 1);
  assert.equal(t1.completionRate, 0.5);
  assert.equal(t1.avgStationsPerParticipant, 1.5); // (2+1)/2
});

test('completedTripIds is befejezőnek számít, de csak ha résztvevő', () => {
  const progressDocs = [
    // teljesítette az egyik állomást ÉS jelölt a trip -> befejező
    { completedStations: ['s1'], completedTripIds: ['t1'] },
    // csak a tripId van, állomás nincs -> NEM résztvevő, NEM befejező (tölcsér ép marad)
    { completedStations: [], completedTripIds: ['t1'] },
  ];
  const out = computeTripAnalytics({ trips, stations, progressDocs });
  const t1 = out.trips.find((t) => t.id === 't1');
  assert.equal(t1.participants, 1);
  assert.equal(t1.finishers, 1);
  // finishers soha nem több a résztvevőknél.
  assert.ok(t1.finishers <= t1.participants);
});

test('összegzés: résztvevők (≥1 állomás) és összes teljesítés', () => {
  const progressDocs = [
    { completedStations: ['s1', 's2'] },
    { completedStations: ['s3'] },
    { completedStations: [] },
  ];
  const out = computeTripAnalytics({ trips, stations, progressDocs });
  assert.equal(out.totals.participants, 2);
  assert.equal(out.totals.totalStationCompletions, 3);
  assert.equal(out.totals.trips, 2);
  assert.equal(out.totals.stations, 3);
  assert.equal(out.totals.trackedUsers, 3);
});

test('átlagos befejezési idő a befejezők első→utolsó állomás ideje alapján', () => {
  const min = 60000;
  const progressDocs = [
    {
      // t1 befejezve: s1 @0, s2 @+30 perc  -> 30 perc
      completedStations: ['s1', 's2'],
      completedStationsAt: { s1: 0, s2: 30 * min },
    },
    {
      // t1 befejezve: s1 @+10, s2 @+60 perc -> 50 perc
      completedStations: ['s1', 's2'],
      completedStationsAt: { s1: 10 * min, s2: 60 * min },
    },
    {
      // csak s1 -> nem befejező, nem számít az időbe
      completedStations: ['s1'],
      completedStationsAt: { s1: 0 },
    },
  ];
  const out = computeTripAnalytics({ trips, stations, progressDocs });
  const t1 = out.trips.find((t) => t.id === 't1');
  assert.equal(t1.avgCompletionMinutes, 40); // (30 + 50) / 2
  assert.equal(t1.completionTimeSamples, 2);
});

test('nincs időbélyeg -> avgCompletionMinutes null, minta 0', () => {
  const progressDocs = [{ completedStations: ['s1', 's2'] }];
  const out = computeTripAnalytics({ trips, stations, progressDocs });
  const t1 = out.trips.find((t) => t.id === 't1');
  assert.equal(t1.avgCompletionMinutes, null);
  assert.equal(t1.completionTimeSamples, 0);
});

test('hiányos időbélyeg (nem minden állomáshoz) kimarad az átlagból', () => {
  const min = 60000;
  const progressDocs = [
    {
      // befejező, de csak s1-hez van időbélyeg -> nem számítható
      completedStations: ['s1', 's2'],
      completedStationsAt: { s1: 0 },
    },
  ];
  const out = computeTripAnalytics({ trips, stations, progressDocs });
  const t1 = out.trips.find((t) => t.id === 't1');
  assert.equal(t1.avgCompletionMinutes, null);
  assert.equal(t1.completionTimeSamples, 0);
  void min;
});

test('hibás alakú mezők (nem tömb, null) nem dobnak, üresnek számítanak', () => {
  const progressDocs = [
    { completedStations: null },
    { completedStations: 'nem-tömb' },
    { completedStations: { s1: true } }, // objektum, nem tömb
    { completedStations: ['s1'] }, // ez az egyetlen valós résztvevő
    {}, // hiányzó mező
  ];
  const out = computeTripAnalytics({ trips, stations, progressDocs });
  assert.equal(out.totals.participants, 1);
  const byId = Object.fromEntries(out.stations.map((s) => [s.id, s]));
  assert.equal(byId.s1.completions, 1);
});

test('egy állomás két túrának is megállója (tripIds): mindkét túra tölcsérébe beleszámít', () => {
  const sharedTrips = [
    { id: 't1', name: 'Vár túra' },
    { id: 't2', name: 'Tó túra' },
  ];
  const sharedStations = [
    { id: 's1', name: 'Vár', tripIds: ['t1'] },
    // A "Kápolna" mindkét túrának megállója.
    { id: 's2', name: 'Kápolna', tripIds: ['t1', 't2'] },
    { id: 's3', name: 'Tópart', tripIds: ['t2'] },
  ];
  const progressDocs = [
    { completedStations: ['s1', 's2'] }, // t1 befejezve (s1+s2), t2 résztvevő (csak s2)
    { completedStations: ['s2', 's3'] }, // t2 befejezve (s2+s3), t1 résztvevő (csak s2)
  ];
  const out = computeTripAnalytics({
    trips: sharedTrips,
    stations: sharedStations,
    progressDocs,
  });

  const t1 = out.trips.find((t) => t.id === 't1');
  const t2 = out.trips.find((t) => t.id === 't2');
  assert.equal(t1.stationCount, 2);
  assert.equal(t1.participants, 2);
  assert.equal(t1.finishers, 1);
  assert.equal(t2.stationCount, 2);
  assert.equal(t2.participants, 2);
  assert.equal(t2.finishers, 1);

  const s2 = out.stations.find((s) => s.id === 's2');
  assert.deepEqual(s2.tripIds, ['t1', 't2']);
  assert.equal(s2.tripName, 'Vár túra, Tó túra');
  assert.equal(s2.completions, 2);
});

test('túrák részvétel szerint csökkenő sorrendben', () => {
  const progressDocs = [
    { completedStations: ['s1'] },
    { completedStations: ['s2'] },
    { completedStations: ['s3'] },
  ];
  const out = computeTripAnalytics({ trips, stations, progressDocs });
  // t1: 2 résztvevő (s1, s2), t2: 1 résztvevő (s3) -> t1 elöl.
  assert.equal(out.trips[0].id, 't1');
  assert.equal(out.trips[0].participants, 2);
  assert.equal(out.trips[1].participants, 1);
});
