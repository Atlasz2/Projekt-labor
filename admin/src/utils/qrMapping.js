import { collection, doc, getDoc, getDocs, query, serverTimestamp, where } from 'firebase/firestore';

// A QR-kód → cél (állomás/esemény) leképezés a privát `qr_codes` kollekcióban
// él: ez az EGYETLEN hely, ahol a kód értéke tárolódik. A nyilvános állomás-
// és eseménydokumentum csak a kód SHA-256 lenyomatát (`qrHash`) tartalmazza,
// amelyből a kód nem állítható vissza, de a mobil offline felismeréshez elég.
// A redeemQr Cloud Function Admin SDK-val olvassa a leképezést (lásd
// docs/SERVER_VALIDATION.md). A dokumentum-azonosító a kód URI-kódolt
// formája — a Cloud Function (functions/lib/redeem-core.js: qrMappingDocId)
// ugyanígy képez azonosítót.

export const qrMappingDocId = (code) => encodeURIComponent(code);

/** A kézzel megadott QR-érték minimális hossza: a rövid, „beszédes” kódok
 *  (pl. VAR-001) kitalálhatók, és a szerver felé végigpróbálhatók. */
export const MIN_CUSTOM_QR_LENGTH = 12;

// Kétértelmű jelek (0/O, 1/I/L) nélkül, hogy kézzel is begépelhető legyen.
const QR_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
const QR_RANDOM_LENGTH = 16; // 31^16 ≈ 2^79 lehetséges kód

/** Kriptográfiailag véletlen, kitalálhatatlan QR-érték (pl. `NV-8K2M…`). */
export function generateQrCode(prefix = 'NV') {
  const out = [];
  // Elutasításos mintavétel: a 248 fölötti bájtot eldobjuk, így minden jel
  // egyenlő valószínűségű (248 = 8 · 31).
  while (out.length < QR_RANDOM_LENGTH) {
    const bytes = crypto.getRandomValues(new Uint8Array(QR_RANDOM_LENGTH));
    for (const b of bytes) {
      if (b < 248 && out.length < QR_RANDOM_LENGTH) out.push(QR_ALPHABET[b % 31]);
    }
  }
  return `${prefix}-${out.join('')}`;
}

/** A kód SHA-256 lenyomata (kisbetűs hex). Ugyanezt számolja a mobil
 *  (offline felismerés) és a migrációs szkript. */
export async function qrHash(code) {
  const data = new TextEncoder().encode(String(code));
  const digest = await crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Kézzel megadott kód ellenőrzése; hibaüzenet, vagy null, ha elfogadható. */
export function customQrCodeProblem(code) {
  const value = String(code ?? '').trim();
  if (!value) return null; // üres → generált kód lesz
  if (value.length < MIN_CUSTOM_QR_LENGTH) {
    return `Az egyedi QR-kód legalább ${MIN_CUSTOM_QR_LENGTH} karakter legyen (a rövid kód kitalálható). Hagyd üresen, és a rendszer biztonságos kódot generál.`;
  }
  if (value.includes('/')) return 'A QR-kód nem tartalmazhat „/” jelet.';
  return null;
}

/** Gyenge-e egy (már meglévő) kód: hiányzik, a nyilvános dokumentum-
 *  azonosítóval egyezik, vagy túl rövid – ilyenkor új kód és újranyomtatás
 *  javasolt. */
export function isWeakQrCode(code, targetId) {
  const value = String(code ?? '').trim();
  return !value || value === targetId || value.length < MIN_CUSTOM_QR_LENGTH;
}

/** A település leképezései `kind:targetId → kód` alakban. A szabályok csak
 *  település szerint szűrt listázást engednek (tenant-izoláció). */
export async function loadQrCodesByTarget(db, projectId) {
  const snap = await getDocs(
    query(collection(db, 'qr_codes'), where('projectId', '==', projectId)),
  );
  const map = new Map();
  for (const d of snap.docs) {
    const data = d.data();
    const code = data.code ?? decodeURIComponent(d.id);
    map.set(`${data.kind === 'event' ? 'event' : 'station'}:${data.targetId}`, code);
  }
  return map;
}

/** Egy elem érvényes QR-kódja: a leképezésből, a migráció előtti adatnál a
 *  régi nyilvános mezőből, végső esetben a dokumentum-azonosítóból. */
export function currentQrCode(codes, kind, item) {
  return codes?.get(`${kind}:${item.id}`) || item.qrCode || item.id;
}

export class QrCodeCollisionError extends Error {
  constructor(code) {
    super(`A(z) "${code}" QR-kód már egy másik elemhez tartozik.`);
    this.name = 'QrCodeCollisionError';
    this.code = code;
  }
}

/**
 * Mentés előtti ütközés-ellenőrzés: a kód nem tartozhat másik elemhez.
 * Új elemnél targetId még nincs — ilyenkor bármilyen létező leképezés ütközés.
 */
export async function assertQrCodeAvailable(db, { code, kind, targetId = null }) {
  const trimmed = (code || '').trim();
  if (!trimmed) return;
  let snap;
  try {
    snap = await getDoc(doc(db, 'qr_codes', qrMappingDocId(trimmed)));
  } catch (err) {
    // Más település leképezését a szabályok nem engedik olvasni: a kód
    // tehát foglalt (egy másik településen).
    if (err?.code === 'permission-denied') throw new QrCodeCollisionError(trimmed);
    throw err;
  }
  if (!snap.exists()) return;
  const data = snap.data();
  if (!(data.kind === kind && data.targetId === targetId)) {
    throw new QrCodeCollisionError(trimmed);
  }
}

/**
 * Egy elem és a QR-leképezése atomi mentése egyetlen kötegben: vagy a
 * dokumentum és a leképezés is megváltozik, vagy egyik sem – így nem maradhat
 * olyan elem, amelynek a kódja nem oldható fel. A régi kód leképezése törlődik,
 * a nyilvános dokumentumba csak a lenyomat kerül (a régi `qrCode` mező törlődik).
 *
 * @param {object} p
 * @param {import('firebase/firestore').WriteBatch} p.batch
 * @param {{ deleteField: Function }} p.ops – Firestore-transzformok (tesztelhetőség)
 * @param {'station'|'event'} p.kind
 * @param {object} p.targetRef – a cél dokumentum-referenciája (új elemnél előre generált)
 * @param {boolean} p.isNew
 * @param {object} p.payload – a cél többi mezője
 * @param {string} p.code – az új kód
 * @param {string|null} p.previousCode – a korábbi kód (szerkesztéskor)
 * @param {string} p.projectId
 */
export async function stageQrSave(db, { batch, ops, kind, targetRef, isNew, payload, code, previousCode, projectId }) {
  const hash = await qrHash(code);
  const data = { ...payload, qrHash: hash };
  if (isNew) {
    batch.set(targetRef, data);
  } else {
    batch.update(targetRef, { ...data, qrCode: ops.deleteField() });
  }
  if (previousCode && previousCode !== code) {
    batch.delete(doc(db, 'qr_codes', qrMappingDocId(previousCode)));
  }
  batch.set(doc(db, 'qr_codes', qrMappingDocId(code)), {
    code,
    kind,
    targetId: targetRef.id,
    projectId,
    updatedAt: serverTimestamp(),
  });
}

/** Egy elem és a leképezése törlése ugyanabban a kötegben. */
export function stageQrDelete(db, { batch, targetRef, code }) {
  batch.delete(targetRef);
  if (code) batch.delete(doc(db, 'qr_codes', qrMappingDocId(code)));
}
