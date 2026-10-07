# Nagyvázsonyi turisztikai QR-pontgyűjtő rendszer

Turisztikai pontgyűjtő rendszer Nagyvázsony számára: a látogatók a túraútvonalak
állomásain elhelyezett QR-kódok beolvasásával helytörténeti tartalmat oldanak fel,
pontot és jutalmakat gyűjtenek, és települési ranglistán versenyeznek. A
tartalmat a település egy webes adminisztrációs felületen kezeli.

| Komponens | Könyvtár | Technológia |
|---|---|---|
| Mobilalkalmazás (turisták) | `mobile_app/` | Flutter 3.38 (Dart ≥ 3.10), Android / iOS |
| Adminisztrációs felület | `admin/` | React 19, Vite 7, Material UI 7, TanStack Query 5 |
| Szerveroldali logika | `functions/` | Cloud Functions v2, Node 22, firebase-admin 14 |
| Biztonsági szabályok | `firestore.rules`, `storage.rules` | Firestore / Storage Security Rules |
| Emulátoros tesztek | `firestore-tests/` | `@firebase/rules-unit-testing`, Firestore-emulátor |

Firebase-projekt: `projekt-labor-a4b1c` (Blaze-csomag, régió: `europe-west1`).

## Architektúra röviden

- A kliensek a **tartalmat** (túrák, állomások, rendezvények stb.) közvetlenül a
  Firestore-ból olvassák; a mobil offline gyorsítótárral (Firestore persistence +
  Hive) hálózat nélkül is működik.
- **Pontot kizárólag a szerver ír.** A mobil a `redeemQr` hívható függvénynek csak a
  nyers QR-kódot, a beolvasáskori GPS-pozíciót és a kiadás települését küldi; a
  feloldás (privát `qr_codes` leképezés), a helyszín-ellenőrzés (Haversine,
  állomásonkénti `radius`, alap 150 m), a tranzakciós jóváírás, a túra-teljesítés,
  a ranglista és a jutalmak a szerveren futnak. A `firestore.rules` a pontokat és a
  feloldott jutalmakat a kliens elől teljesen lezárja.
- **White-label:** minden tartalmi dokumentum `projectId` mezővel jelöli a
  települést (hiánya = `nagyvazsony`). Az admin csak a saját települését, a
  developer mindet kezeli. A mobil kiadás települése build-időben dől el
  (`--dart-define=PROJECT_ID=…`).
- Részletek: [docs/DATA_MODEL.md](docs/DATA_MODEL.md),
  [docs/SERVER_VALIDATION.md](docs/SERVER_VALIDATION.md),
  [docs/SZAKDOLGOZAT_BIZTONSAG.md](docs/SZAKDOLGOZAT_BIZTONSAG.md).

## Cloud Functions

| Függvény | Hívó | Feladat |
|---|---|---|
| `redeemQr` | mobil (App Check) | QR-beváltás: validáció, atomi jóváírás és ranglista, túra, jutalom |
| `reconcileAchievements` | mobil (App Check) | utólag teljesült jutalmak feloldása |
| `renameMe` | mobil (App Check) | a játékos nevének módosítása (foglalás, profil, ranglisták) |
| `exportUserData` | mobil (App Check) | GDPR 20. cikk – adatexport |
| `deleteMyAccount` | mobil (App Check) | GDPR 17. cikk – saját fiók törlése |
| `notifyOnNewEvent` | Firestore-trigger | push-értesítés új rendezvényről (`events` topic) |
| `tripAnalytics` | admin | túra-tölcsér, átlagos idő, állomás-népszerűség |
| `hikingRoute` | admin | gyalogos útvonal (BRouter → Valhalla → OSRM → egyenes) |
| `inviteAdmin`, `setUserBanned`, `adminDeleteUser`, `seedProjectLeaderboards` | developer | felhasználó- és ranglistakezelés |

## Mobilalkalmazás

Képernyők (`lib/screens/`): bejelentkezés-kapu, regisztráció, főmenü, térkép és
túrák, túranavigáció, QR-beolvasás, feloldott tartalmak, előzmények, profil
(ranglista, jutalmak, adatvédelem), jutalmak előrehaladása, rendezvények, szállás
és vendéglátás, kapcsolat és hibabejelentés.

