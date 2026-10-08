// A redeemQr hívható függvény magja. Szándékosan nem importál semmit a
// firebase-admin-ból: a db-t és a FieldValue-t az index.js injektálja, így a
// tesztek egy in-memory Firestore-stubbal futtathatják (lásd test/).
//
// A pontjóváírás itt, Admin SDK jogosultsággal történik — a kliens csak a
// nyers QR-kódot küldi be, ezért a Firestore rules a user_progress kliens-
// oldali írását teljesen lezárhatja (lásd docs/SERVER_VALIDATION.md).

import { stationTripIds } from './station-trips-core.js';

/** A QR-kód → cél leképezés dokumentum-azonosítója. A kódot URI-kódoljuk,
 *  hogy '/' és egyéb, dokumentum-útvonalban tiltott karakterek se okozzanak
 *  gondot. Az admin oldali qrMapping util ugyanígy képez azonosítót. */
export function qrMappingDocId(code) {
  return encodeURIComponent(code);
}

// White-label: egy dokumentum települése. A mező HIÁNYA az alapértelmezett
// települést jelenti (a még nem migrált, régi tartalom is oda tartozik) –
// ugyanaz a szabály, mint az admin és a mobil oldalon.
const DEFAULT_PROJECT_ID = 'nagyvazsony';

function projectOf(data) {
  const value = data?.projectId;
  return typeof value === 'string' && value.trim() !== ''
    ? value
    : DEFAULT_PROJECT_ID;
}

/** A beolvasott kód feloldása állomásra vagy eseményre.
 *
 * Az egyetlen hiteles út a privát `qr_codes` leképező kollekció. A régi
 * keresés (nyilvános qrCode mező, majd dokumentum-azonosító) csak
 * `legacyFallback` mellett fut: a QR-migráció (scripts/harden-qr-codes.mjs)
 * előtti adatokhoz kell, utána ki kell kapcsolni, mert a nyilvános mezőkön át
 * a kódok kigyűjthetők (T7). Lásd docs/LAUNCH.md.
 * @returns {Promise<{kind: 'station'|'event', id: string, data: object}|null>}
 */
async function resolveTarget(db, code, { legacyFallback }) {
  const mapSnap = await db.collection('qr_codes').doc(qrMappingDocId(code)).get();
  if (mapSnap.exists) {
    const mapping = mapSnap.data();
    const kind = mapping.kind === 'event' ? 'event' : 'station';
    const coll = kind === 'event' ? 'events' : 'stations';
    const target = await db.collection(coll).doc(String(mapping.targetId)).get();
    if (target.exists) {
      // A leképezés csak a saját településének célját oldhatja fel: egy más
      // településre „átirányított” kód érvénytelen (a szabályok ezt íráskor is
      // tiltják – ez a mélységi védelem második vonala).
      if (mapping.projectId && mapping.projectId !== projectOf(target.data())) {
        return null;
      }
      return { kind, id: target.id, data: target.data() };
    }
    // A leképezés árva (a cél törölve) — továbbengedjük a fallbackre.
  }

  if (!legacyFallback) return null;

  for (const [coll, kind] of [['stations', 'station'], ['events', 'event']]) {
    const byField = await db
      .collection(coll)
      .where('qrCode', '==', code)
      .limit(1)
      .get();
    if (!byField.empty) {
      const d = byField.docs[0];
      return { kind, id: d.id, data: d.data() };
    }

    if (!code.includes('/')) {
      const byId = await db.collection(coll).doc(code).get();
      if (byId.exists) {
        return { kind, id: byId.id, data: byId.data() };
      }
    }
  }

  return null;
}

function targetPoints(data) {
  const p = Number(data?.points);
  return Number.isFinite(p) ? Math.trunc(p) : 10;
}

/** Alapértelmezett megengedett távolság az állomástól (méter), ha az
 *  állomás nem ad meg saját `radius` mezőt. Bőven a GPS-pontatlanság fölött,
 *  hogy a helyszínen lévő legitim felhasználót ne utasítsa el. */
export const DEFAULT_LOCATION_RADIUS_M = 150;

/** Két WGS84 koordináta közti távolság méterben (Haversine). */
export function haversineMeters(lat1, lng1, lat2, lng2) {
  const R = 6371000; // Föld sugara méterben
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(a)));
}

