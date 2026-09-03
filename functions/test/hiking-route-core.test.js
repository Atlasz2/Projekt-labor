import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  decodePolyline6,
  appendRoutePoints,
  buildValhallaPayload,
  buildOsrmPath,
  parseValhallaResponse,
  parseOsrmResponse,
  buildBRouterUrl,
  parseBRouterResponse,
  normalizeCoordinates,
} from '../lib/hiking-route-core.js';

test('buildValhallaPayload: a földutakat preferáló beállítás (mint a mobilon)', () => {
  const payload = buildValhallaPayload([
    [47.0975, 17.6928],
    [47.0995, 17.6975],
  ]);

  assert.equal(payload.costing, 'pedestrian');
  // Ez a kulcs: a földutak/nyomvonalak előnyben részesítése.
  assert.equal(payload.costing_options.pedestrian.use_tracks, 1.0);
  assert.equal(payload.costing_options.pedestrian.use_hills, 0.6);
  assert.deepEqual(payload.locations[0], {
    lat: 47.0975,
    lon: 17.6928,
    type: 'break',
  });
});

test('decodePolyline6 oda-vissza: a kódolt pontsor visszafejthető', () => {
  // A Valhalla shape-je 1e6 pontosságú polyline. Egy ismert, rövid minta:
  const points = decodePolyline6('_ibE_seK_seK_seK');
  assert.ok(points.length >= 2);
  points.forEach(([lat, lon]) => {
    assert.ok(Number.isFinite(lat));
    assert.ok(Number.isFinite(lon));
  });
});

test('appendRoutePoints: az illesztési pont nem duplázódik', () => {
  const target = [
    [47.1, 17.6],
    [47.2, 17.7],
  ];
  appendRoutePoints(target, [
    [47.2, 17.7], // ugyanaz, mint az előző vége
    [47.3, 17.8],
  ]);
  assert.equal(target.length, 3);
  assert.deepEqual(target[2], [47.3, 17.8]);
});

test('appendRoutePoints: nem érintkező szakasz teljes egészében hozzáfűződik', () => {
  const target = [[47.1, 17.6]];
  appendRoutePoints(target, [
    [47.5, 17.9],
    [47.6, 18.0],
  ]);
  assert.equal(target.length, 3);
});

test('parseValhallaResponse: szakaszokból útvonal, km→m átváltással', () => {
  const shape = '_ibE_seK_seK_seK';
  const result = parseValhallaResponse({
    trip: { legs: [{ shape }], summary: { length: 2.5, time: 1800 } },
  });

  assert.ok(result);
  assert.equal(result.source, 'valhalla-pedestrian');
  assert.equal(result.distanceMeters, 2500); // 2.5 km -> 2500 m
  assert.equal(result.durationSeconds, 1800);
  assert.ok(result.coords.length >= 2);
});

test('parseValhallaResponse: hiányzó/üres szakaszokra null', () => {
  assert.equal(parseValhallaResponse({}), null);
  assert.equal(parseValhallaResponse({ trip: { legs: [] } }), null);
  assert.equal(parseValhallaResponse({ trip: { legs: [{ shape: '' }] } }), null);
});

test('parseOsrmResponse: [lon,lat] -> [lat,lon] fordítás', () => {
  const result = parseOsrmResponse({
    routes: [
      {
        geometry: {
          coordinates: [
            [17.6928, 47.0975],
            [17.6975, 47.0995],
          ],
        },
        distance: 386.4,
        duration: 278.1,
      },
    ],
  });

  assert.ok(result);
  assert.deepEqual(result.coords[0], [47.0975, 17.6928]);
  assert.equal(result.source, 'osrm-foot');
  assert.equal(result.distanceMeters, 386.4);
});

test('parseOsrmResponse: kevés pontra vagy hiányzó útvonalra null', () => {
  assert.equal(parseOsrmResponse({}), null);
  assert.equal(parseOsrmResponse({ routes: [] }), null);
  assert.equal(
    parseOsrmResponse({ routes: [{ geometry: { coordinates: [[17.6, 47.1]] } }] }),
    null,
  );
});

test('buildOsrmPath: lon,lat sorrend pontosvesszővel', () => {
  assert.equal(
    buildOsrmPath([
      [47.1, 17.6],
      [47.2, 17.7],
    ]),
    '17.6,47.1;17.7,47.2',
  );
});

test('normalizeCoordinates: érvénytelen párokat kiszűr', () => {
  const out = normalizeCoordinates([
    [47.1, 17.6],
    ['nem', 'szam'],
    [200, 17.6], // érvénytelen szélesség
    [47.2, 17.7],
    null,
  ]);
  assert.deepEqual(out, [
    [47.1, 17.6],
    [47.2, 17.7],
  ]);
});

test('buildBRouterUrl: lon,lat párok | jellel, túra-profillal', () => {
  const url = buildBRouterUrl([
    [47.0975, 17.6928],
    [47.0995, 17.6975],
  ]);
  assert.ok(url.includes('lonlats=17.6928,47.0975|17.6975,47.0995'));
  // Ez a kulcs: a túra-profil adja a föld-/erdei utas útvonalat.
  assert.ok(url.includes('profile=hiking-beta'));
  assert.ok(url.includes('format=geojson'));
});

test('parseBRouterResponse: [lon,lat(,magasság)] -> [lat,lon]', () => {
  const result = parseBRouterResponse({
    features: [
      {
        geometry: {
          coordinates: [
            [17.6928, 47.0975, 210],
            [17.695, 47.098, 215],
            [17.6975, 47.0995, 220],
          ],
        },
        properties: { 'track-length': '4098', 'total-time': '3200' },
      },
    ],
  });

  assert.ok(result);
  assert.deepEqual(result.coords[0], [47.0975, 17.6928]);
  assert.equal(result.coords.length, 3);
  assert.equal(result.distanceMeters, 4098);
  assert.equal(result.durationSeconds, 3200);
  assert.equal(result.source, 'brouter-hiking');
});

test('parseBRouterResponse: hiányzó/kevés pontra null', () => {
  assert.equal(parseBRouterResponse({}), null);
  assert.equal(parseBRouterResponse({ features: [] }), null);
  assert.equal(
    parseBRouterResponse({
      features: [{ geometry: { coordinates: [[17.6, 47.1]] } }],
    }),
    null,
  );
});
