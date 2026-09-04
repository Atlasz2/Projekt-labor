import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  stationTripIds,
  stationBelongsToTrip,
  stationOrderIndexForTrip,
  stationsForTrip,
} from '../lib/station-trips-core.js';

test('stationTripIds: új tripIds tömböt adja vissza, ha van', () => {
  assert.deepEqual(stationTripIds({ tripIds: ['t1', 't2'] }), ['t1', 't2']);
});

test('stationTripIds: duplikátumokat kiszűri', () => {
  assert.deepEqual(stationTripIds({ tripIds: ['t1', 't1', 't2'] }), ['t1', 't2']);
});

test('stationTripIds: visszamenőleg a régi tripId mezőt egyelemű listaként adja', () => {
  assert.deepEqual(stationTripIds({ tripId: 't1' }), ['t1']);
});

test('stationTripIds: se tripIds, se tripId -> üres lista', () => {
  assert.deepEqual(stationTripIds({}), []);
  assert.deepEqual(stationTripIds({ tripIds: [] }), []);
});

test('stationBelongsToTrip: több túrának is megállója lehet', () => {
  const station = { tripIds: ['t1', 't2'] };
  assert.equal(stationBelongsToTrip(station, 't1'), true);
  assert.equal(stationBelongsToTrip(station, 't2'), true);
  assert.equal(stationBelongsToTrip(station, 't3'), false);
});

test('stationOrderIndexForTrip: a tripOrder map-ből olvas túránként külön sorrendet', () => {
  const station = { tripIds: ['t1', 't2'], tripOrder: { t1: 0, t2: 3 } };
  assert.equal(stationOrderIndexForTrip(station, 't1'), 0);
  assert.equal(stationOrderIndexForTrip(station, 't2'), 3);
});

test('stationOrderIndexForTrip: régi egyetlen orderIndex mezőre visszamenőleg kompatibilis', () => {
  const station = { tripId: 't1', orderIndex: 2 };
  assert.equal(stationOrderIndexForTrip(station, 't1'), 2);
});

test('stationOrderIndexForTrip: ismeretlen túrára 0', () => {
  const station = { tripIds: ['t1'], tripOrder: { t1: 5 } };
  assert.equal(stationOrderIndexForTrip(station, 't2'), 0);
});

test('stationsForTrip: csak a túrához tartozó állomásokat adja, sorrendben', () => {
  const stations = [
    { id: 's1', tripIds: ['t1', 't2'], tripOrder: { t1: 1, t2: 0 } },
    { id: 's2', tripIds: ['t1'], tripOrder: { t1: 0 } },
    { id: 's3', tripIds: ['t2'], tripOrder: { t2: 1 } },
  ];
  const t1 = stationsForTrip(stations, 't1');
  assert.deepEqual(t1.map((s) => s.id), ['s2', 's1']);

  const t2 = stationsForTrip(stations, 't2');
  assert.deepEqual(t2.map((s) => s.id), ['s1', 's3']);
});

test('stationsForTrip: egy állomás két túra listájában is szerepelhet, egymástól független sorrenddel', () => {
  const shared = { id: 'shared', tripIds: ['a', 'b'], tripOrder: { a: 0, b: 2 } };
  const stations = [
    shared,
    { id: 'a2', tripIds: ['a'], tripOrder: { a: 1 } },
    { id: 'b1', tripIds: ['b'], tripOrder: { b: 0 } },
    { id: 'b2', tripIds: ['b'], tripOrder: { b: 1 } },
  ];
  assert.deepEqual(stationsForTrip(stations, 'a').map((s) => s.id), ['shared', 'a2']);
  assert.deepEqual(
    stationsForTrip(stations, 'b').map((s) => s.id),
    ['b1', 'b2', 'shared'],
  );
});