/** A cél koordinátája `{lat, lng}` vagy null, ha nincs érvényes helye.
 *  A latitude/longitude közvetlen mezőkből VAGY egy beágyazott
 *  location: {latitude, longitude} objektumból olvas. */
function targetLatLng(data) {
  const lat = Number(data?.latitude ?? data?.location?.latitude);
  const lng = Number(data?.longitude ?? data?.location?.longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (lat === 0 && lng === 0) return null; // hiányzó koordináta jelzője
  return { lat, lng };
}

/**
 * Helyszín-ellenőrzés a jóváírás előtt. `null`-t ad, ha a jóváírás mehet
 * (a helyszín rendben, vagy nincs mit ellenőrizni); egyébként a
 * kiutasítás részleteit adja vissza.
 *
 * A helyszínt csak akkor ellenőrizzük, ha a célnak van koordinátája ÉS a
 * kliens beküldött pozíciót. Pozíció nélkül átengedjük (régi kliensek,
 * GPS-mentes eszközök) — a védelem a beküldött pozíciót vizsgálja, nem a
 * hiányát. Ezt a korlátot a szakdolgozat dokumentálja.
 */
export function checkLocation(targetData, location) {
  const target = targetLatLng(targetData);
  if (!target) return null;
  if (
    !location ||
    !Number.isFinite(Number(location.lat)) ||
    !Number.isFinite(Number(location.lng))
  ) {
    return null;
  }

  const distance = haversineMeters(
    Number(location.lat),
    Number(location.lng),
    target.lat,
    target.lng,
  );
  const radius = Number(targetData?.radius);
  const threshold =
    Number.isFinite(radius) && radius > 0 ? radius : DEFAULT_LOCATION_RADIUS_M;

  if (distance > threshold) {
    return { distance: Math.round(distance), threshold };
  }
  return null;
}

/** Túra-teljesítés detektálása állomás-jóváírás után: a beolvasott állomás
 *  MOST MÁR TÖBB túrának is megállója lehet, ezért mindegyiket
 *  megvizsgáljuk – ha valamelyiknek minden állomása megvan, az a túra
 *  bekerül a completedTripIds-be. A bővített listát adja vissza. */
async function detectTripCompletion({
  db,
  FieldValue,
  uid,
  kind,
  targetData,
  completedStations,
  completedTripIds,
}) {
  const result = [...completedTripIds];
  if (kind !== 'station') return result;

  const candidateTripIds = stationTripIds(targetData).filter(
    (tripId) => !result.includes(tripId),
  );
  if (candidateTripIds.length === 0) return result;

  const newlyCompleted = [];
  for (const tripId of candidateTripIds) {
    // Csak létező, az állomás településéhez tartozó túra teljesülhet – egy
    // törölt túrára mutató, ottmaradt hivatkozás nem ér jutalmat.
    const tripSnap = await db.collection('trips').doc(tripId).get();
    if (!tripSnap.exists || projectOf(tripSnap.data()) !== projectOf(targetData)) {
      continue;
    }
    // Két lekérdezés: az új `tripIds` tömbre (array-contains, egy állomás
    // több túrának is megállója lehet) ÉS a régi egyszeres `tripId` mezőre
    // (amíg a migráció, scripts/migrate-station-trip-memberships.mjs, nem
    // futott le mindenhol) – összefésülve, doksinkénti dedup-pal.
    const [byArray, byLegacy] = await Promise.all([
      db.collection('stations').where('tripIds', 'array-contains', tripId).get(),
      db.collection('stations').where('tripId', '==', tripId).get(),
    ]);
    const tripStationDocs = new Map();
    for (const d of [...byArray.docs, ...byLegacy.docs]) tripStationDocs.set(d.id, d);
    if (tripStationDocs.size === 0) continue;

    const allDone = [...tripStationDocs.keys()].every((id) =>
      completedStations.includes(id),
    );
    if (allDone) newlyCompleted.push(tripId);
  }

  if (newlyCompleted.length === 0) return result;

  result.push(...newlyCompleted);
  await db.collection('user_progress').doc(uid).update({
    completedTripIds: FieldValue.arrayUnion(...newlyCompleted),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return result;
}

async function checkAchievements({ db, FieldValue, uid, counts, projectId }) {
  const [achSnap, unlockedSnap] = await Promise.all([
    db.collection('achievements').get(),
    db.collection('user_progress').doc(uid).collection('unlocked_achievements').get(),
  ]);
  const alreadyUnlocked = new Set(unlockedSnap.docs.map((d) => d.id));

  const newlyUnlocked = [];
  const batch = db.batch();

  for (const doc of achSnap.docs) {
    if (alreadyUnlocked.has(doc.id)) continue;
    const ach = doc.data();
    // Más település jutalma itt nem oldódhat fel (white-label).
    if (projectOf(ach) !== projectId) continue;
    const type = String(ach.conditionType ?? '');
    const target = Number(ach.conditionValue) || 1;

    let met = false;
    if (type === 'station_count') met = counts.stations >= target;
    else if (type === 'event_count') met = counts.events >= target;
    else if (type === 'qr_count') met = counts.stations + counts.events >= target;
    else if (type === 'points_threshold') met = counts.points >= target;
    else if (type === 'trip_complete') met = counts.trips >= target;
    else if (type === 'top_n') {
      // A leaderboard-szinkron ELŐBB fut, így a saját friss pontszámunkkal
      // versenyzünk. Holtversenynél a limit(N) találati sorrendje dönt.
      // A település SAJÁT ranglistáján versenyzünk – egy másik falu
      // játékosai nem szorítanak ki innen senkit.
      const top = await db
        .collection('leaderboards')
        .doc(projectId)
        .collection('entries')
        .orderBy('points', 'desc')
        .limit(target)
        .get();
      met = top.docs.some((d) => d.id === uid);
    }

    if (met) {
      batch.set(
        db.collection('user_progress').doc(uid).collection('unlocked_achievements').doc(doc.id),
        { unlockedAt: FieldValue.serverTimestamp() },
      );
      // Admin SDK-val futunk, így a kliensből tiltott globális statisztika
      // is frissíthető.
      batch.update(db.collection('achievements').doc(doc.id), {
        unlockedCount: FieldValue.increment(1),
      });
      newlyUnlocked.push({ id: doc.id, ...ach });
    }
  }

  if (newlyUnlocked.length > 0) {
    const first = newlyUnlocked[0];
    batch.set(
      db.collection('user_progress').doc(uid),
      {
        pendingAchievementBanner: {
          title: String(first.name ?? 'Jutalom feloldva!'),
          subtitle:
            newlyUnlocked.length === 1
              ? String(first.description ?? '')
              : `${newlyUnlocked.length} új jutalom feloldva!`,
        },
      },
      { merge: true },
    );
    await batch.commit();
  }

  return newlyUnlocked;
}

const arrayLength = (value) => (Array.isArray(value) ? value.length : 0);

/**
 * A jutalmak utólagos egyeztetése (reconcile) a hívó tárolt haladása alapján.
 *
 * Egy jutalom beolvasás nélkül is teljesülhet: utólag létrehozott jutalom,
 * top_n rangváltozás más felhasználók miatt, vagy egy korábban elbukott
 * feloldás. A kliens ezt korábban maga írta az unlocked_achievements
 * alkollekcióba; a szerveroldali változat miatt ez az írás a kliens elől
 * lezárható (lásd firestore.rules).
 */
export async function reconcileAchievementsCore({ db, FieldValue, uid, projectId }) {
  const snap = await db.collection('user_progress').doc(uid).get();
  if (!snap.exists) return { newAchievements: [] };

  const data = snap.data() ?? {};
  const counts = {
    stations: arrayLength(data.completedStations),
    events: arrayLength(data.completedEvents),
    trips: arrayLength(data.completedTripIds),
    points: Number(data.totalPoints) || 0,
  };
  const project =
    typeof projectId === 'string' && projectId.trim() !== ''
      ? projectId.trim()
      : DEFAULT_PROJECT_ID;

  const newAchievements = await checkAchievements({
    db,
    FieldValue,
    uid,
    counts,
    projectId: project,
  });
  return { newAchievements };
}

/** A projektenkénti ranglista bejegyzésének útvonala. Alkollekció, hogy a
 *  rangsorolás (orderBy points) összetett index nélkül működjön, és egy
 *  település ranglistája ne keveredjen a többiével. */
export function leaderboardEntryRef(db, projectId, uid) {
  return db
    .collection('leaderboards')
    .doc(projectId)
    .collection('entries')
    .doc(uid);
}

/** A ranglista-bejegyzések írása a jóváírási tranzakción belül: így a pont
 *  és a ranglista csak együtt változhat (egy félbeszakadt kérés után sem
 *  maradhat el a ranglista frissítése, mert a tranzakció egésze ismétlődik). */
function writeLeaderboards(tx, {
  db,
  FieldValue,
  uid,
  displayName,
  points,
  counts,
  projectId,
  awardedPoints,
  kind,
}) {
  // Régi, globális ranglista – megmarad, hogy a még nem frissített
  // appverziók se törjenek el (átmeneti kettős írás). Abszolút értékek.
  tx.set(
    db.collection('public_leaderboard').doc(uid),
    {
      displayName,
      points,
      completedStationsCount: counts.stations,
      completedEventsCount: counts.events,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  // Projektenkénti ranglista: a pontokat NÖVELJÜK, mert itt csak az adott
  // településen szerzett pont számít (a globális totalPoints nem jó erre).
  // A tranzakció garantálja, hogy egy jóváírás pontosan egyszer növel.
  tx.set(
    leaderboardEntryRef(db, projectId, uid),
    {
      uid,
      displayName,
      projectId,
      points: FieldValue.increment(awardedPoints),
      completedStationsCount: FieldValue.increment(kind === 'station' ? 1 : 0),
      completedEventsCount: FieldValue.increment(kind === 'event' ? 1 : 0),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

/** Kell-e pozíció a cél beváltásához: minden helyhez kötött (koordinátával
 *  rendelkező) célnál igen, hacsak az admin kifejezetten nem engedi a pozíció
 *  nélküli beváltást (requireLocation === false, pl. akadálymentes állomás).
 *  A koordináta nélküli célok (helyhez nem kötött rendezvények) mentesek. */
export function requiresLocation(targetData) {
  return targetLatLng(targetData) != null && targetData?.requireLocation !== false;
}

/** Érvényes-e a beolvasáskori pozíció (mindkét koordináta véges szám). */
function hasValidLocation(location) {
  return (
    location != null &&
    Number.isFinite(Number(location.lat)) &&
    Number.isFinite(Number(location.lng))
  );
}

/**
 * A teljes jóváírási folyamat egy beolvasott kódra.
 *
 * Ismeretlen kódra `{ found: false }`-t ad vissza (nem dob), hogy a kliens
 * megbízhatóan meg tudja különböztetni a "nincs ilyen kód" esetet a
 * "függvény nincs deployolva" hibától.
 *
 * A `location` opcionális `{lat, lng}` — a beolvasás pillanatában rögzített
 * eszközpozíció. Ha a cél helyhez kötött és a pozíció túl messze van, a
 * jóváírás elmarad: `{ found: true, rejected: 'out_of_range', ... }`.
 */
export async function redeemQrCore({
  db,
  FieldValue,
  uid,
  code,
  location,
  projectId,
  legacyFallback = true,
}) {
  const target = await resolveTarget(db, code, { legacyFallback });
  if (!target) {
    return { found: false };
  }

  // Több-települési (white-label) védelem: egy másik település QR-kódja nem
  // írható jóvá ebben a kiadásban. A kliens elhagyhatja a projectId-t (régi
  // appverzió) – ilyenkor nem szűrünk, hogy ne törjünk meglévő telepítéseket.
  const callerProject =
    typeof projectId === 'string' && projectId.trim() !== ''
      ? projectId.trim()
      : null;
  if (callerProject && projectOf(target.data) !== callerProject) {
    return {
      found: true,
      rejected: 'wrong_project',
      kind: target.kind,
      targetId: target.id,
      target: target.data,
      targetProjectId: projectOf(target.data),
    };
  }

  // Helyhez kötött célnál a pozíció nélküli kérés (kikapcsolt helymeghatározás,
  // módosított kliens) nem kap pontot – különben a GPS kikapcsolásával a
  // helyszín-ellenőrzés megkerülhető volna. Az admin állomásonként
  // engedélyezheti a pozíció nélküli beváltást (requireLocation: false).
  if (requiresLocation(target.data) && !hasValidLocation(location)) {
    return {
      found: true,
      rejected: 'location_required',
      kind: target.kind,
      targetId: target.id,
      target: target.data,
    };
  }

  const locationReject = checkLocation(target.data, location);
  if (locationReject) {
    return {
      found: true,
      rejected: 'out_of_range',
      kind: target.kind,
      targetId: target.id,
      target: target.data,
      distance: locationReject.distance,
      threshold: locationReject.threshold,
    };
  }

  const points = targetPoints(target.data);
  const targetProject = projectOf(target.data);
  const progressRef = db.collection('user_progress').doc(uid);
  const userRef = db.collection('users').doc(uid);
  const listField =
    target.kind === 'station' ? 'completedStations' : 'completedEvents';

  const outcome = await db.runTransaction(async (tx) => {
    const snap = await tx.get(progressRef);
    const data = snap.exists ? snap.data() : null;
    // A ranglistán megjelenő név – minden olvasás az írások előtt történik.
    let displayName = String(data?.name ?? '').trim();
    if (!displayName) {
      const userSnap = await tx.get(userRef);
      const user = userSnap.exists ? userSnap.data() : {};
      displayName = String(user?.displayName ?? user?.name ?? 'Felhasználó');
    }

    const completedStations = [...(data?.completedStations ?? [])];
    const completedEvents = [...(data?.completedEvents ?? [])];
    const currentPoints = Number(data?.totalPoints) || 0;

    const list =
      target.kind === 'station' ? completedStations : completedEvents;
    const alreadyDone = list.includes(target.id);

    if (!alreadyDone) {
      list.push(target.id);
      // Állomás teljesítésekor rögzítjük a beolvasás időpontját is
      // (completedStationsAt map), hogy az analitika kiszámíthassa az egyes
      // túrák átlagos befejezési idejét (első → utolsó állomás). Eseményekre
      // nem tároljuk (a tölcsér-analitika állomás-alapú).
      const isStation = target.kind === 'station';
      if (!snap.exists) {
        tx.set(progressRef, {
          totalPoints: points,
          completedStations,
          completedEvents,
          completedTripIds: [],
          ...(isStation
            ? {
                completedStationsAt: {
                  [target.id]: FieldValue.serverTimestamp(),
                },
              }
            : {}),
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      } else {
        const update = {
          [listField]: FieldValue.arrayUnion(target.id),
          totalPoints: FieldValue.increment(points),
          updatedAt: FieldValue.serverTimestamp(),
        };
        if (isStation) {
          update[`completedStationsAt.${target.id}`] =
            FieldValue.serverTimestamp();
        }
        tx.update(progressRef, update);
      }

      writeLeaderboards(tx, {
        db,
        FieldValue,
        uid,
        displayName,
        points: currentPoints + points,
        counts: {
          stations: completedStations.length,
          events: completedEvents.length,
        },
        projectId: targetProject,
        awardedPoints: points,
        kind: target.kind,
      });
    }

    return {
      alreadyDone,
      updatedPoints: alreadyDone ? currentPoints : currentPoints + points,
      completedStations,
      completedEvents,
      progressData: data ?? {},
    };
  });

  // A túra-teljesítés és a jutalmak kiértékelése idempotens, ezért ismételt
  // beolvasáskor is lefut: ha egy korábbi kérés a jóváírás után megszakadt,
  // az újrapróbálkozás (pl. az offline sorból) pótolja a kimaradt lépést.
  const completedTripIds = await detectTripCompletion({
    db,
    FieldValue,
    uid,
    kind: target.kind,
    targetData: target.data,
    completedStations: outcome.completedStations,
    completedTripIds: [...(outcome.progressData.completedTripIds ?? [])],
  });

  const counts = {
    stations: outcome.completedStations.length,
    events: outcome.completedEvents.length,
    trips: completedTripIds.length,
    points: outcome.updatedPoints,
  };

  // A ranglista a tranzakcióban már frissült, így a top_n feltétel a friss
  // pontszámmal értékelődik ki.
  const newAchievements = await checkAchievements({
    db,
    FieldValue,
    uid,
    counts,
    projectId: targetProject,
  });

  return {
    found: true,
    kind: target.kind,
    targetId: target.id,
    target: target.data,
    alreadyDone: outcome.alreadyDone,
    newAchievements,
    updatedPoints: outcome.updatedPoints,
    completedStationsCount: counts.stations,
    completedEventsCount: counts.events,
  };
}
