// Az ELŐKÉSZÍTETT firestore.lockdown.rules tesztjei — a szabálykészlet még
// nincs élesítve (lásd docs/SERVER_VALIDATION.md deploy-sorrend), de itt már
// bizonyítjuk, hogy élesítés után a pont-felfújási vektor is zárul.

import { test, before, after } from 'node:test';
import { readFileSync } from 'node:fs';

import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { deleteField, doc, setDoc, updateDoc } from 'firebase/firestore';

let env;

const ALICE = 'alice-uid';

function aliceDb() {
  return env.authenticatedContext(ALICE, { email: 'alice@example.com' }).firestore();
}

async function seed(path, data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), path), data);
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-rules-lockdown',
    firestore: { rules: readFileSync('../firestore.lockdown.rules', 'utf8') },
  });
});

after(async () => {
  await env.cleanup();
});

test('LOCKDOWN: a pontnövelési vektor zárva — update totalPoints tiltva', async () => {
  await seed(`user_progress/${ALICE}`, { totalPoints: 10, completedStations: [] });
  await assertFails(
    updateDoc(doc(aliceDb(), `user_progress/${ALICE}`), { totalPoints: 999999 }),
  );
});

test('LOCKDOWN: completedStations kliensoldali bővítése tiltva', async () => {
  await seed(`user_progress/${ALICE}`, {
    totalPoints: 10,
    completedStations: ['st1'],
  });
  await assertFails(
    updateDoc(doc(aliceDb(), `user_progress/${ALICE}`), {
      completedStations: ['st1', 'st2'],
    }),
  );
});

test('LOCKDOWN: nullázott regisztrációs create továbbra is engedett', async () => {
  await env.clearFirestore();
  await assertSucceeds(
    setDoc(doc(aliceDb(), `user_progress/${ALICE}`), {
      name: 'Alice',
      totalPoints: 0,
      completedStations: [],
      completedEvents: [],
      completedTripIds: [],
    }),
  );
});

test('LOCKDOWN: hamis kezdőértékes create továbbra is tiltva', async () => {
  await env.clearFirestore();
  await assertFails(
    setDoc(doc(aliceDb(), `user_progress/${ALICE}`), {
      totalPoints: 500,
      completedStations: [],
      completedEvents: [],
    }),
  );
});

test('LOCKDOWN: a banner-nyugtázás (egyetlen megengedett kliens-update) megy', async () => {
  await seed(`user_progress/${ALICE}`, {
    totalPoints: 10,
    pendingAchievementBanner: { title: 'Jutalom!' },
  });
  await assertSucceeds(
    updateDoc(doc(aliceDb(), `user_progress/${ALICE}`), {
      pendingAchievementBanner: deleteField(),
    }),
  );
});

test('LOCKDOWN: banner + pont együttes módosítása tiltva (csempészés kizárva)', async () => {
  await seed(`user_progress/${ALICE}`, {
    totalPoints: 10,
    pendingAchievementBanner: { title: 'Jutalom!' },
  });
  await assertFails(
    updateDoc(doc(aliceDb(), `user_progress/${ALICE}`), {
      pendingAchievementBanner: deleteField(),
      totalPoints: 999999,
    }),
  );
});

test('LOCKDOWN: unlocked_achievements kliensről nem írható', async () => {
  await seed(`user_progress/${ALICE}`, { totalPoints: 0 });
  await assertFails(
    setDoc(
      doc(aliceDb(), `user_progress/${ALICE}/unlocked_achievements/hamis`),
      { unlockedAt: new Date() },
    ),
  );
});

test('LOCKDOWN: qr_codes enumeráció továbbra is tiltva', async () => {
  await seed('qr_codes/TITKOS', { kind: 'station', targetId: 'st1' });
  await assertFails(
    setDoc(doc(aliceDb(), 'qr_codes/HAMIS'), { kind: 'station', targetId: 'x' }),
  );
});

test('LOCKDOWN: leaderboard kereszt-ellenőrzés változatlanul működik', async () => {
  await seed(`user_progress/${ALICE}`, { totalPoints: 42, completedStations: [] });
  await assertSucceeds(
    setDoc(doc(aliceDb(), `public_leaderboard/${ALICE}`), {
      displayName: 'Alice',
      points: 42,
    }),
  );
  await assertFails(
    setDoc(doc(aliceDb(), `public_leaderboard/${ALICE}`), {
      displayName: 'Alice',
      points: 43,
    }),
  );
});
