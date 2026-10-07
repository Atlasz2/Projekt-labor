// A QR-kódok indulás előtti megerősítése (T7 – QR-enumeráció lezárása).
//
// Cél-állapot minden állomásra és rendezvényre:
//  - a kód értéke CSAK a privát qr_codes leképezésben él (projectId-vel),
//  - a nyilvános dokumentum a kód SHA-256 lenyomatát tárolja (qrHash), a régi
//    qrCode mező törlődik,
//  - a kitalálható kódok (hiányzó, a nyilvános dokumentum-azonosítóval egyező,
//    rövid vagy ütköző) új, véletlen kódot kapnak – ezek matricáját újra kell
//    nyomtatni (a terv `reprint` listája).
//
// A modul nem importálja a firebase-admin-t: a db-t és a FieldValue-t a hívó
// (scripts/harden-qr-codes.mjs, illetve a tesztek) adja.

import { createHash, randomInt } from 'node:crypto';

import { qrMappingDocId } from './redeem-core.js';

const DEFAULT_PROJECT_ID = 'nagyvazsony';
export const MIN_QR_LENGTH = 12;
const QR_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
const QR_RANDOM_LENGTH = 16;
const BATCH_LIMIT = 400;

const projectOf = (data) =>
  typeof data?.projectId === 'string' && data.projectId.trim() !== ''
    ? data.projectId
    : DEFAULT_PROJECT_ID;

/** A kód SHA-256 lenyomata (kisbetűs hex) – az admin és a mobil párja. */
export function qrHash(code) {
  return createHash('sha256').update(String(code), 'utf8').digest('hex');
}

/** Kriptográfiailag véletlen, kitalálhatatlan kód (az admin generátor párja). */
export function generateQrCode(prefix = 'NV') {
  let body = '';
  for (let i = 0; i < QR_RANDOM_LENGTH; i++) body += QR_ALPHABET[randomInt(QR_ALPHABET.length)];
  return `${prefix}-${body}`;
}

/** Kitalálható-e a kód (hiányzik, egyezik a dokumentum-azonosítóval, rövid). */
export function isWeakQrCode(code, targetId) {
  const value = String(code ?? '').trim();
  return !value || value === targetId || value.length < MIN_QR_LENGTH;
}

/**
 * A migrációs terv összeállítása – csak olvas.
 * @returns {Promise<{items: Array, staleMappings: string[]}>}
 *   items: { kind, id, projectId, name, oldCode, code, reprint, reason }
 *   staleMappings: törlendő qr_codes dokumentum-azonosítók (árva vagy elavult)
 */
export async function planQrHardening(db, { generate = generateQrCode } = {}) {
  const mappingSnap = await db.collection('qr_codes').get();
  const mappingsByTarget = new Map(); // kind:targetId -> [{docId, code}]
  for (const d of mappingSnap.docs) {
    const m = d.data();
    const kind = m.kind === 'event' ? 'event' : 'station';
    const key = `${kind}:${m.targetId}`;
    const code = String(m.code ?? decodeURIComponent(d.id));
    if (!mappingsByTarget.has(key)) mappingsByTarget.set(key, []);
    mappingsByTarget.get(key).push({ docId: d.id, code });
  }

  const items = [];
  const usedCodes = new Set();
  const keptMappingIds = new Set();

  for (const [coll, kind] of [['stations', 'station'], ['events', 'event']]) {
    const snap = await db.collection(coll).get();
    for (const docSnap of snap.docs) {
      const data = docSnap.data();
      const mappings = mappingsByTarget.get(`${kind}:${docSnap.id}`) ?? [];
      const publicCode = String(data.qrCode ?? '').trim();
      // A matricán lévő kód: elsősorban a nyilvános mezővel egyező leképezés,
      // aztán bármely leképezés, aztán a régi mező, végül a dokumentum-id.
      const oldCode =
        mappings.find((m) => m.code === publicCode)?.code ??
        mappings[0]?.code ??
        (publicCode || docSnap.id);

      let code = oldCode;
      let reason = null;
      if (isWeakQrCode(oldCode, docSnap.id)) {
        reason = oldCode === docSnap.id ? 'azonosítóval egyező kód' : 'rövid kód';
      } else if (usedCodes.has(oldCode)) {
        reason = 'ütköző kód';
      }
      if (reason) {
        do {
          code = generate();
        } while (usedCodes.has(code));
      }
      usedCodes.add(code);
      keptMappingIds.add(qrMappingDocId(code));

      items.push({
        kind,
        id: docSnap.id,
        projectId: projectOf(data),
        name: String(data.name ?? ''),
        oldCode,
        code,
        reprint: reason != null,
        reason,
      });
    }
  }

  const staleMappings = mappingSnap.docs
    .map((d) => d.id)
    .filter((docId) => !keptMappingIds.has(docId));

  return { items, staleMappings };
}

/** A terv végrehajtása kötegekben. Idempotens: egy már megerősített
 *  adatbázison ugyanazt az állapotot írja vissza. */
export async function applyQrHardening(db, FieldValue, plan) {
  const ops = [];
  for (const docId of plan.staleMappings) {
    ops.push((batch) => batch.delete(db.collection('qr_codes').doc(docId)));
  }
  for (const item of plan.items) {
    const coll = item.kind === 'event' ? 'events' : 'stations';
    ops.push((batch) =>
      batch.set(db.collection('qr_codes').doc(qrMappingDocId(item.code)), {
        code: item.code,
        kind: item.kind,
        targetId: item.id,
        projectId: item.projectId,
        updatedAt: FieldValue.serverTimestamp(),
      }),
    );
    ops.push((batch) =>
      batch.update(db.collection(coll).doc(item.id), {
        qrHash: qrHash(item.code),
        qrCode: FieldValue.delete(),
      }),
    );
  }

  let written = 0;
  for (let i = 0; i < ops.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    for (const op of ops.slice(i, i + BATCH_LIMIT)) op(batch);
    await batch.commit();
    written += Math.min(BATCH_LIMIT, ops.length - i);
  }
  return { written };
}

/** Az újranyomtatandó matricák listája CSV-ben (pontosvesszővel, Excelhez). */
export function reprintCsv(plan) {
  const esc = (v) => `"${String(v).replace(/"/g, '""')}"`;
  const rows = plan.items
    .filter((i) => i.reprint)
    .map((i) => [i.projectId, i.kind === 'event' ? 'rendezvény' : 'állomás', i.name, i.id, i.code, i.reason]);
  return [
    ['település', 'típus', 'név', 'azonosító', 'új QR-kód', 'ok'],
    ...rows,
  ]
    .map((r) => r.map(esc).join(';'))
    .join('\n');
}
