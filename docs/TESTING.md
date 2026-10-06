# Tesztelés

A rendszer négy rétegben tesztelt. Minden réteg a CI-ban (`.github/workflows/ci.yml`)
is fut, push és pull request esetén.

| Réteg | Hely | Eszköz | Tesztek |
|---|---|---|---|
| Cloud Functions egységtesztek | `functions/test/` | `node:test` + memóriabeli Firestore-hamisítvány (`fake-firestore.js`) | 88 |
| Szabályok és integráció | `firestore-tests/tests/` | `@firebase/rules-unit-testing`, firebase-admin, Firestore-emulátor | 40 |
| Adminisztrációs felület | `admin/src/**/*.test.js(x)` | Vitest, React Testing Library, jsdom | 161 |
| Mobilalkalmazás | `mobile_app/test/` | `flutter test`, `fake_cloud_firestore` | 101 |

Statikus elemzés: `npm run admin:lint` (ESLint, 0 figyelmeztetés megengedve) és
`flutter analyze` (hiba- és figyelmeztetésmentes).

## Futtatás

```bash
npm run functions:test
npm run admin:test
npm run mobile:test
npm run rules:test      # Firestore-emulátort indít, JDK 21 szükséges
```

## Mit fednek le

**Cloud Functions** (`redeem-core`, `gdpr-core`, `analytics-core`,
`hiking-route-core`, `notification-builder`, `station-trips-core`): a QR-feloldás
minden ága (privát leképezés, `qrCode` mező, dokumentum-azonosító, árva leképezés),
idempotens jóváírás, túra-teljesítés több túrához tartozó állomással, minden
jutalomtípus (köztük `top_n` a települési ranglistán), a jutalmak település szerinti
szűrése, a jutalom-egyeztetés (`reconcileAchievementsCore`), a Haversine-távolság és
a helyszín-ellenőrzés (sugár, pozíció nélküli kérés), a település-ellenőrzés
(`wrong_project`), a GDPR-export és -törlés (idegen adat érintetlen, hibabejelentés
anonimizálva), az analitikai aggregáció és az útvonal-szolgáltatók válaszainak
feldolgozása.

**Szabályok** (`rules.test.js`): a fenyegetésmodell vektorai (T1–T8) támadási
forgatókönyvekkel – hamis kezdőérték, pontnövelés és -csökkentés, teljesített lista
módosítása, jutalom önfeloldása, idegen adat írása, szerepkör-emelés, ranglista-
hamisítás, QR-enumeráció, tartalom írása –, a jutalom-értesítés nyugtázásának
engedélyezése (és csempészett mezők tiltása), valamint a white-label
tenant-izoláció (admin csak a saját települését írhatja, nem mozgathat át
tartalmat, szerepkört és települést csak developer kezel).

**Integráció valós Firestore-emulátor ellen** (`redeem-core-emulator`,
`gdpr-core-emulator`): valódi tranzakció-szemantika – négy párhuzamos beváltásból
pontosan egy jóváírás –, `orderBy`-os `top_n`, helyszín-elutasítás, jutalom-
egyeztetés, GDPR-műveletek.

**Admin**: segédfüggvények (QR-leképezés és ütközésvizsgálat, helyi QR-generálás,
fotómezők, település-szűrés, szerepkör-feloldás, útvonal, CSV-export, túránkénti
sorrend), komponensek és oldalak (állomások, felhasználók, hibabejelentések,
áttekintő, analitika).

**Mobil**: a szerver-válasz értelmezése és a hibaosztályozás (végleges / átmeneti),
a kliensoldali helyszín-előszűrés, az offline sor modellje, jutalom-feltételek,
profilstatisztikák, útvonal-szolgáltatás, település-szűrés, képmezők, hitelesítés,
regisztrációs űrlap, akadálymentesség, és egy folyamatteszt a beolvasástól az
eredményképernyőig.
