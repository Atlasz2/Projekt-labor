import { randomBytes } from 'node:crypto';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import { defineBoolean } from 'firebase-functions/params';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';

import { redeemQrCore, reconcileAchievementsCore } from './lib/redeem-core.js';
import { buildEventNotification } from './lib/notification-builder.js';
import { collectUserData, deleteUserData } from './lib/gdpr-core.js';
import { InvalidNameError, NameTakenError, renameUserCore } from './lib/profile-core.js';
import { computeTripAnalytics } from './lib/analytics-core.js';
import {
  buildValhallaPayload,
  buildOsrmPath,
  buildBRouterUrl,
  parseValhallaResponse,
  parseOsrmResponse,
  parseBRouterResponse,
  normalizeCoordinates,
} from './lib/hiking-route-core.js';

initializeApp();

// Staff = admin (egy település kezelője) VAGY developer (platform-szintű).
// Ugyanaz a logika, mint a firestore.rules staffRoles()/isAdmin() párosában
// (users/{uid}.role, vagy az email-doc variáns). Máskülönben permission-denied.
const STAFF_ROLES = ['admin', 'developer'];

// A mobilból hívott callable-ök közös beállítása (lásd a redeemQr feletti
// App Check-megjegyzést).
const MOBILE_CALLABLE = { region: 'europe-west1', enforceAppCheck: false };

// Indulási kapcsolók – telepítéskor a functions/.env.<projekt> fájlból
// olvasódnak, így az élesítés lépései kódmódosítás nélkül, konfigurációval
// tehetők meg (lásd docs/LAUNCH.md).
//
// ENFORCE_APP_CHECK: a mobil callable-ök csak érvényes App Check-tokennel
// fogadnak kérést. Az áruházi (Play Integrity) kiadás után kapcsolandó be.
const ENFORCE_APP_CHECK = defineBoolean('ENFORCE_APP_CHECK', {
  default: false,
  description: 'A mobil callable-ök megkövetelik az érvényes App Check-tokent.',
});
// QR_LEGACY_FALLBACK: a QR-kód feloldása a nyilvános qrCode mezőn és a
// dokumentum-azonosítón keresztül is. A QR-migráció (scripts/harden-qr-codes.mjs)
// után kikapcsolandó, különben a kódok kigyűjthetők (T7).
const QR_LEGACY_FALLBACK = defineBoolean('QR_LEGACY_FALLBACK', {
  default: true,
  description: 'QR-feloldás a nyilvános mezőkön át (csak a migráció előtt).',
});

/** App Check a mobil hívásokon: a token mindig naplózódik; ha a kikényszerítés
 *  be van kapcsolva, token nélkül a kérés elutasul. */
function assertAppCheck(request) {
  if (request.app) return;
  if (ENFORCE_APP_CHECK.value()) {
    throw new HttpsError(
      'unauthenticated',
      'Az alkalmazás hitelesítése sikertelen. Telepítsd a hivatalos áruházból.',
    );
  }
  logger.warn('Mobil hívás App Check-token nélkül', {
    uid: request.auth?.uid ?? null,
  });
}

async function assertAdmin(db, request) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Bejelentkezés szükséges.');
  }
  const byUid = await db.collection('users').doc(uid).get();
  if (byUid.exists && STAFF_ROLES.includes(byUid.data()?.role)) return uid;

  const email = request.auth?.token?.email;
  if (email) {
    const byEmail = await db.collection('users').doc(email).get();
    const data = byEmail.exists ? byEmail.data() : null;
    if (
      data &&
      STAFF_ROLES.includes(data.role) &&
      data.email === email &&
      data.uid === uid
    ) {
      return uid;
    }
  }
  throw new HttpsError('permission-denied', 'Admin jogosultság szükséges.');
}

// Developer (platform-szintű) jogosultság ellenőrzése. Szigorúbb az adminnál:
// csak a users/{uid}.role == 'developer' megy át. Felhasználó-törléshez és
// szerep-adáshoz kell.
async function assertDeveloper(db, request) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Bejelentkezés szükséges.');
  }
  const snap = await db.collection('users').doc(uid).get();
  if (snap.exists && snap.data()?.role === 'developer') return uid;
  throw new HttpsError('permission-denied', 'Developer jogosultság szükséges.');
}

