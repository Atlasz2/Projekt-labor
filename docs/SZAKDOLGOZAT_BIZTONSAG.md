# A pontgyűjtő rendszer biztonsági architektúrája

> Szakdolgozati fejezet-nyersanyag: a QR-alapú pontgyűjtés fenyegetésmodellje, a
> rétegzett védekezés és a maradék kockázatok. A hivatkozott fájlok a repóban
> találhatók.

## 1. A probléma: kliensoldali bizalom egy pontgyűjtő játékban

A pont a rendszer „valutája”: jutalmak és ranglista-helyezés függ tőle, ezért ha
hamisítható, a játékosítás értékét veszti. A kiinduló architektúrában a pontot a
mobil kliens számolta és írta közvetlenül a Firestore-ba. Ez kényelmes, de a kliens
nem megbízható: a Firebase-projekt API-kulcsa nyilvános, így egy bejelentkezett
felhasználó a hivatalos alkalmazás nélkül is írhat mindent, amit a szabályok
engednek. A fejezet azt mutatja be, hogyan került a rendszer a „bízz a kliensben”
modellből a „bízz a szerverben” modellbe, tesztekkel bizonyított módon.

## 2. Fenyegetésmodell

A támadó **hitelesített, de rosszindulatú felhasználó**: valódi fiókja van, és a
hivatalos klienst megkerülve közvetlenül hívhatja a Firestore REST API-t, vagy
módosított appot futtathat. Nem feltételezünk adatbázis-szintű hozzáférést vagy
ellopott admin-fiókot.

| # | Támadási vektor | Cél | Kiinduló állapot | Jelenlegi állapot |
|---|---|---|---|---|
| T1 | Pontfelfújás létrehozáskor | saját haladás létrehozása magas ponttal | nyitott | zárt (nullázott létrehozás) |
| T2 | Pontfelfújás módosítással | saját pont tetszőleges növelése | nyitott | zárt (csak szerver ír) |
| T3 | Pontcsökkentés, állomás eltávolítása | adatrongálás | zárt | zárt |
| T4 | Más felhasználó adatának írása | idegen haladás manipulálása | zárt | zárt |
| T5 | Jogosultság-eszkaláció | saját fiók admin szerepre emelése | zárt | zárt |
| T6 | Ranglista-hamisítás | magas helyezés teljesítmény nélkül | zárt | zárt |
| T7 | QR-kód-enumeráció | kódok kigyűjtése helyszíni jelenlét nélkül | nyitott | részben zárt |
| T8 | Tartalmi kollekció írása | hamis állomás vagy jutalom | zárt | zárt (tenant-izolációval) |
| T9 | Távoli beolvasás | pont lefényképezett kóddal, távolról | nyitott | visszaszorítva (GPS) |
| T10 | Jutalom önfeloldása | jutalom (akár fizikai kedvezmény) teljesítés nélkül | nyitott | zárt (csak szerver ír) |

## 3. A védekezés rétegei

### 3.1 Firestore security rules

- **UID-alapú admin-ellenőrzés**: az admin jogot a felhasználó UID-kulcsú `users`
  dokumentumának `role` mezője dönti el; szerepkört csak developer adhat (T5). Az
  e-mail-kulcsú tartalék csak egyező `uid` mezővel fogad el.
- **Lezárt haladás**: a `user_progress` dokumentumot a kliens csak nullázva hozhatja
  létre (T1), és csak a jutalom-értesítés nyugtázását módosíthatja; pontot,
  teljesített listát és alkollekciót (feloldott jutalmak) csak a szerver vagy admin
  írhat (T2, T3, T10).
- **Ranglisták**: a települési ranglistát csak a szerver írja; a régi globális
  ranglistán a pont csak a tárolt `totalPoints`-szal egyezhet (T6).
- **Tenant-izoláció**: admin csak a saját települése tartalmát írhatja, és nem
  mozgathat át tartalmat másik településre; a developer mindet kezeli (T8).
