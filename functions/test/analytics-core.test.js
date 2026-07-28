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
