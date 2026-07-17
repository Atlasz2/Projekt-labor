import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';

import { redeemQrCore } from './lib/redeem-core.js';
import { buildEventNotification } from './lib/notification-builder.js';
import { collectUserData, deleteUserData } from './lib/gdpr-core.js';

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

  // Opcionális beolvasáskori eszközpozíció a helyszín-ellenőrzéshez.
  let location = null;
  const rawLat = Number(request.data?.lat);
  const rawLng = Number(request.data?.lng);
  if (Number.isFinite(rawLat) && Number.isFinite(rawLng)) {
    location = { lat: rawLat, lng: rawLng };
  }

  try {
    return await redeemQrCore({
      db: getFirestore(),
      FieldValue,
      uid,
      code,
      location,
    });
  } catch (err) {
    console.error('redeemQr failed', { uid, code, err });
    throw new HttpsError('internal', 'A jóváírás nem sikerült, próbáld újra.');
  }
});

// GDPR 20. cikk — adathordozhatóság: a hívó SAJÁT adatainak teljes exportja.
// A kliens JSON-fájlként menti/megosztja a választ.
export const exportUserData = onCall({ region: 'europe-west1' }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Bejelentkezés szükséges.');
  }

  try {
    return await collectUserData({ db: getFirestore(), uid });
  } catch (err) {
    logger.error('exportUserData failed', { uid, err });
    throw new HttpsError('internal', 'Az adatexport nem sikerült, próbáld újra.');
  }
});

// GDPR 17. cikk — törléshez való jog: a hívó SAJÁT fiókjának és minden
// kapcsolódó dokumentumának törlése (a hibabejelentések anonimizálásával),
// legvégül az Auth-fiókkal együtt. A kliens ezután kijelentkezik.
export const deleteMyAccount = onCall({ region: 'europe-west1' }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Bejelentkezés szükséges.');
  }

  try {
    const result = await deleteUserData({
      db: getFirestore(),
      uid,
      deleteAuthUser: (u) => getAuth().deleteUser(u),
    });
    logger.info('Fiók törölve (GDPR)', {
      uid,
      deletedDocs: result.deleted.length,
      anonymizedBugReports: result.anonymizedBugReports,
    });
    return { ok: true };
  } catch (err) {
    logger.error('deleteMyAccount failed', { uid, err });
    throw new HttpsError('internal', 'A fiók törlése nem sikerült, próbáld újra.');
  }
});

// Új esemény létrehozásakor push-értesítés az 'events' topicra feliratkozott
// mobil klienseknek. A tényleges üzenetet a notification-builder állítja össze.
export const notifyOnNewEvent = onDocumentCreated(
  { region: 'europe-west1', document: 'events/{eventId}' },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const message = buildEventNotification({
      id: event.params.eventId,
      data: snap.data(),
    });
    if (!message) {
      logger.info('Esemény név nélkül — értesítés kihagyva', {
        eventId: event.params.eventId,
      });
      return;
    }

    try {
      const messageId = await getMessaging().send(message);
      logger.info('Esemény-értesítés elküldve', {
        eventId: event.params.eventId,
        messageId,
      });
    } catch (err) {
      logger.error('Esemény-értesítés sikertelen', {
        eventId: event.params.eventId,
        err,
      });
    }
  },
);
