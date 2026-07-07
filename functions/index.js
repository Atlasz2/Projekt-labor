import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

import { redeemQrCore } from './lib/redeem-core.js';

initializeApp();

// Szerveroldali QR-jóváírás. A kliens (mobil app) csak a nyers kódot küldi;
// a validáció, pontszámítás, jutalom-feloldás és leaderboard-írás itt fut
// Admin SDK jogosultsággal. A Flutter oldal a
// FirebaseFunctions.instanceFor(region: 'europe-west1') példányon hívja.
export const redeemQr = onCall({ region: 'europe-west1' }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Bejelentkezés szükséges.');
  }

  const code =
    typeof request.data?.code === 'string' ? request.data.code.trim() : '';
  if (!code) {
    throw new HttpsError('invalid-argument', 'Hiányzó QR-kód.');
  }

  try {
    return await redeemQrCore({ db: getFirestore(), FieldValue, uid, code });
  } catch (err) {
    console.error('redeemQr failed', { uid, code, err });
    throw new HttpsError('internal', 'A jóváírás nem sikerült, próbáld újra.');
  }
});