- **Privát `qr_codes`**: kliens nem olvashatja; település szerint elkülönítve, a
  leképezés célja a köteg utáni állapotban ellenőrzött (T7).

### 3.2 Szerveroldali jóváírás és jutalom-egyeztetés (Cloud Functions)

A `redeemQr` hívható függvény a klienstől csak a nyers QR-kódot, a pozíciót és a
kiadás települését kapja; minden mást Admin SDK-val maga állapít meg. A felhasználó
azonosítója a tokenből jön, nem a kérésből.

- **Atomicitás**: a jóváírás és a ranglista-bejegyzések egy tranzakcióban
  íródnak (`arrayUnion` + `increment`), így párhuzamos feldolgozás (élő beolvasás
  + offline sor) sem ír kétszer, és a pont nem változhat a ranglista nélkül –
  emulátoros teszt: négy párhuzamos hívásból pontosan egy ír, a ranglistán is.
- **Önjavítás**: a túra-teljesítés és a jutalmak kiértékelése idempotens, és
  ismételt beolvasáskor is lefut; egy megszakadt kérés újrapróbálása pótolja a
  kimaradt lépést. Törölt vagy más településhez tartozó túra nem teljesülhet.
- **Település-ellenőrzés**: másik település kódja `wrong_project`; a jutalmak közül
  csak a cél településéi oldódhatnak fel.
- **Jutalom-egyeztetés**: a beolvasás nélkül teljesülő jutalmakat (utólag létrehozott
  jutalom, top-N rangváltozás) a `reconcileAchievements` függvény oldja fel, így a
  kliensnek nem kell írnia a jutalmak alkollekcióját.

### 3.3 A QR-értékek elrejtése (T7)

A kód értéke kizárólag a privát `qr_codes` leképezésben él; a publikusan
olvasható `stations`/`events` dokumentum csak a SHA-256 lenyomatát (`qrHash`)
tárolja, amelyből a kód nem állítható vissza, de a mobil offline felismeréséhez
elég. Az új kódok kriptográfiailag véletlenek (16 jel, kb. 79 bit), egyedi kód
csak legalább 12 karakterrel adható meg – így a kód sem kigyűjteni, sem
végigpróbálni nem lehet. A dokumentum és a leképezés egy kötegben íródik (nincs
feloldhatatlan kód), a leképezés település szerint elkülönített, és a szabályok
a köteg utáni állapotban ellenőrzik, hogy a célja létezik és ugyanahhoz a
településhez tartozik; a szerver ugyanezt feloldáskor is ellenőrzi. A meglévő
adatot a `scripts/harden-qr-codes.mjs` migráció hozza ebbe az állapotba (a
kitalálható kódok cseréjével és újranyomtatási listával), utána a
`QR_LEGACY_FALLBACK=false` kapcsoló és a szabályok `qrCode`-tilalma zárja le a
régi utat. Az admin a QR-képeket helyben, böngészőben generálja, így a
kódértékek harmadik félhez sem jutnak el.

### 3.4 Helyszín-ellenőrzés (T9)

A kliens a beolvasáskor rögzíti a GPS-pozíciót, a szerver az állomás koordinátáihoz
méri (Haversine); ha a távolság nagyobb a küszöbnél (állomásonkénti `radius`, alap
150 m), `rejected: 'out_of_range'`. A mobil ugyanezt a képletet az offline sorba
állítás előtt is alkalmazza (felesleges sorelemek kiszűrése, azonnali
visszajelzés), de a döntés mindig a szerveren születik. Koordináta nélküli célok
mentesülnek. Az admin állomásonként előírhatja a helymeghatározást
(`requireLocation`): ilyenkor a pozíció nélküli kérés `location_required`
elutasítást kap, így a lefényképezett kód távolról, GPS nélkül sem váltható be.

### 3.5 App Check

