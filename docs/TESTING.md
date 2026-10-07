# Tesztelés

A rendszer négy rétegben tesztelt. Minden réteg a CI-ban (`.github/workflows/ci.yml`)
is fut, push és pull request esetén.

| Réteg | Hely | Eszköz | Tesztek |
|---|---|---|---|
| Cloud Functions egységtesztek | `functions/test/` | `node:test` + memóriabeli Firestore-hamisítvány (`fake-firestore.js`) | 109 |
| Szabályok és integráció | `firestore-tests/tests/` | `@firebase/rules-unit-testing`, firebase-admin, Firestore-emulátor | 44 |
| Adminisztrációs felület | `admin/src/**/*.test.js(x)` | Vitest, React Testing Library, jsdom | 195 |
| Mobilalkalmazás | `mobile_app/test/` | `flutter test`, `fake_cloud_firestore` | 118 |

Statikus elemzés: `npm run admin:lint` (ESLint, 0 figyelmeztetés megengedve) és
`flutter analyze` (hiba- és figyelmeztetésmentes).

## Futtatás

```bash
npm run functions:test
npm run admin:test
npm run mobile:test
npm run rules:test      # Firestore-emulátort indít, JDK 21 szükséges
```

Lefedettségmérés (a CI is lefedettséggel futtatja a rétegeket):

```bash
npm run functions:coverage  # node:test beépített mérése, csak a lib/ üzleti logika
npm run admin:coverage      # Vitest + v8, eredmény: admin/coverage/
npm run mobile:coverage     # flutter test --coverage, eredmény: mobile_app/coverage/lcov.info
```

Állapot (2026. október 7.): a Cloud Functions üzleti logikája 100% sor- és 90%
ág-lefedettségű; az admin felületen 44% (a segédfüggvények és a kritikus hookok
– CRUD, QR-kezelés, képkezelés, településkezelés – teljesen lefedettek, a nagy,
térképes oldalkomponensek kevésbé); a mobilon a tesztek által betöltött fájlokra 45%.

## Mit fednek le

**Cloud Functions** (`redeem-core`, `qr-harden-core`, `profile-core`, `gdpr-core`,
`analytics-core`, `hiking-route-core`, `notification-builder`, `station-trips-core`):
a QR-feloldás minden ága (privát leképezés, kikapcsolható régi tartalék, árva és
más településre eltérített leképezés), idempotens és önjavító jóváírás (a ranglista
a tranzakcióban; ismételt beolvasás pótolja a kimaradt túra-teljesítést), törölt
vagy idegen túra nem teljesül, kötelező pozíció (`location_required`), a QR-migráció
(gyenge, ütköző kódok cseréje, lenyomat, idempotencia, újranyomtatási CSV, a
migráció után a régi kód nem, az új beváltható), túra-teljesítés több túrához
tartozó állomással, minden
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
tartalmat, szerepkört és települést csak developer kezel), a QR-kód értékének
tilalma a nyilvános dokumentumban, a dokumentum és a leképezés kötegelt mentése,
a más településre mutató vagy nem létező célú leképezés tiltása, és a leképezések
település szerinti olvasása/listázása.

**Integráció valós Firestore-emulátor ellen** (`redeem-core-emulator`,
`gdpr-core-emulator`): valódi tranzakció-szemantika – négy párhuzamos beváltásból
pontosan egy jóváírás, a ranglistán is –, `orderBy`-os `top_n`, helyszín-elutasítás, jutalom-
egyeztetés, GDPR-műveletek.

**Admin**: QR-kezelés (véletlen kódgenerálás, SHA-256 lenyomat a közös ellenőrző
értékekkel, gyenge kód felismerése, atomi mentés és törlés, település szerinti
betöltés, ütközésvizsgálat), az állomásoldal mentése (a nyilvános dokumentumba
csak lenyomat kerül, a régi leképezés törlődik, rövid kód elutasítva, kötelező
pozíció), segédfüggvények (helyi QR-generálás,
fotómezők, település-szűrés, szerepkör-feloldás, útvonal, CSV-export, túránkénti
sorrend), komponensek és oldalak (állomások, felhasználók, hibabejelentések,
áttekintő, analitika).

**Admin – hookok és kontextus**: a generikus CRUD hook (település-szűrés, a
`projectId` kikényszerítése), a képkezelő (a Storage-kép csak sikeres mentés után
törlődik, megszakításkor semmi), a feltöltés időkorlátja és tartaléka, valamint a
településkezelés (duplikált azonosító tiltása, csak üres település törölhető, az
alapértelmezett település átnevezése). A túra törlésekor az állomások
leválasztását (`tripUnlinkPatch`) külön tesztek ellenőrzik.

**Mobil**: a szerver-válasz értelmezése és a hibaosztályozás (végleges / átmeneti),
az offline sor feldolgozása (`drainQueue`: siker, végleges hiba, átmeneti hiba,
egy hibás elem nem állítja meg a többit), a lenyomat-alapú offline kódfelismerés
(közös ellenőrző értékek), a kötelező pozíció, az adatkezelési tájékoztató,
a kliensoldali helyszín-előszűrés, az offline sor modellje, jutalom-feltételek,
profilstatisztikák, útvonal-szolgáltatás, település-szűrés, képmezők, hitelesítés,
regisztrációs űrlap, akadálymentesség, és egy folyamatteszt a beolvasástól az
eredményképernyőig.
