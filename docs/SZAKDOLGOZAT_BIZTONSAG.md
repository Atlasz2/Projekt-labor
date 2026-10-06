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
- **Privát `qr_codes`**: kliens nem olvashatja (T7).

### 3.2 Szerveroldali jóváírás és jutalom-egyeztetés (Cloud Functions)

A `redeemQr` hívható függvény a klienstől csak a nyers QR-kódot, a pozíciót és a
kiadás települését kapja; minden mást Admin SDK-val maga állapít meg. A felhasználó
azonosítója a tokenből jön, nem a kérésből.

- **Atomicitás**: a jóváírás tranzakcióban fut (`arrayUnion` + `increment`), így
  párhuzamos feldolgozás (élő beolvasás + offline sor) sem ír kétszer – emulátoros
  teszt: négy párhuzamos hívásból pontosan egy ír.
- **Település-ellenőrzés**: másik település kódja `wrong_project`; a jutalmak közül
  csak a cél településéi oldódhatnak fel.
- **Jutalom-egyeztetés**: a beolvasás nélkül teljesülő jutalmakat (utólag létrehozott
  jutalom, top-N rangváltozás) a `reconcileAchievements` függvény oldja fel, így a
  kliensnek nem kell írnia a jutalmak alkollekcióját.

### 3.3 A QR-értékek elrejtése (T7)

A `stations`/`events` publikusan olvashatók, és tartalmazzák a `qrCode` mezőt. A
kód → cél hozzárendelés a privát `qr_codes` kollekcióban él; a végső lépés a
`qrCode` mező kivezetése a nyilvános dokumentumokból (a kinyomtatott matricák
érvényesek maradnak). Az admin a QR-képeket helyben, böngészőben generálja, így a
kódértékek harmadik félhez sem jutnak el (korábban egy külső QR-képszolgáltatás
kapta meg őket).

### 3.4 Helyszín-ellenőrzés (T9)

A kliens a beolvasáskor rögzíti a GPS-pozíciót, a szerver az állomás koordinátáihoz
méri (Haversine); ha a távolság nagyobb a küszöbnél (állomásonkénti `radius`, alap
150 m), `rejected: 'out_of_range'`. A mobil ugyanezt a képletet az offline sorba
állítás előtt is alkalmazza (felesleges sorelemek kiszűrése, azonnali
visszajelzés), de a döntés mindig a szerveren születik. Koordináta nélküli célok
mentesülnek.

### 3.5 App Check

A mobilból hívott függvények (`redeemQr`, `reconcileAchievements`,
`exportUserData`, `deleteMyAccount`) csak érvényes App Check-tokennel fogadnak
hívást (Play Integrity / App Attest), ami a módosított klienseket és a közvetlen
API-hívó szkripteket szűri.

## 4. A védekezés bizonyítása

| Szint | Mit bizonyít | Eszköz |
|---|---|---|
| Szabálytesztek (emulátor, 26) | T1–T8 és T10 elutasítva, a legitim műveletek (regisztráció, nyugtázás, admin jutalom-odaítélés) engedettek, tenant-izoláció | `@firebase/rules-unit-testing` |
| Cloud Functions (stub, 82) | a jóváírás és az egyeztetés minden ága, helyszín- és település-ellenőrzés, GDPR | `node:test` + memóriabeli Firestore |
| Cloud Functions (emulátor, 9) | valós tranzakció-szemantika, konkurencia, helyszín-elutasítás, egyeztetés | Firestore-emulátor |
| Mobil (95) | szerver-válasz értelmezése, hibaosztályozás, helyszín-előszűrés | `flutter test` |

## 5. Maradék kockázatok

- **GPS-hamisítás és opcionális pozíció**: pozíció nélküli kéréssel vagy
  szimulált pozícióval a helyszín-ellenőrzés megkerülhető. Szigorúbb módban a
  szerver elutasíthatná a pozíció nélküli kérést, illetve sebességellenőrzést
  (két beolvasás közti távolság / idő) végezhetne.
- **QR-enumeráció a migráció alatt**: amíg a `qrCode` mező a nyilvános
  dokumentumokban van, a kódok kigyűjthetők; ezt a mező kivezetése zárja.
- **Fiók-visszaállítás**: az e-mailhez kapcsolt fiók jelszava a névből képződik;
  aki ismeri valaki e-mail-címét és (nyilvános) nevét, hozzáférhet a fiókhoz.
  Tudatos egyszerűsítés pontgyűjtő fióknál.
- **Régi appverziók**: a lezárt szabályok után a kliensoldali jóváírást használó
  régi verziók nem írhatnak pontot – ez szándékos, de frissítést igényel.

## 6. Összegzés

A tíz azonosított vektorból hatot (T1, T3–T6, T8) önmagában a deklaratív
szabályréteg zár; a pontfelfújást és a jutalom önfeloldását (T2, T10) a
szerveroldali jóváírás és egyeztetés a lezárt szabályokkal együtt zárja, a
QR-enumerációt a privát leképezés és a helyi QR-generálás szorítja vissza, a távoli
beolvasást a GPS-ellenőrzés nehezíti. Minden réteget automatizált teszt bizonyít,
valós Firestore-emulátor ellen is; a maradék kockázatok dokumentáltak.

### Hivatkozott fájlok

- `firestore.rules`, `storage.rules`
- `functions/lib/redeem-core.js`, `functions/index.js`
- `firestore-tests/tests/` – szabály- és emulátoros tesztek
- `docs/SERVER_VALIDATION.md` – üzembe helyezés