// Szerveroldali QR-jóváírás. A kliens (mobil app) csak a nyers kódot küldi;
// a validáció, pontszámítás, jutalom-feloldás és leaderboard-írás itt fut
// Admin SDK jogosultsággal. A Flutter oldal a
// FirebaseFunctions.instanceFor(region: 'europe-west1') példányon hívja.
//
// App Check: a mobilból hívott callable-ök (redeemQr, reconcileAchievements,
// renameMe, exportUserData, deleteMyAccount) az App Check-tokent ellenőrzik és
// naplózzák; a kikényszerítést az ENFORCE_APP_CHECK kapcsoló (assertAppCheck)
// adja, a platform szintű MOBILE_CALLABLE.enforceAppCheck pedig ki van kapcsolva.
// Ok: a Firebase App Distributionnel terjesztett, nem a Play Áruházból
// telepített Android-build nem kap érvényes Play Integrity-tokent, így a
// kikényszerítés minden hívást elutasított ("app: INVALID" a naplóban). A
// Play Áruházas kiadás és az App Check konzolbeli regisztrációja után az
// ENFORCE_APP_CHECK=true beállítással visszakapcsolható. A pontintegritást ettől függetlenül a szerveroldali
// jóváírás és a lezárt Firestore-szabályok védik.
export const redeemQr = onCall(
  MOBILE_CALLABLE,
  async (request) => {
  assertAppCheck(request);
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

  // A kiadás települése (white-label). Régi appverzió nem küldi – akkor nincs
  // település-szűrés, hogy a meglévő telepítések ne törjenek el.
  const projectId =
    typeof request.data?.projectId === 'string'
      ? request.data.projectId.trim()
      : '';

  try {
    return await redeemQrCore({
      db: getFirestore(),
      FieldValue,
      uid,
      code,
      location,
      projectId,
      legacyFallback: QR_LEGACY_FALLBACK.value(),
    });
  } catch (err) {
    logger.error('redeemQr failed', { uid, code, err });
    throw new HttpsError('internal', 'A jóváírás nem sikerült, próbáld újra.');
  }
});

// A hívó jutalmainak utólagos egyeztetése (a jutalmak képernyő betöltésekor).
// A feloldást a szerver írja, így az unlocked_achievements alkollekció a
// kliens elől lezárható.
export const reconcileAchievements = onCall(
  MOBILE_CALLABLE,
  async (request) => {
  assertAppCheck(request);
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Bejelentkezés szükséges.');
    }
    const projectId =
      typeof request.data?.projectId === 'string' ? request.data.projectId : '';

    try {
      return await reconcileAchievementsCore({
        db: getFirestore(),
        FieldValue,
        uid,
        projectId,
      });
    } catch (err) {
      logger.error('reconcileAchievements failed', { uid, err });
      throw new HttpsError('internal', 'A jutalmak frissítése nem sikerült.');
    }
  },
);

// A játékos nevének módosítása (névfoglalás, profil, haladás, ranglisták).
// A ranglistát csak a szerver írhatja, ezért a módosítás itt fut. E-mailhez
// kötött fióknál a névből képzett visszaállítási jelszó is frissül, hogy a
// másik eszközös belépés az új névvel működjön.
export const renameMe = onCall(
  MOBILE_CALLABLE,
  async (request) => {
  assertAppCheck(request);
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Bejelentkezés szükséges.');
    }
    const auth = getAuth();
    try {
      return await renameUserCore({
        db: getFirestore(),
        FieldValue,
        uid,
        name: request.data?.name,
        updatePassword: async (password) => {
          const user = await auth.getUser(uid);
          if (user.providerData.some((p) => p.providerId === 'password')) {
            await auth.updateUser(uid, { password });
          }
        },
      });
    } catch (err) {
      if (err instanceof NameTakenError) {
        throw new HttpsError('already-exists', err.message);
      }
      if (err instanceof InvalidNameError) {
        throw new HttpsError('invalid-argument', err.message);
      }
      logger.error('renameMe failed', { uid, err });
      throw new HttpsError('internal', 'A név módosítása nem sikerült.');
    }
  },
);

