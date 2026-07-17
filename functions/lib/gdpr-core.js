// GDPR adatjogok magja: adathordozhatóság (20. cikk — export) és a törléshez
// való jog (17. cikk — "elfeledtetés"). A db-t és az Auth-törlő callbacket az
// index.js injektálja, így a tesztek stubbal futtathatják.
//
// Mindkét művelet KIZÁRÓLAG a hívó saját (uid) adatain dolgozik — a callable
// réteg garantálja, hogy az uid a hitelesített felhasználóé.

/** A felhasználóhoz tartozó dokumentumhelyek egy helyen, hogy az export és a
 *  törlés garantáltan ugyanazt a kört fedje. */
const USER_PROGRESS_SUBCOLLECTIONS = [
  'completed_stations',
  'completed_events',
  'unlocked_achievements',
];

function snapToObject(snap) {
  return snap.exists ? snap.data() : null;
}

async function readSubcollection(db, uid, name) {
  const snap = await db
    .collection('user_progress')
    .doc(uid)
    .collection(name)
    .get();
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}

/**
 * A felhasználó összes tárolt adatának összegyűjtése egy JSON-barát objektumba.
 * Firestore Timestamp-ek a callable szerializáláskor ISO-má alakulnak a
 * kliens oldalon (a payload map-ként utazik).
 */
export async function collectUserData({ db, uid }) {
  const [userSnap, progressSnap, leaderboardSnap] = await Promise.all([
    db.collection('users').doc(uid).get(),
    db.collection('user_progress').doc(uid).get(),
    db.collection('public_leaderboard').doc(uid).get(),
  ]);

  const subcollections = {};
  for (const name of USER_PROGRESS_SUBCOLLECTIONS) {
    subcollections[name] = await readSubcollection(db, uid, name);
  }

  const [usernamesSnap, bugReportsSnap] = await Promise.all([
    db.collection('usernames').where('uid', '==', uid).get(),
    db.collection('bug_reports').where('reported_by.user_id', '==', uid).get(),
  ]);

  return {
    exportedAt: new Date().toISOString(),
    uid,
    profile: snapToObject(userSnap),
    progress: snapToObject(progressSnap),
    progressDetails: subcollections,
    leaderboardEntry: snapToObject(leaderboardSnap),
    reservedUsernames: usernamesSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
    bugReports: bugReportsSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
  };
}

/**
 * A felhasználó összes adatának törlése ("right to be forgotten").
 *
 * A hibabejelentéseket nem töröljük, hanem ANONIMIZÁLJUK: az üzemeltetési
 * értékük (a hiba leírása) megmarad, de a személyes azonosítók lenullázódnak —
 * a GDPR ezt megengedi, mert anonim adat már nem személyes adat.
 *
 * @param {object} deps
 * @param {object} deps.db - Firestore Admin-példány
 * @param {string} deps.uid
 * @param {(uid: string) => Promise<void>} [deps.deleteAuthUser]
 *   - az Auth-fiók törlése; injektálható a tesztekhez
 * @returns {Promise<{deleted: string[], anonymizedBugReports: number}>}
 */
export async function deleteUserData({ db, uid, deleteAuthUser }) {
  const deleted = [];
  const batch = db.batch();

  // 1. user_progress alkollekciók
  for (const name of USER_PROGRESS_SUBCOLLECTIONS) {
    const snap = await db
      .collection('user_progress')
      .doc(uid)
      .collection(name)
      .get();
    for (const d of snap.docs) {
      batch.delete(db.collection('user_progress').doc(uid).collection(name).doc(d.id));
      deleted.push(`user_progress/${uid}/${name}/${d.id}`);
    }
  }

  // 2. fő dokumentumok
  for (const [coll, id] of [
    ['user_progress', uid],
    ['users', uid],
    ['public_leaderboard', uid],
  ]) {
    batch.delete(db.collection(coll).doc(id));
    deleted.push(`${coll}/${id}`);
  }

  // 3. foglalt felhasználónevek
  const usernamesSnap = await db
    .collection('usernames')
    .where('uid', '==', uid)
    .get();
  for (const d of usernamesSnap.docs) {
    batch.delete(db.collection('usernames').doc(d.id));
    deleted.push(`usernames/${d.id}`);
  }

  // 4. hibabejelentések anonimizálása (törlés helyett)
  const bugReportsSnap = await db
    .collection('bug_reports')
    .where('reported_by.user_id', '==', uid)
    .get();
  for (const d of bugReportsSnap.docs) {
    batch.update(db.collection('bug_reports').doc(d.id), {
      reported_by: { user_id: '[törölt fiók]', email: null, name: null },
    });
  }

  await batch.commit();

  // 5. Auth-fiók — legutoljára, hogy Firestore-hiba esetén a felhasználó
  // be tudjon lépni és újrapróbálni.
  if (deleteAuthUser) {
    await deleteAuthUser(uid);
  }

  return { deleted, anonymizedBugReports: bugReportsSnap.docs.length };
}
