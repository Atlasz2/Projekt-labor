import { doc, getDoc, setDoc, deleteDoc, serverTimestamp } from 'firebase/firestore';

// A QR-kód → cél (állomás/esemény) leképezés a privát `qr_codes` kollekcióban
// él, így a mobil kliensek elől elrejthetők a QR-értékek: a redeemQr Cloud
// Function Admin SDK-val olvassa (lásd docs/SERVER_VALIDATION.md).
// A dokumentum-azonosító a kód URI-kódolt formája — a Cloud Function
// (functions/lib/redeem-core.js: qrMappingDocId) ugyanígy képez azonosítót.

export const qrMappingDocId = (code) => encodeURIComponent(code);

/** Az érvényes QR-érték: a kitöltött kód, vagy ha üres, a dokumentum id-ja.
 *  Ugyanaz a konvenció, mint a qrHelpers.getQrValue-ban. */
export const effectiveQrCode = (code, targetId) =>
  (code || '').trim() || targetId;

export class QrCodeCollisionError extends Error {
  constructor(code) {
    super(`A(z) "${code}" QR-kód már egy másik elemhez tartozik.`);
    this.name = 'QrCodeCollisionError';
    this.code = code;
  }
}

/**
 * Mentés előtti ütközés-ellenőrzés: egyedi (kézzel megadott) kód nem
 * tartozhat másik elemhez. Üres kódra nem fut (a doc-id nem ütközhet).
 * Új elemnél targetId még nincs — ilyenkor bármilyen létező leképezés ütközés.
 */
export async function assertQrCodeAvailable(db, { code, kind, targetId = null }) {
  const trimmed = (code || '').trim();
  if (!trimmed) return;

  const snap = await getDoc(doc(db, 'qr_codes', qrMappingDocId(trimmed)));
  if (!snap.exists()) return;

  const data = snap.data();
  const sameTarget = data.kind === kind && data.targetId === targetId;
  if (!sameTarget) {
    throw new QrCodeCollisionError(trimmed);
  }
}

/**
 * A leképezés frissítése mentés után. Ha a kód változott, a régi
 * leképezést törli. A hívó felelőssége a hibakezelés (a mentett elem
 * ilyenkor is érvényes: a Cloud Function legacy fallbackje megtalálja).
 */
export async function syncQrMapping(db, { kind, targetId, code, previousCode = null }) {
  const next = effectiveQrCode(code, targetId);
  const prev = previousCode ? effectiveQrCode(previousCode, targetId) : null;

  if (prev && prev !== next) {
    await deleteDoc(doc(db, 'qr_codes', qrMappingDocId(prev)));
  }

  await setDoc(doc(db, 'qr_codes', qrMappingDocId(next)), {
    code: next,
    kind,
    targetId,
    updatedAt: serverTimestamp(),
  });
}

/** A leképezés törlése az elem törlésekor. */
export async function removeQrMapping(db, { code, targetId }) {
  const value = effectiveQrCode(code, targetId);
  await deleteDoc(doc(db, 'qr_codes', qrMappingDocId(value)));
}
