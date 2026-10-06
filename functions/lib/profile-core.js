// A játékos megjelenített nevének módosítása. A név több helyen szerepel
// (névfoglalás, profil, haladás, ranglisták), és a ranglistákat csak a szerver
// írhatja, ezért a módosítás szerveroldalon, egy helyen történik. A db-t, a
// FieldValue-t és a jelszó-frissítőt az index.js injektálja (tesztelhetőség).

import { projectLeaderboardEntries } from './gdpr-core.js';

export const NAME_MIN_LENGTH = 2;
export const NAME_MAX_LENGTH = 40;

/** A névfoglalás kulcsa: kisbetűs, szóköz-tömörített (a mobil is így képzi). */
export const normalizeDisplayName = (value) =>
  String(value ?? '').trim().toLowerCase().replace(/\s+/g, ' ');

/** Az e-mailes visszaállítás jelszava a névből (a mobil AuthService párja). */
export const passwordFromName = (name) => `nvkey:${normalizeDisplayName(name)}`;

export class InvalidNameError extends Error {}
export class NameTakenError extends Error {}

/**
 * @param {object} deps
 * @param {(password: string) => Promise<void>} [deps.updatePassword]
 *   - e-mailhez kötött fióknál a visszaállítási jelszó frissítése
 * @returns {Promise<{displayName: string}>}
 */
export async function renameUserCore({ db, FieldValue, uid, name, updatePassword }) {
  const displayName = String(name ?? '').trim().replace(/\s+/g, ' ');
  if (displayName.length < NAME_MIN_LENGTH || displayName.length > NAME_MAX_LENGTH) {
    throw new InvalidNameError(
      `A név ${NAME_MIN_LENGTH}–${NAME_MAX_LENGTH} karakter hosszú lehet.`,
    );
  }
  if (displayName.includes('/')) {
    throw new InvalidNameError('A név nem tartalmazhat „/” jelet.');
  }
  const normalized = normalizeDisplayName(displayName);

  // Foglalás és profil egy tranzakcióban: két egyidejű kérés nem kaphatja
  // meg ugyanazt a nevet.
  await db.runTransaction(async (tx) => {
    const ref = db.collection('usernames').doc(normalized);
    const snap = await tx.get(ref);
    if (snap.exists && snap.data().uid !== uid) {
      throw new NameTakenError('Ez a név már foglalt.');
    }
    tx.set(ref, {
      uid,
      displayName,
      normalized,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(
      db.collection('users').doc(uid),
      { name: displayName, displayName, updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
  });

  const batch = db.batch();

  // A korábbi név felszabadítása.
  const reserved = await db.collection('usernames').where('uid', '==', uid).get();
  for (const d of reserved.docs) {
    if (d.id !== normalized) batch.delete(db.collection('usernames').doc(d.id));
  }

  const progressRef = db.collection('user_progress').doc(uid);
  if ((await progressRef.get()).exists) {
    batch.set(progressRef, { name: displayName }, { merge: true });
  }
  const globalRef = db.collection('public_leaderboard').doc(uid);
  if ((await globalRef.get()).exists) {
    batch.set(globalRef, { displayName }, { merge: true });
  }
  for (const entry of await projectLeaderboardEntries(db, uid)) {
    batch.set(entry.ref, { displayName }, { merge: true });
  }
  await batch.commit();

  if (updatePassword) {
    await updatePassword(passwordFromName(displayName));
  }
  return { displayName };
}