A mobilból hívott függvények (`redeemQr`, `reconcileAchievements`, `renameMe`,
`exportUserData`, `deleteMyAccount`) a tokent ellenőrzik és naplózzák; az
`ENFORCE_APP_CHECK=true` kapcsolóval token nélkül elutasítanak (Play Integrity /
App Attest), ami a módosított klienseket és a közvetlen API-hívó szkripteket
szűri. A kikényszerítés az áruházi kiadás után kapcsolandó be, mert az App
Distributionnel terjesztett build nem kap érvényes Play Integrity-tokent
(lásd `docs/LAUNCH.md`).

## 4. A védekezés bizonyítása

| Szint | Mit bizonyít | Eszköz |
|---|---|---|
| Szabálytesztek (emulátor, 33) | T1–T8 és T10 elutasítva, a legitim műveletek (regisztráció, nyugtázás, admin jutalom-odaítélés) engedettek, tenant-izoláció, a nyilvános QR-érték tilalma, a QR-leképezés elkülönítése és célellenőrzése | `@firebase/rules-unit-testing` |
| Cloud Functions (stub, 109) | a jóváírás és az egyeztetés minden ága, önjavítás, helyszín- és település-ellenőrzés, kötelező pozíció, QR-migráció, GDPR | `node:test` + memóriabeli Firestore |
| Cloud Functions (emulátor, 11) | valós tranzakció-szemantika, konkurencia (a ranglistán is), helyszín-elutasítás, egyeztetés, GDPR | Firestore-emulátor |
| Admin (195) | atomi QR-mentés, kódgenerálás és -lenyomat, ütközésvédelem, tenant-szűrés | Vitest |
| Mobil (118) | szerver-válasz értelmezése, hibaosztályozás, offline sor, lenyomat-alapú offline felismerés | `flutter test` |

## 5. Maradék kockázatok

- **GPS-hamisítás**: szimulált pozícióval a helyszín-ellenőrzés megkerülhető; a
  pozíció nélküli kérést a `requireLocation` állomásokon a szerver elutasítja,
  egyebütt (akadálymentesség) átengedi. Az App Check kikényszerítése a módosított
  klienseket szűri; sebességellenőrzés (két beolvasás közti távolság / idő)
  további réteg lehetne.
- **QR-enumeráció a migrációig**: amíg a `harden-qr-codes.mjs` nem futott le és a
  `QR_LEGACY_FALLBACK` be van kapcsolva, a régi nyilvános kódok kigyűjthetők
  (`docs/LAUNCH.md`, 2–3. lépés).
- **Fiók-visszaállítás**: az e-mailhez kapcsolt fiók jelszava a névből képződik;
  aki ismeri valaki e-mail-címét és (nyilvános) nevét, hozzáférhet a fiókhoz.
  Tudatos egyszerűsítés pontgyűjtő fióknál.
- **Régi appverziók**: a lezárt szabályok után a kliensoldali jóváírást használó
  régi verziók nem írhatnak pontot – ez szándékos, de frissítést igényel.

## 6. Összegzés

A tíz azonosított vektorból hatot (T1, T3–T6, T8) önmagában a deklaratív
szabályréteg zár; a pontfelfújást és a jutalom önfeloldását (T2, T10) a
szerveroldali jóváírás és egyeztetés a lezárt szabályokkal együtt zárja, a
QR-enumerációt a lenyomatos, véletlen kódú, település szerint elkülönített privát
leképezés zárja (a migráció után), a távoli beolvasást a GPS-ellenőrzés és az
állomásonként előírható kötelező pozíció nehezíti. Minden réteget automatizált teszt bizonyít,
valós Firestore-emulátor ellen is; a maradék kockázatok dokumentáltak.

### Hivatkozott fájlok

- `firestore.rules`, `storage.rules`
- `functions/lib/redeem-core.js`, `functions/index.js`
- `firestore-tests/tests/` – szabály- és emulátoros tesztek
- `docs/SERVER_VALIDATION.md` – üzembe helyezés
