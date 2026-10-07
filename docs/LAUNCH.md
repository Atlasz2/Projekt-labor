# Indulási ellenőrzőlista

A rendszer minden indulás előtti eleme elkészült és tesztelt; ez a lista az
**éles üzembe állítás** lépéseit rögzíti, a helyes sorrendben. A sorrend nem
felcserélhető: minden lépés az előzőre épít, és mindegyik visszafordítható
állapotból indul.

> Jelenlegi állapot (2026. október): a függvények, a Firestore-szabályok, az
> indexek és a Storage-szabályok a migráció **előtti** állapotban élesek; a
> mobil csak a tesztelői körben (App Distribution) érhető el; az admin felület
> nincs közzétéve.

## 0. Előfeltételek

- [ ] Firebase CLI bejelentkezve, a `projekt-labor-a4b1c` projekthez jogosult fiókkal.
- [ ] Szolgáltatásfiók-kulcs a migrációhoz (`GOOGLE_APPLICATION_CREDENTIALS`), csak helyben, a tárolón kívül.
- [ ] Friss biztonsági mentés: `gcloud firestore export gs://<bucket>/backup-<dátum>`.
- [ ] Minden teszt zöld: `npm run functions:test`, `npm run admin:test`, `npm run rules:test`, `npm run mobile:test`.

## 1. Az adatkezelő adatai (GDPR)

- [ ] A mobil kiadási buildjébe az adatkezelő neve és elérhetősége:
  `--dart-define=PRIVACY_CONTROLLER="<név, cím>" --dart-define=PRIVACY_EMAIL=<cím>`
  (enélkül a tájékoztató nem nevezi meg az adatkezelőt).
- [ ] Az admin felületen kitöltött „Elérhetőségek” (a mobil ellenőrizetlen
  alapértéket nem mutat).
- [ ] A Play Áruház adatbiztonsági űrlapja a `PrivacyScreen` tartalmával összhangban.

## 2. QR-kódok megerősítése (T7)

A cél: a kódok értéke csak a privát `qr_codes` leképezésben éljen, a nyilvános
dokumentum csak a lenyomatot (`qrHash`) tárolja, és a kitalálható kódok (a
dokumentum-azonosítóval egyező, rövid vagy ütköző kódok) újakat kapjanak.

1. [ ] Próbafuttatás – csak olvas, és listát készít:
   ```bash
   cd functions && node scripts/harden-qr-codes.mjs
   ```
2. [ ] A `qr-ujranyomtatas-<dátum>.csv` átnézése: ezek a matricák új kódot kapnak.
3. [ ] Végrehajtás: `node scripts/harden-qr-codes.mjs --apply`
4. [ ] Az új matricák kinyomtatása az admin felületről (állomás → Nyomtatás / túra → Összes QR), és kihelyezése.

## 3. Szerveroldal élesítése

1. [ ] `functions/.env.projekt-labor-a4b1c`: `QR_LEGACY_FALLBACK=false`
   (a kód ezután csak a privát leképezésből oldható fel).
2. [ ] Függvények: `firebase deploy --only functions`
3. [ ] Szabályok és indexek: `firebase deploy --only firestore:rules,firestore:indexes,storage`
   (a lezárt `qrCode`-tilalom és a QR-leképezés tenant-izolációja csak a 2. lépés után élesíthető).
4. [ ] Füstteszt egy tesztfiókkal: egy állomás beolvasása (pont, ranglista),
   egy rossz kód (`found: false`), egy `requireLocation` állomás pozíció nélkül (elutasítás).

**Visszalépés:** `QR_LEGACY_FALLBACK=true` és a függvények újratelepítése; a
szabályok az előző verzióra a Firebase-konzol „Rules” előzményéből állíthatók vissza.

## 4. Admin felület közzététele

- [ ] Tároló-titkok: `FIREBASE_SERVICE_ACCOUNT` és a `VITE_*` értékek.
- [ ] GitHub Actions → „Admin – telepítés (Firebase Hosting)” → Run workflow,
  megerősítés: `ELESITES`. A munkafolyamat lintel, tesztel, buildel és telepít.
- [ ] A Firebase Authentication „Authorized domains” listájában a hosting-domain.
- [ ] A Google Maps API-kulcs HTTP-referrer korlátozása a hosting-domainre.

> Figyelem: a `firebase deploy` paraméter nélkül a hostingot is telepíti –
> mindig `--only`-val telepíts.

## 5. Mobil kiadás és App Check

1. [ ] Kiadási build (`flutter build appbundle --release` a fenti `--dart-define`-okkal),
   feltöltés a Play Console belső tesztcsatornájára.
2. [ ] App Check: a Firebase-konzolon az Android-app regisztrálása Play Integrity
   szolgáltatóval (az App Signing SHA-256 ujjlenyomattal).
3. [ ] A belső tesztcsatornáról telepített appal a naplóban ellenőrizni, hogy a
   hívások érvényes tokennel érkeznek (nincs „Mobil hívás App Check-token nélkül”
   figyelmeztetés).
4. [ ] `functions/.env.projekt-labor-a4b1c`: `ENFORCE_APP_CHECK=true`, majd
   `firebase deploy --only functions`.
5. [ ] Nyilvános kiadás a Play Áruházban.

**Visszalépés:** `ENFORCE_APP_CHECK=false` és a függvények újratelepítése.

## 6. Az indulás után

- [ ] Crashlytics és a függvénynaplók figyelése az első napokban.
- [ ] A `requireLocation` bekapcsolása azoknál az állomásoknál, ahol a helyszíni
  jelenlét fontos (admin → állomás szerkesztése).
- [ ] Terepi ellenőrzés: a 150 m-es sugár megfelel-e minden állomásnál (szükség
  esetén állomásonkénti `radius`).
