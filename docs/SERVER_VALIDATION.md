# Szerveroldali QR-validáció (redeemQr Cloud Function)

## Miért volt rá szükség?

A korábbi architektúrában a pontjóváírást a mobil kliens számolta és írta a
Firestore-ba. A security rules a pontcsökkentést és a hamis kezdőértéket
tiltották, de két támadási vektor nyitva maradt:

1. **Pont-felfújás**: egy módosított kliens (vagy a Firestore REST API-t a
   publikus API-kulccsal hívó szkript) az update-ágon tetszőleges mértékben
   növelhette a saját `user_progress.totalPoints` értékét — a monoton szabály
   csak a csökkentést tiltja.
2. **QR-enumeráció**: a `stations` és `events` kollekciók publikusan
   olvashatók (a térképhez és a listákhoz kell), és a `qrCode` mező is bennük
   volt — a teljes QR-készlet lekérdezhető volt beolvasás nélkül, otthonról.

## Az új architektúra

```
Mobil app ──(nyers kód)──► redeemQr Cloud Function (europe-west1)
                               │  1. qr_codes/{URI-kódolt kód} leképezés
                               │     (fallback: stations/events qrCode mező,
                               │      majd doc-id — a migráció idejére)
                               │  2. tranzakció: user_progress jóváírás
                               │  3. jutalom-feloldás + unlockedCount
                               │  4. public_leaderboard szinkron
                               ▼
                           Firestore (Admin SDK, a rules megkerülésével)
```

- **`functions/lib/redeem-core.js`** — a teljes jóváírási logika, injektált
  db-vel; 12 unit teszt fedi (in-memory Firestore-stub, `npm test`).
- **`qr_codes` kollekció** — kód → cél (állomás/esemény) leképezés; csak admin
  írhatja/olvashatja, kliens egyáltalán nem. Az admin felület mentéskor/
  törléskor automatikusan karbantartja (`admin/src/utils/qrMapping.js`),
  ütközésvédelemmel.
- **Flutter** — szerver-először: a `QrProcessingService` a függvényt hívja;
  ha az nincs deployolva (`not-found`), erre a futásra visszavált a legacy
  kliensoldali útra. Ismeretlen kódra a szerver `found:false`-t ad (nem
  hibát), így az offline várólista poison-kezelése változatlanul működik.
  Tranziens hálózati hiba továbbdobódik, a várólista újrapróbálja.

## Üzembe helyezés (sorrend számít!)

> **Előfeltétel**: a Cloud Functions **Blaze (pay-as-you-go)** Firebase-csomagot
> igényel. A Spark (ingyenes) csomagon a deploy elutasításra kerül — az app
> ilyenkor is működik, a legacy fallback úton.

1. **Függvény deploy**
   ```bash
   firebase deploy --only functions
   ```
2. **qr_codes backfill** (egyszeri, idempotens)
   ```bash
   cd functions
   GOOGLE_APPLICATION_CREDENTIALS=<service-account.json> node scripts/backfill-qr-codes.mjs
   ```
   Ütközéseket (két elem azonos QR-értékkel) kiírja — ezeket az admin
   felületen kell feloldani.
3. **Ellenőrzés**: mobil beolvasás után a Functions log mutatja a hívást;
   a pontnak a szerveren kell jóváíródnia.
4. **Rules lockdown** — CSAK akkor, ha a szerver-utas mobil verzió már kint
   van (a régi, tisztán kliensoldali app-verziók ettől elromlanak!).
   A `firestore.rules`-ban a `user_progress` blokk cseréje:

   ```
   match /user_progress/{userId} {
     allow read: if isSignedIn() && (request.auth.uid == userId || isAdmin());
     allow write: if isAdmin();

     // Regisztráció: nullázott create továbbra is kliensről történik.
     allow create: if isSignedIn() && request.auth.uid == userId
       && (!request.resource.data.keys().hasAny(['totalPoints'])
           || request.resource.data.totalPoints == 0)
       && (!request.resource.data.keys().hasAny(['completedStations'])
           || request.resource.data.completedStations.size() == 0)
       && (!request.resource.data.keys().hasAny(['completedEvents'])
           || request.resource.data.completedEvents.size() == 0)
       && (!request.resource.data.keys().hasAny(['completedTripIds'])
           || request.resource.data.completedTripIds.size() == 0);

     // Az egyetlen megengedett kliens-update: a jutalom-banner nyugtázása.
     allow update: if isSignedIn() && request.auth.uid == userId
       && request.resource.data.diff(resource.data).affectedKeys()
            .hasOnly(['pendingAchievementBanner']);

     // ... alkollekciók változatlanul ...
   }
   ```

   A `public_leaderboard` szabályát nem kell szigorítani: a meglévő
   kereszt-ellenőrzés (points == user_progress.totalPoints) a lezárt
   user_progress mellett már önmagában is hamisíthatatlan.

5. **Opcionális utolsó lépés (teljes enumeráció-védelem)**: a `qrCode` mező
   eltávolítása a publikus `stations`/`events` dokumentumokból és a doc-id
   fallback kivezetése a függvényből. A kinyomtatott QR-matricák érvényben
   maradnak (az értékük a `qr_codes` leképezésben él tovább). Ehhez az admin
   PDF-exportot a `qr_codes` kollekcióból kell kiszolgálni.

## Helyi kipróbálás emulátorral

```bash
firebase emulators:start          # functions + firestore + auth (firebase.json)
```

Flutter oldalon fejlesztéskor irányítsd a függvényhívást az emulátorra
(pl. a main.dart-ban, debug módban):

```dart
FirebaseFunctions.instanceFor(region: 'europe-west1')
    .useFunctionsEmulator('localhost', 5001);
```

## Push értesítések (notifyOnNewEvent)

A `functions/` ugyanebben a workspace-ben tartalmaz egy `notifyOnNewEvent`
Firestore-triggert: új `events/{id}` dokumentum létrehozásakor push-üzenetet
küld az `events` FCM-topicra. Az üzenetet a tesztelhető
`functions/lib/notification-builder.js` állítja össze (cím, dátum+helyszín,
rövidített leírás). A mobil kliens (`NotificationService`) bejelentkezés után
engedélyt kér és feliratkozik a topicra; kijelentkezéskor leiratkoztatható.

Ez is a `firebase deploy --only functions` paranccsal élesedik (Blaze-csomag).
Androidon opcionálisan létrehozható egy `events` nevű notification-csatorna a
natív rétegben; ennek hiányában az FCM a default csatornát használja.

## Tesztek

| Réteg | Teszt | Darab |
|---|---|---|
| Cloud Function (mag + értesítés) | `functions/test/*.test.js` (node:test) | 22 |
| Cloud Function (emulátor ellen) | `firestore-tests/tests/redeem-core-emulator.test.js` | 6 |
| Firestore rules (emulátor) | `firestore-tests/tests/rules-*.test.js` | 22 |
| Admin util | `admin/src/utils/qrMapping.test.js` (Vitest) | 13 |
| Flutter | `mobile_app/test/qr_processing_service_test.dart` | 20 |

A CI (`.github/workflows/ci.yml`) minden réteget futtat; a rules-job Temurin
JDK 21 + `firebase emulators:exec` alatt fut.
