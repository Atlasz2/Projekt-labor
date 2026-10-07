# Szerveroldali QR-validáció (redeemQr) és jutalom-egyeztetés

## Miért szerveroldali?

A korábbi architektúrában a pontjóváírást a mobil kliens számolta és írta a
Firestore-ba. A szabályok a pontcsökkentést és a hamis kezdőértéket tiltották, de
két támadási vektor nyitva maradt:

1. **Pont-felfújás**: egy módosított kliens (vagy a Firestore REST API-t a
   nyilvános API-kulccsal hívó szkript) tetszőlegesen növelhette a saját
   `user_progress.totalPoints` értékét – a legitim jóváírás is pontnövelés, ezt
   deklaratív szabály nem tudja megkülönböztetni.
2. **Jutalom önfeloldása**: a kliens maga írta az `unlocked_achievements`
   alkollekciót, így bármely jutalmat (akár fizikai kedvezményt) feloldhatott.

Mindkettőt az zárja, hogy a pontot és a jutalmat **kizárólag a szerver** írja, a
kliens elől pedig a `firestore.rules` ezeket teljesen lezárja.

## Architektúra

```
Mobil app ──(nyers kód + GPS + projectId)──► redeemQr (europe-west1, App Check)
                                           │ 1. qr_codes/{URI-kódolt kód} leképezés
                                           │    (a leképezés települése = a célé; a
                                           │     qrCode mező / doc-id tartalék csak
                                           │     QR_LEGACY_FALLBACK=true mellett)
                                           │ 2. település-ellenőrzés (wrong_project)
                                           │ 3. kötelező pozíció (requireLocation →
                                           │    location_required)
                                           │ 4. helyszín-ellenőrzés (Haversine, radius / 150 m)
                                           │ 5. tranzakció: user_progress jóváírás ÉS
                                           │    ranglista-bejegyzések (atomi)
                                           │ 6. túra-teljesítés (csak létező, saját
                                           │    településbeli túra) – idempotens
                                           │ 7. jutalmak (csak a település sajátjai) – idempotens
                                           ▼
                                       Firestore (Admin SDK)

Mobil (jutalmak képernyő) ──► reconcileAchievements (App Check)
                               → utólag teljesült jutalmak feloldása
```

- **`functions/lib/redeem-core.js`** – a teljes jóváírási és egyeztetési logika,
  injektált adatbázissal (`redeemQrCore`, `reconcileAchievementsCore`); a
  `functions/test/` alatt memóriabeli Firestore-hamisítvánnyal, a
  `firestore-tests/` alatt valódi emulátorral tesztelt.
- **`qr_codes` kollekció** – kód → cél (állomás/esemény) leképezés `projectId`-vel;
  csak a település adminja, a developer és a szerver olvashatja. A kód értéke
  KIZÁRÓLAG itt él: a nyilvános dokumentum a SHA-256 lenyomatát (`qrHash`)
  tárolja. Az admin felület a dokumentumot és a leképezést egy kötegben írja
  (`admin/src/utils/qrMapping.js: stageQrSave`), ütközésvédelemmel; új elemnél
  kriptográfiailag véletlen, 16 jeles kódot generál, egyedi kódot csak legalább
  12 karakterrel fogad el. A szabályok a leképezés célját a köteg utáni
  állapotban ellenőrzik (`existsAfter`/`getAfter`), így kód nem irányítható más
  település állomására.
- **Önjavítás** – a pont és a ranglista egy tranzakcióban íródik; a túra-
  teljesítés és a jutalmak ismételt beolvasáskor is kiértékelődnek, így egy
  megszakadt kérés utáni újrapróbálkozás (pl. az offline sorból) pótolja a
  kimaradt lépést.
- **Mobil** – a `QrProcessingService` csak a szervert hívja. Ismeretlen kódra a
  szerver `found:false`-t ad (végleges hiba, az offline sor eldobja); a nem
  elérhető függvény (`QrServerUnavailableException`) és a hálózati hiba átmeneti,
  az offline sor később újrapróbálja. Kliensoldali jóváírási tartalék nincs: a
  lezárt szabályok mellett nem is működhetne.
- **Helyszín-ellenőrzés** – a `LocationService` a beolvasáskor lekéri a pozíciót,
  a szerver az állomás koordinátáihoz méri. Offline beolvasásnál a pozíció a sorba
  kerül, a kliens a biztosan elutasítandó beolvasást már a sorba állítás előtt
  kiszűri. A pozíció opcionális: hiányában a szerver átengedi (lásd
  `docs/SZAKDOLGOZAT_BIZTONSAG.md`).

## A lezárt szabályok (`firestore.rules`)

```
match /user_progress/{userId} {
  allow read: if isOwner(userId) || isAdmin();
  allow write: if isAdmin();
  allow create: if isOwner(userId) && isZeroedProgress(request.resource.data);
  allow update: if isOwner(userId)
    && request.resource.data.diff(resource.data).affectedKeys()
         .hasOnly(['pendingAchievementBanner']);   // értesítés nyugtázása
  match /{subcollection}/{docId} {
    allow read: if isOwner(userId) || isAdmin();
    allow write: if isAdmin();                       // jutalmak: csak szerver/admin
  }
}
```

A települési ranglistát (`leaderboards/{projectId}/entries`) kliens nem írhatja. A
régi, globális `public_leaderboard` írása a kereszt-ellenőrzés
(`points == user_progress.totalPoints`) miatt a lezárt haladás mellett
hamisíthatatlan; a szerver a még nem frissített appverziók miatt továbbra is írja.

## Üzembe helyezés

```bash
firebase deploy --only functions
firebase deploy --only firestore:rules,firestore:indexes,storage
```

Az élesítés pontos, sorrendhez kötött lépései (QR-migráció a
`scripts/harden-qr-codes.mjs` szkripttel, `QR_LEGACY_FALLBACK=false`, függvények,
szabályok, App Check-kikényszerítés `ENFORCE_APP_CHECK=true`-val):
[LAUNCH.md](LAUNCH.md). A kapcsolók a `functions/.env.projekt-labor-a4b1c`
fájlban vannak, így az élesítés konfigurációval, kódmódosítás nélkül történik.

## Helyi kipróbálás emulátorral

```bash
firebase emulators:start          # functions + firestore + auth (firebase.json)
```

Flutter oldalon fejlesztéskor a függvényhívás az emulátorra irányítható:

```dart
FirebaseFunctions.instanceFor(region: 'europe-west1')
    .useFunctionsEmulator('localhost', 5001);
```

## Push-értesítések (notifyOnNewEvent)

Új `events/{id}` dokumentum létrehozásakor push-üzenet megy az `events`
FCM-topicra; az üzenetet a tesztelt `functions/lib/notification-builder.js`
állítja össze. A mobil (`NotificationService`) bejelentkezés után engedélyt kér és
feliratkozik.

## GDPR-adatjogok (exportUserData / deleteMyAccount)

- **`exportUserData`** (20. cikk): a hívó összes adatának JSON-exportja; a mobil
  fájlba írja és a megosztó lapon felkínálja.
- **`deleteMyAccount`** (17. cikk): a hívó minden dokumentumának törlése, a
  hibabejelentések anonimizálása, végül az Auth-fiók törlése.

Mindkettő kizárólag a hitelesített hívó adataival dolgozik (`request.auth.uid`).
