// A redeemQr hívható függvény magja. Szándékosan nem importál semmit a
// firebase-admin-ból: a db-t és a FieldValue-t az index.js injektálja, így a
// tesztek egy in-memory Firestore-stubbal futtathatják (lásd test/).
//
// A pontjóváírás itt, Admin SDK jogosultsággal történik — a kliens csak a
// nyers QR-kódot küldi be, ezért a Firestore rules a user_progress kliens-
// oldali írását teljesen lezárhatja (lásd docs/SERVER_VALIDATION.md).

/** A QR-kód → cél leképezés dokumentum-azonosítója. A kódot URI-kódoljuk,
 *  hogy '/' és egyéb, dokumentum-útvonalban tiltott karakterek se okozzanak
 *  gondot. Az admin oldali qrMapping util ugyanígy képez azonosítót. */
export function qrMappingDocId(code) {
  return encodeURIComponent(code);
}

/** A beolvasott kód feloldása állomásra vagy eseményre.
 *
 * Elsődleges út a privát `qr_codes` leképező kollekció; amíg a backfill le
 * nem futott, marad a régi keresés: qrCode mező, majd doc-id fallback.
 * @returns {Promise<{kind: 'station'|'event', id: string, data: object}|null>}
 */
async function resolveTarget(db, code) {
  const mapSnap = await db.collection('qr_codes').doc(qrMappingDocId(code)).get();
  if (mapSnap.exists) {
    const mapping = mapSnap.data();
    const kind = mapping.kind === 'event' ? 'event' : 'station';
    const coll = kind === 'event' ? 'events' : 'stations';
    const target = await db.collection(coll).doc(String(mapping.targetId)).get();
    if (target.exists) {
      return { kind, id: target.id, data: target.data() };
    }
    // A leképezés árva (a cél törölve) — továbbengedjük a fallbackre.
  }

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

/** Túra-teljesítés detektálása állomás-jóváírás után: ha a beolvasott
 *  állomás túrájának minden állomása megvan, a túra bekerül a
 *  completedTripIds-be. A bővített listát adja vissza. */
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

  const tripId = String(targetData?.tripId ?? '').trim();
  if (!tripId || result.includes(tripId)) return result;

  const tripStations = await db
    .collection('stations')
    .where('tripId', '==', tripId)
    .get();
  if (tripStations.docs.length === 0) return result;

  const allDone = tripStations.docs.every((d) =>
    completedStations.includes(d.id),
  );
  if (!allDone) return result;

  result.push(tripId);
  await db.collection('user_progress').doc(uid).update({
    completedTripIds: FieldValue.arrayUnion(tripId),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return result;
}

async function checkAchievements({ db, FieldValue, uid, counts }) {
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
      const top = await db
        .collection('public_leaderboard')
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

async function syncLeaderboard({ db, FieldValue, uid, points, counts, progressData }) {
  let displayName = String(progressData?.name ?? '').trim();
  if (!displayName) {
    const userSnap = await db.collection('users').doc(uid).get();
    const user = userSnap.exists ? userSnap.data() : {};
    displayName = String(user.displayName ?? user.name ?? 'Felhasználó');
  }

  await db.collection('public_leaderboard').doc(uid).set(
    {
      displayName,
      points,
      completedStationsCount: counts.stations,
      completedEventsCount: counts.events,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

/**
 * A teljes jóváírási folyamat egy beolvasott kódra.
 *
 * Ismeretlen kódra `{ found: false }`-t ad vissza (nem dob), hogy a kliens
 * megbízhatóan meg tudja különböztetni a "nincs ilyen kód" esetet a
 * "függvény nincs deployolva" hibától.
 */
export async function redeemQrCore({ db, FieldValue, uid, code }) {
  const target = await resolveTarget(db, code);
  if (!target) {
    return { found: false };
  }

  const points = targetPoints(target.data);
  const progressRef = db.collection('user_progress').doc(uid);
  const listField =
    target.kind === 'station' ? 'completedStations' : 'completedEvents';

  const outcome = await db.runTransaction(async (tx) => {
    const snap = await tx.get(progressRef);
    const data = snap.exists ? snap.data() : null;

    const completedStations = [...(data?.completedStations ?? [])];
    const completedEvents = [...(data?.completedEvents ?? [])];
    const currentPoints = Number(data?.totalPoints) || 0;

    const list =
      target.kind === 'station' ? completedStations : completedEvents;
    const alreadyDone = list.includes(target.id);

    if (!alreadyDone) {
      list.push(target.id);
      if (!snap.exists) {
        tx.set(progressRef, {
          totalPoints: points,
          completedStations,
          completedEvents,
          completedTripIds: [],
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      } else {
        tx.update(progressRef, {
          [listField]: FieldValue.arrayUnion(target.id),
          totalPoints: FieldValue.increment(points),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }

    return {
      alreadyDone,
      updatedPoints: alreadyDone ? currentPoints : currentPoints + points,
      completedStations,
      completedEvents,
      progressData: data ?? {},
    };
  });

  let completedTripIds = [...(outcome.progressData.completedTripIds ?? [])];

  let newAchievements = [];
  if (!outcome.alreadyDone) {
    completedTripIds = await detectTripCompletion({
      db,
      FieldValue,
      uid,
      kind: target.kind,
      targetData: target.data,
      completedStations: outcome.completedStations,
      completedTripIds,
    });
  }

  const counts = {
    stations: outcome.completedStations.length,
    events: outcome.completedEvents.length,
    trips: completedTripIds.length,
    points: outcome.updatedPoints,
  };

  if (!outcome.alreadyDone) {
    // Előbb a leaderboard, hogy a top_n feltétel már a friss pontszámmal
    // értékelődjön ki.
    await syncLeaderboard({
      db,
      FieldValue,
      uid,
      points: outcome.updatedPoints,
      counts,
      progressData: outcome.progressData,
    });
    newAchievements = await checkAchievements({ db, FieldValue, uid, counts });
  }

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
