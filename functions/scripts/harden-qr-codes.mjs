// Indulás előtti QR-megerősítés (lásd lib/qr-harden-core.js és docs/LAUNCH.md).
//
// Alapértelmezésben PRÓBAFUTTATÁS: csak kiírja, mit tenne, és elkészíti az
// újranyomtatandó matricák listáját – az adatbázist nem módosítja.
//
//   node scripts/harden-qr-codes.mjs            # próbafuttatás
//   node scripts/harden-qr-codes.mjs --apply    # végrehajtás
//
// Hitelesítés: GOOGLE_APPLICATION_CREDENTIALS=<service-account.json>, vagy
// emulátor ellen FIRESTORE_EMULATOR_HOST=localhost:8080.
//
// A végrehajtás után a functions/.env.<projekt> fájlban QR_LEGACY_FALLBACK=false,
// majd a függvények és a szabályok telepítése következik.

import { writeFileSync } from 'node:fs';

import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

import { applyQrHardening, planQrHardening, reprintCsv } from '../lib/qr-harden-core.js';

const apply = process.argv.includes('--apply');

initializeApp({
  credential: applicationDefault(),
  projectId: process.env.GCLOUD_PROJECT ?? 'projekt-labor-a4b1c',
});
const db = getFirestore();

const plan = await planQrHardening(db);
const reprint = plan.items.filter((i) => i.reprint);

console.log(`Elemek: ${plan.items.length} (állomás + rendezvény)`);
console.log(`Új kódot kap (matricát újra kell nyomtatni): ${reprint.length}`);
for (const i of reprint) {
  console.log(`  - [${i.projectId}] ${i.kind} "${i.name}" (${i.id}): ${i.reason}`);
}
console.log(`Törlendő elavult/árva leképezés: ${plan.staleMappings.length}`);

const csvPath = `qr-ujranyomtatas-${new Date().toISOString().slice(0, 10)}.csv`;
writeFileSync(csvPath, `﻿${reprintCsv(plan)}\n`, 'utf8');
console.log(`Újranyomtatási lista: ${csvPath}`);

if (!apply) {
  console.log('\nPRÓBAFUTTATÁS – semmi nem módosult. Végrehajtás: --apply');
  process.exit(0);
}

const { written } = await applyQrHardening(db, FieldValue, plan);
console.log(`\nKész: ${written} írási művelet.`);
console.log('Következő lépés: QR_LEGACY_FALLBACK=false, majd telepítés (docs/LAUNCH.md).');