// GDPR 20. cikk — adathordozhatóság: a hívó SAJÁT adatainak teljes exportja.
// A kliens JSON-fájlként menti/megosztja a választ.
export const exportUserData = onCall(
  MOBILE_CALLABLE,
  async (request) => {
  assertAppCheck(request);
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
export const deleteMyAccount = onCall(
  MOBILE_CALLABLE,
  async (request) => {
  assertAppCheck(request);
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

// Developer-only: egy MÁSIK felhasználó teljes törlése (Auth-fiók + minden
// kapcsolódó dokumentum, a hibabejelentések anonimizálásával). Ugyanazt a
// tesztelt gdpr-core magot használja, mint a saját fiók törlése.
export const adminDeleteUser = onCall({ region: 'europe-west1' }, async (request) => {
  const db = getFirestore();
  try {
    const callerUid = await assertDeveloper(db, request);

    const targetUid = String(request.data?.uid ?? '').trim();
    if (!targetUid) {
      throw new HttpsError('invalid-argument', 'Hiányzó felhasználó-azonosító.');
    }
    // Önmagát ne tudja törölni (kizárná magát a rendszerből).
    if (targetUid === callerUid) {
      throw new HttpsError(
        'failed-precondition',
        'A saját fiókodat itt nem törölheted.',
      );
    }

    const result = await deleteUserData({
      db,
      uid: targetUid,
      deleteAuthUser: (u) => getAuth().deleteUser(u),
    });
    logger.info('Felhasználó törölve (developer)', {
      callerUid,
      targetUid,
      deletedDocs: result.deleted.length,
    });
    return { ok: true, deletedDocs: result.deleted.length };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logger.error('adminDeleteUser failed', { message: err?.message, stack: err?.stack });
    throw new HttpsError('internal', 'A felhasználó törlése nem sikerült.', {
      reason: String(err?.message ?? err),
    });
  }
});

// Túraútvonal-tervezés az admin panelnek. A böngészőből a Valhalla nem hívható
// megbízhatóan (CORS / hálózati korlátok), ezért szerveroldalról kérjük –
// UGYANAZZAL a föld- és erdeiút-preferáló beállítással, mint a mobilapp
// (use_tracks: 1.0). Ha a Valhalla nem elérhető, OSRM gyalogos tartalék jön.
export const hikingRoute = onCall(
  { region: 'europe-west1', timeoutSeconds: 60 },
  async (request) => {
    const db = getFirestore();
    try {
      await assertAdmin(db, request);

      const coordinates = normalizeCoordinates(request.data?.coordinates);
      if (coordinates.length < 2) {
        throw new HttpsError(
          'invalid-argument',
          'Legalább két érvényes koordináta szükséges.',
        );
      }

      const withTimeout = async (url, options, ms) => {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), ms);
        try {
          return await fetch(url, { ...options, signal: controller.signal });
        } finally {
          clearTimeout(timer);
        }
      };

      const UA = 'NagyvazsonyTuraApp/1.0 (+szakdolgozat)';

      // 1) BRouter – túrázásra tervezett; a föld- és erdei utakat, ösvényeket
      //    részesíti előnyben. Ez adja a valódi túraútvonalat.
      try {
        const res = await withTimeout(
          buildBRouterUrl(coordinates),
          { headers: { 'User-Agent': UA } },
          12000,
        );
        if (res.ok) {
          const parsed = parseBRouterResponse(await res.json());
          if (parsed) return parsed;
        }
      } catch (err) {
        logger.info('BRouter nem elérhető, jön a Valhalla', {
          message: err?.message,
        });
      }

      // 2) Valhalla – szintén turistaút-preferáló (a mobilapp elsődlege).
      //    Rövidebb időkorláttal, mert itt már csak tartalék.
      try {
        const res = await withTimeout(
          'https://valhalla1.openstreetmap.de/route',
          {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'User-Agent': UA },
            body: JSON.stringify(buildValhallaPayload(coordinates)),
          },
          6000,
        );
        if (res.ok) {
          const parsed = parseValhallaResponse(await res.json());
          if (parsed) return parsed;
        }
      } catch (err) {
        logger.info('Valhalla nem elérhető, jön az OSRM', {
          message: err?.message,
        });
      }

      // 3) OSRM gyalogos tartalék (közutakat is használ – csak végszükség).
      try {
        const path = buildOsrmPath(coordinates);
        const res = await withTimeout(
          `https://router.project-osrm.org/route/v1/foot/${path}?overview=full&geometries=geojson&steps=false&continue_straight=false`,
          {},
          15000,
        );
        if (res.ok) {
          const parsed = parseOsrmResponse(await res.json());
          if (parsed) return parsed;
        }
      } catch (err) {
        logger.warn('OSRM sem elérhető', { message: err?.message });
      }

      // 4) Végső eset: az állomásokat egyenes szakaszok kötik össze.
      return {
        coords: coordinates,
        distanceMeters: 0,
        durationSeconds: 0,
        source: 'fallback',
      };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      logger.error('hikingRoute failed', {
        message: err?.message,
        stack: err?.stack,
      });
      throw new HttpsError('internal', 'Az útvonal lekérése nem sikerült.', {
        reason: String(err?.message ?? err),
      });
    }
  },
);

// Developer-only: admin meghívása e-mail alapján. Ha a fiók még nem létezik,
// létrehozza; majd admin szerepkört és települést rendel hozzá. Visszaad egy
// jelszó-beállító linket, amit a developer eljuttathat a meghívottnak – így
// nem kell külön e-mail-küldő szolgáltatás.
export const inviteAdmin = onCall({ region: 'europe-west1' }, async (request) => {
  const db = getFirestore();
  try {
    await assertDeveloper(db, request);

    const email = String(request.data?.email ?? '').trim().toLowerCase();
    const name = String(request.data?.name ?? '').trim() || 'Admin';
    const projectId = String(request.data?.projectId ?? '').trim() || 'nagyvazsony';

    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      throw new HttpsError('invalid-argument', 'Érvénytelen e-mail cím.');
    }

    const auth = getAuth();
    let uid;
    let created = false;
    try {
      uid = (await auth.getUserByEmail(email)).uid;
    } catch (err) {
      if (err?.code !== 'auth/user-not-found') throw err;
      // Ideiglenes, véletlen jelszó – a meghívott a linken állítja be a sajátját.
      const temporary = `Inv-${randomBytes(24).toString('base64url')}`;
      uid = (await auth.createUser({ email, password: temporary, displayName: name })).uid;
      created = true;
    }

    await db.collection('users').doc(uid).set(
      {
        uid,
        email,
        name,
        displayName: name,
        role: 'admin',
        projectId,
        banned: false,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const resetLink = await auth.generatePasswordResetLink(email);
    logger.info('Admin meghívva', { uid, email, projectId, created });
    return { ok: true, uid, created, resetLink };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logger.error('inviteAdmin failed', { message: err?.message, stack: err?.stack });
    throw new HttpsError('internal', 'A meghívás nem sikerült.', {
      reason: String(err?.message ?? err),
    });
  }
});

// Developer-only: felhasználó kitiltása / feloldása (visszafordítható, a
// végleges törlés alternatívája). Letiltja az Auth-fiókot – a kitiltott
// felhasználó nem tud bejelentkezni –, és jelöli a users dokumentumban.
export const setUserBanned = onCall({ region: 'europe-west1' }, async (request) => {
  const db = getFirestore();
  try {
    const callerUid = await assertDeveloper(db, request);

    const targetUid = String(request.data?.uid ?? '').trim();
    const banned = request.data?.banned === true;
    if (!targetUid) {
      throw new HttpsError('invalid-argument', 'Hiányzó felhasználó-azonosító.');
    }
    if (targetUid === callerUid) {
      throw new HttpsError('failed-precondition', 'Magadat nem tilthatod ki.');
    }

    // Az Auth-fiók letiltása a tényleges védelem (nem tud belépni).
    try {
      await getAuth().updateUser(targetUid, { disabled: banned });
    } catch (err) {
      // Lehet, hogy csak Firestore-beli (anonim/haladás) felhasználó – a
      // jelölést akkor is elvégezzük.
      if (err?.code !== 'auth/user-not-found') throw err;
    }

    await db.collection('users').doc(targetUid).set(
      { banned, updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );

    logger.info('Felhasználó kitiltás állítva', { callerUid, targetUid, banned });
    return { ok: true, banned };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logger.error('setUserBanned failed', { message: err?.message, stack: err?.stack });
    throw new HttpsError('internal', 'A művelet nem sikerült.', {
      reason: String(err?.message ?? err),
    });
  }
});

// Developer-only migráció: a projektenkénti ranglista feltöltése a meglévő
// haladásból. Enélkül az új (településenkénti) ranglista üresen indulna, mert
// csak az ezután történő beolvasások növelnék. A pontokat az adott település
// SAJÁT állomásaiból/eseményeiből számoljuk.
export const seedProjectLeaderboards = onCall(
  { region: 'europe-west1', memory: '512MiB', timeoutSeconds: 300 },
  async (request) => {
    const db = getFirestore();
    try {
      await assertDeveloper(db, request);

      const [stationsSnap, eventsSnap, progressSnap] = await Promise.all([
        db.collection('stations').select('points', 'projectId').get(),
        db.collection('events').select('points', 'projectId').get(),
        db
          .collection('user_progress')
          .select('completedStations', 'completedEvents', 'name')
          .get(),
      ]);

      const DEFAULT_PROJECT_ID = 'nagyvazsony';
      const projectOf = (d) =>
        typeof d?.projectId === 'string' && d.projectId.trim()
          ? d.projectId
          : DEFAULT_PROJECT_ID;

      // targetId -> { project, points }
      const targets = new Map();
      for (const d of stationsSnap.docs) {
        const data = d.data();
        targets.set(d.id, {
          project: projectOf(data),
          points: Number(data.points) || 10,
          kind: 'station',
        });
      }
      for (const d of eventsSnap.docs) {
        const data = d.data();
        targets.set(d.id, {
          project: projectOf(data),
          points: Number(data.points) || 10,
          kind: 'event',
        });
      }

      let written = 0;
      const projects = new Set();

      for (const doc of progressSnap.docs) {
        const uid = doc.id;
        const data = doc.data();
        const completed = [
          ...(Array.isArray(data.completedStations) ? data.completedStations : []),
          ...(Array.isArray(data.completedEvents) ? data.completedEvents : []),
        ];

        // Településenkénti összegzés ehhez a felhasználóhoz.
        const byProject = new Map();
        for (const id of completed) {
          const t = targets.get(id);
          if (!t) continue;
          const acc =
            byProject.get(t.project) ?? { points: 0, stations: 0, events: 0 };
          acc.points += t.points;
          if (t.kind === 'station') acc.stations += 1;
          else acc.events += 1;
          byProject.set(t.project, acc);
        }
        if (byProject.size === 0) continue;

        let displayName = String(data.name ?? '').trim();
        if (!displayName) {
          const userSnap = await db.collection('users').doc(uid).get();
          const user = userSnap.exists ? userSnap.data() : {};
          displayName = String(user.displayName ?? user.name ?? 'Felhasználó');
        }

        for (const [projectId, acc] of byProject) {
          projects.add(projectId);
          await db
            .collection('leaderboards')
            .doc(projectId)
            .collection('entries')
            .doc(uid)
            .set(
              {
                uid,
                projectId,
                displayName,
                points: acc.points,
                completedStationsCount: acc.stations,
                completedEventsCount: acc.events,
                updatedAt: FieldValue.serverTimestamp(),
              },
              { merge: true },
            );
          written += 1;
        }
      }

      logger.info('Ranglista feltöltve', { written, projects: [...projects] });
      return { ok: true, written, projects: [...projects] };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      logger.error('seedProjectLeaderboards failed', {
        message: err?.message,
        stack: err?.stack,
      });
      throw new HttpsError('internal', 'A ranglista feltöltése nem sikerült.', {
        reason: String(err?.message ?? err),
      });
    }
  },
);

// Admin-only viselkedési analitika: túra-tölcsér (résztvevők → befejezők) és
// állomás-népszerűség. A számítás szerveroldalon, Admin SDK jogosultsággal fut,
// így a kliensnek nem kell letöltenie az összes user_progress dokumentumot.
// Az aggregáció tiszta függvénye a lib/analytics-core.js-ben tesztelt.
export const tripAnalytics = onCall(
  { region: 'europe-west1', memory: '512MiB', timeoutSeconds: 120 },
  async (request) => {
    try {
      const db = getFirestore();
      // Az admin-ellenőrzés is a try-on belül van, hogy egy váratlan hiba is
      // strukturált (reason-nel ellátott) választ adjon a csupasz "internal"
      // helyett – a szándékos jogosultsági hibák viszont változatlanul mennek.
      await assertAdmin(db, request);

      // Csak a szükséges mezőket olvassuk (kevesebb memória, gyorsabb) – a nagy
      // szöveges/tartalom-mezők nem kerülnek be.
      const [tripsSnap, stationsSnap, progressSnap] = await Promise.all([
        db.collection('trips').select('name', 'projectId').get(),
        db.collection('stations').select('name', 'tripId', 'tripIds', 'projectId').get(),
        db
          .collection('user_progress')
          .select('completedStations', 'completedTripIds', 'completedStationsAt')
          .get(),
      ]);

      const allTrips = tripsSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
      const allStations = stationsSnap.docs.map((d) => ({ id: d.id, ...d.data() }));

      // Település-szűrés: a hiányzó projectId az alapértelmezett településhez
      // tartozik. A 'all' (csak developernek van értelme) az összesített nézet.
      const DEFAULT_PROJECT_ID = 'nagyvazsony';
      const projectOf = (d) =>
        typeof d?.projectId === 'string' && d.projectId.trim()
          ? d.projectId
          : DEFAULT_PROJECT_ID;
      const requested = String(request.data?.projectId ?? '').trim();
      const scopeAll = requested === '' || requested === 'all';
      const trips = scopeAll
        ? allTrips
        : allTrips.filter((t) => projectOf(t) === requested);
      const stations = scopeAll
        ? allStations
        : allStations.filter((st) => projectOf(st) === requested);
      const progressDocs = progressSnap.docs.map((d) => {
        const data = d.data();
        // A Firestore Timestamp-eket epoch-millisec-re konvertáljuk, hogy a
        // tiszta analytics-core szerializálható számokkal dolgozhasson.
        const rawAt = data.completedStationsAt;
        let completedStationsAt;
        if (rawAt && typeof rawAt === 'object' && !Array.isArray(rawAt)) {
          completedStationsAt = {};
          for (const [sid, value] of Object.entries(rawAt)) {
            if (value && typeof value.toMillis === 'function') {
              completedStationsAt[sid] = value.toMillis();
            } else if (typeof value === 'number') {
              completedStationsAt[sid] = value;
            }
          }
        }
        return {
          completedStations: data.completedStations,
          completedTripIds: data.completedTripIds,
          completedStationsAt,
        };
      });

      return {
        generatedAt: new Date().toISOString(),
        projectId: scopeAll ? 'all' : requested,
        ...computeTripAnalytics({ trips, stations, progressDocs }),
      };
    } catch (err) {
      // A szándékos HttpsError-t (permission-denied, unauthenticated) érintetlenül
      // továbbengedjük – a kliens így a helyes kódot kapja.
      if (err instanceof HttpsError) throw err;
      logger.error('tripAnalytics failed', {
        message: err?.message,
        stack: err?.stack,
      });
      // Admin-only függvény, így a valódi ok átadható a felületnek a diagnózishoz.
      throw new HttpsError('internal', 'Az analitika számítása nem sikerült.', {
        reason: String(err?.message ?? err),
      });
    }
  },
);

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
