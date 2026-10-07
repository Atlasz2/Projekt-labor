import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import {
  applyQrHardening,
  generateQrCode,
  isWeakQrCode,
  planQrHardening,
  qrHash,
  reprintCsv,
} from '../lib/qr-harden-core.js';
import { qrMappingDocId, redeemQrCore } from '../lib/redeem-core.js';
import { FakeFirestore, FakeFieldValue } from './fake-firestore.js';

let db;
let counter;
const fakeGenerate = () => `NV-UJKOD${String(++counter).padStart(8, '0')}`;

beforeEach(() => {
  db = new FakeFirestore();
  counter = 0;
});

// Közös ellenőrző értékek – az admin (Web Crypto) és a mobil (package:crypto)
// tesztje ugyanezeket várja.
test('qrHash: SHA-256 hex, egyezik a közös ellenőrző értékekkel', () => {
  assert.equal(qrHash('NV-TEST'), '0abb45e3145aaa2aa1615ef649495da944a4ddabf2ab985ab4977df7a6f18c7e');
  assert.equal(
    qrHash('Kinizsi-vár-ÁRVÍZTŰRŐ'),
    '4b0ad59562f24dd4fcdb87acf1aa7e50f8f0520f619b8ba0929bec5da53676c1',
  );
});

test('generateQrCode: 16 jeles, kétértelmű jelek nélküli, nem ismétlődő kód', () => {
  const codes = new Set(Array.from({ length: 500 }, () => generateQrCode()));
  assert.equal(codes.size, 500);
  for (const c of codes) assert.match(c, /^NV-[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{16}$/);
});

test('isWeakQrCode: hiányzó, rövid és azonosítóval egyező kód gyenge', () => {
  assert.equal(isWeakQrCode('', 'st1'), true);
  assert.equal(isWeakQrCode('VAR-001', 'st1'), true);
  assert.equal(isWeakQrCode('st1-hosszu-azonosito', 'st1-hosszu-azonosito'), true);
  assert.equal(isWeakQrCode('VARKERT-2026-TAVASZ', 'st1'), false);
});

test('terv: az erős kód marad, a gyenge új kódot kap és újranyomtatandó', async () => {
  db.seed('stations/st1', { name: 'Vár', qrCode: 'VARKERT-2026-TAVASZ' });
  db.seed('stations/st2', { name: 'Kút' }); // doc-id a kód
  db.seed('stations/st3', { name: 'Templom', qrCode: 'TEMP-1', projectId: 'nagyvazsony' });
  db.seed('events/ev1', { name: 'Vártúra', qrCode: 'ev1', projectId: 'mencshely' });

  const plan = await planQrHardening(db, { generate: fakeGenerate });
  const byId = Object.fromEntries(plan.items.map((i) => [i.id, i]));

  assert.equal(byId.st1.code, 'VARKERT-2026-TAVASZ');
  assert.equal(byId.st1.reprint, false);
  assert.equal(byId.st2.reprint, true);
  assert.equal(byId.st2.reason, 'azonosítóval egyező kód');
  assert.equal(byId.st3.reason, 'rövid kód');
  assert.equal(byId.ev1.projectId, 'mencshely');
  assert.equal(byId.ev1.kind, 'event');
  assert.match(byId.ev1.code, /^NV-UJKOD/);
});

test('terv: két elem azonos (erős) kódja esetén a második új kódot kap', async () => {
  db.seed('stations/a', { name: 'A', qrCode: 'KOZOS-KOD-123456' });
  db.seed('stations/b', { name: 'B', qrCode: 'KOZOS-KOD-123456' });

  const plan = await planQrHardening(db, { generate: fakeGenerate });

  assert.equal(plan.items[0].code, 'KOZOS-KOD-123456');
  assert.equal(plan.items[1].reason, 'ütköző kód');
  assert.notEqual(plan.items[1].code, 'KOZOS-KOD-123456');
});

test('terv: nyilvános mező nélkül a meglévő leképezés kódja az irányadó; az árva és elavult leképezés törlendő', async () => {
  // Az új admin már nem ír nyilvános qrCode mezőt – a kód a leképezésben él.
  db.seed('stations/st1', { name: 'Vár' });
  db.seed(`qr_codes/${qrMappingDocId('NV-MEGLEVO-KOD-01')}`, { code: 'NV-MEGLEVO-KOD-01', kind: 'station', targetId: 'st1' });
  db.seed('qr_codes/st1', { code: 'st1', kind: 'station', targetId: 'st1' });
  db.seed('qr_codes/ARVA-KOD-1234567', { code: 'ARVA-KOD-1234567', kind: 'station', targetId: 'torolt' });

  const plan = await planQrHardening(db, { generate: fakeGenerate });

  assert.equal(plan.items[0].code, 'NV-MEGLEVO-KOD-01');
  assert.equal(plan.items[0].reprint, false);
  assert.deepEqual(plan.staleMappings.sort(), ['ARVA-KOD-1234567', 'st1']);
});

test('terv: ha a nyilvános (matricán lévő) kód gyenge, akkor is új kód és újranyomtatás jár', async () => {
  // A matricára az került, amit az admin mutatott: a nyilvános mező értéke.
  db.seed('stations/st1', { name: 'Vár', qrCode: 'st1' });
  db.seed('qr_codes/st1', { code: 'st1', kind: 'station', targetId: 'st1' });

  const plan = await planQrHardening(db, { generate: fakeGenerate });

  assert.equal(plan.items[0].oldCode, 'st1');
  assert.equal(plan.items[0].reprint, true);
});

test('végrehajtás: lenyomat a nyilvános dokumentumban, kód csak a leképezésben', async () => {
  db.seed('stations/st1', { name: 'Vár', qrCode: 'VARKERT-2026-TAVASZ', projectId: 'nagyvazsony' });
  db.seed('stations/st2', { name: 'Kút' });
  db.seed('qr_codes/st2', { code: 'st2', kind: 'station', targetId: 'st2' });

  const plan = await planQrHardening(db, { generate: fakeGenerate });
  await applyQrHardening(db, FakeFieldValue, plan);

  const st1 = db.read('stations/st1');
  assert.equal(st1.qrCode, undefined);
  assert.equal(st1.qrHash, qrHash('VARKERT-2026-TAVASZ'));
  assert.deepEqual(
    { ...db.read(`qr_codes/${qrMappingDocId('VARKERT-2026-TAVASZ')}`), updatedAt: null },
    { code: 'VARKERT-2026-TAVASZ', kind: 'station', targetId: 'st1', projectId: 'nagyvazsony', updatedAt: null },
  );
  assert.equal(db.read('qr_codes/st2'), undefined, 'az azonosító-alapú régi leképezés törlődik');
  assert.equal(db.read('stations/st2').qrHash, qrHash('NV-UJKOD00000001'));
});

test('végrehajtás után a régi (kitalálható) kód nem, az új kód beváltható', async () => {
  db.seed('stations/st2', { name: 'Kút', points: 10 });
  db.seed('user_progress/u1', { totalPoints: 0, completedStations: [], completedEvents: [], completedTripIds: [] });

  await applyQrHardening(db, FakeFieldValue, await planQrHardening(db, { generate: fakeGenerate }));

  const redeem = (code) =>
    redeemQrCore({ db, FieldValue: FakeFieldValue, uid: 'u1', code, legacyFallback: false });
  assert.deepEqual(await redeem('st2'), { found: false });
  assert.equal((await redeem('NV-UJKOD00000001')).found, true);
  assert.equal(db.read('user_progress/u1').totalPoints, 10);
});

test('idempotens: a második futás nem ad új kódot és nem jelöl újranyomtatást', async () => {
  db.seed('stations/st2', { name: 'Kút' });
  await applyQrHardening(db, FakeFieldValue, await planQrHardening(db, { generate: fakeGenerate }));

  const second = await planQrHardening(db, { generate: fakeGenerate });

  assert.equal(second.items[0].code, 'NV-UJKOD00000001');
  assert.equal(second.items.filter((i) => i.reprint).length, 0);
  assert.deepEqual(second.staleMappings, []);
});

test('újranyomtatási CSV: fejléc és csak az új kódot kapó elemek', async () => {
  db.seed('stations/st1', { name: 'Vár "felső"', qrCode: 'VARKERT-2026-TAVASZ' });
  db.seed('stations/st2', { name: 'Kút' });

  const csv = reprintCsv(await planQrHardening(db, { generate: fakeGenerate }));
  const lines = csv.split('\n');

  assert.equal(lines.length, 2);
  assert.match(lines[0], /^"település";"típus";"név"/);
  assert.equal(lines[1], '"nagyvazsony";"állomás";"Kút";"st2";"NV-UJKOD00000001";"azonosítóval egyező kód"');
});