Offline működés:
1. Firestore offline gyorsítótár (korlátlan méret).
2. Hive-gyorsítótár a túrákhoz, állomásokhoz, jutalmakhoz és útvonalakhoz (12 óránként frissül).
3. Offline QR-sor: hálózat nélkül a kód és a pozíció tartós sorba kerül, a kapcsolat
   helyreállásakor (valódi elérhetőség-próba után) automatikusan beváltódik;
   végleges hibánál az elem kikerül, átmeneti hibánál marad.
4. Offline térképcsempék: a kiválasztott túra mentén letöltött CARTO-csempék
   offline állapotban egy helyi csempeszolgáltatón keresztül jelennek meg a térképen.
5. Offline képek: az állomásképek helyi fájlként, a megjelenítési mérethez
   illesztett felbontásban dekódolva.

## Adminisztrációs felület

Oldalak: áttekintő (napi pillanatképekkel), analitika, túrák (útvonaltervezéssel,
túránkénti állomássorrenddel), állomások (térképes helykijelölés, QR-kód és
nyomtatható PDF), térkép, rendezvények, szállások, vendéglátóhelyek, a település
története, elérhetőségek, jutalmak, hibabejelentések, felhasználók, települések
(developer). A QR-képeket a böngésző helyben generálja (`qrcode`), külső szolgáltatás nélkül.

## Fejlesztés

Előfeltételek: Node.js 22, Flutter 3.38, Firebase CLI, a Firestore-emulátorhoz JDK 21.

```bash
npm --prefix admin ci              # admin függőségek
npm --prefix functions ci          # Cloud Functions függőségek
npm --prefix firestore-tests ci    # emulátoros tesztek függőségei
cd mobile_app && flutter pub get   # mobil függőségek
```

Indítás Windowson egyszerre: `start.bat`. Külön:

```bash
npm run admin:dev                  # http://localhost:5173
cd mobile_app && flutter run
```

Helyi fejlesztéshez az admin a Firebase Emulator Suite-hoz is csatlakozhat, éles
adatok érintése nélkül:

```bash
firebase emulators:start --only auth,firestore,storage,functions
VITE_USE_EMULATORS=true npm --prefix admin run dev
```

Az admin a `admin/.env.local` fájlból olvassa a Firebase- és Maps-kulcsokat
(minta: `admin/.env.example`). A mobil Android-konfigurációja
(`google-services.json`) nem része a tárolónak.

## Tesztek és minőség

```bash
npm run admin:test         # Vitest
npm run functions:test     # node:test, memóriabeli Firestore-hamisítvánnyal
npm run rules:test         # szabályok + integráció a Firestore-emulátor ellen (JDK 21)
npm run mobile:test        # flutter test
npm run admin:lint         # ESLint, 0 figyelmeztetés
npm run mobile:analyze     # flutter analyze
npm run functions:coverage # lefedettség: functions:/admin:/mobile:coverage
```

A tesztelés részletei: [docs/TESTING.md](docs/TESTING.md). A GitHub Actions CI
(`.github/workflows/ci.yml`) mind a négy réteget futtatja; a `release.yml` a `main`
ágról kiadási APK-t épít és a Firebase App Distributionön keresztül a tesztelőkhöz juttatja
([docs/APP_DISTRIBUTION.md](docs/APP_DISTRIBUTION.md)).

## Telepítés (Firebase)

```bash
firebase deploy --only functions
firebase deploy --only firestore:rules,firestore:indexes,storage
```

Mindig `--only`-val telepíts: a `firebase.json` hosting-blokkja miatt a
paraméter nélküli `firebase deploy` az admin felületet is közzétenné. Az admin
felület közzététele kizárólag a kézzel indítható „Admin – telepítés”
munkafolyamattal történik. Az élesítés teljes, sorrendhez kötött lépéssora (QR-
migráció, kapcsolók, App Check, áruházi kiadás): [docs/LAUNCH.md](docs/LAUNCH.md).

## Ismert korlátok

- A helyszín-ellenőrzés a pozíció hiányát átengedi (GPS nélküli eszközök), kivéve
  a kötelező helymeghatározású állomásokat; a pozíció szoftveresen hamisítható, az
  App Check (kikényszerítve az áruházi kiadás után) a módosított klienseket szűri.
- A mobilfiók e-mailes visszaállításának jelszava a névből képződik (tudatos
  egyszerűsítés: pontgyűjtő fiók, nyilvános név + nem nyilvános e-mail).
- Az admin felület a település szerinti szűrést kliensoldalon végzi; sok település
  esetén szerveroldali `where('projectId', …)` lekérdezésre érdemes váltani.
- Adminisztrátoroknak szóló e-mail-értesítések nincsenek.
