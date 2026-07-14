# A pontgyűjtő rendszer biztonsági architektúrája

> Szakdolgozati fejezet-nyersanyag. A rendszer QR-alapú pontgyűjtő logikájának
> fenyegetés-modellezését, a rétegzett védekezést és a maradék kockázatokat
> tárgyalja. A hivatkozott forrásfájlok a repóban találhatók.

## 1. A probléma: kliensoldali bizalom egy pontgyűjtő játékban

A rendszer gamifikált turisztikai alkalmazás: a felhasználók fizikai
helyszíneken QR-kódot olvasnak be, amiért pontot kapnak, és a pontok alapján
jutalmakat oldanak fel, illetve ranglistán versenyeznek. A pont tehát a
rendszer „valutája" — ha hamisítható, az egész gamifikáció értékét veszti.

A kiinduló architektúrában a pontszámítást a **mobil kliens** végezte és írta
közvetlenül az adatbázisba (Firebase Firestore). Ez a mobil- és
webalkalmazásoknál gyakori, kényelmes minta, de egy alapvető bizalmi hibát
hordoz: **a kliens nem megbízható**. A Firestore biztonsági szabályai
(`security rules`) korlátozzák ugyan, mit írhat egy hitelesített felhasználó,
de a szabályok csak deklaratív feltételek — nem tudják kiváltani a
szerveroldali üzleti logikát.

A fejezet azt a folyamatot mutatja be, ahogy a rendszer a „bízz a kliensben"
modellből a „bízz a szerverben" modellbe került, tesztekkel bizonyított
módon.

## 2. Fenyegetés-modell

A vizsgált támadó egy **hitelesített, de rosszindulatú felhasználó**: valós
fiókkal rendelkezik (bejelentkezett), és képes a hivatalos kliens megkerülésére
— akár a Firestore REST API-t hívja közvetlenül a publikus API-kulccsal, akár
módosított app-buildet futtat. Nem feltételezünk viszont adatbázis-szintű
hozzáférést vagy ellopott admin-hitelesítést.

| # | Támadási vektor | Cél | Kiinduló állapot |
|---|---|---|---|
| T1 | Pont-felfújás létrehozáskor | A saját `user_progress` doksi létrehozása magas `totalPoints`-szal | **Nyitva** |
| T2 | Pont-felfújás módosítással | A saját `totalPoints` tetszőleges növelése update-tel | **Nyitva** |
| T3 | Pontcsökkentés / állomás-eltávolítás | Adatrongálás, versenyző visszavetése | Zárva (monoton szabály) |
| T4 | Más felhasználó adatának írása | Idegen pontszám/haladás manipulálása | Zárva |
| T5 | Jogosultság-eszkaláció | Saját fiók `admin` szerepre emelése | Zárva |
| T6 | Ranglista-hamisítás | Magas pont a ranglistán valódi teljesítmény nélkül | Zárva (kereszt-ellenőrzés) |
| T7 | QR-kód enumeráció | Az összes QR-érték kigyűjtése beolvasás (helyszín) nélkül | **Nyitva** |
| T8 | Tartalmi kollekció írása | Hamis állomás/jutalom létrehozása | Zárva |
| T9 | Távoli beolvasás | Pont szerzése a helyszíntől távol (lefényképezett QR) | **Nyitva** |

A négy **nyitott** vektor (T1, T2, T7, T9) adta a munka fókuszát.

## 3. A védekezés rétegei

A megoldás nem egyetlen kapcsoló, hanem egymásra épülő rétegek sora — a
„defense in depth" elv szerint minden réteg akkor is korlátoz, ha egy másik
kiesik.

### 3.1 Réteg: Firestore security rules

Az első védvonal deklaratív. A `firestore.rules` néhány kulcsdöntése:

- **UID-alapú admin-ellenőrzés** (`adminByUid`): az admin jogot a felhasználó
  dokumentumának UID-kulcsú változata dönti el, amit a felhasználó nem tud
  meghamisítani (nem hozhat létre tetszőleges UID-jű doksit). Az email-alapú
  fallback is csak akkor fogad el, ha a doksi `uid` mezője egyezik a hívóéval.
- **Monoton haladás** (`isValidProgressUpdate`): a `totalPoints` nem
  csökkenhet, a `completedStations` nem zsugorodhat (T3 zárva).
- **Nullázott létrehozás**: a `user_progress` létrehozásakor a számlálóknak
  nulláznak kell lenniük — ez zárja a T1 vektort.
- **Ranglista kereszt-ellenőrzés**: a `public_leaderboard` bejegyzés
  `points` mezője csak akkor fogadott el, ha megegyezik a felhasználó
  `user_progress.totalPoints` értékével (T6 zárva). A védelem a
  `user_progress` doksi létezését is megköveteli, hogy a hiányzó doksin
  keresztüli megkerülés se működjön.

**Amit a rules nem tud**: a T2 vektort (update-tel való pont-növelés) nem
lehet tisztán deklaratívan zárni, amíg a kliens írja a pontot — hiszen a
legitim jóváírás is éppen pont-növelés. Ehhez szerveroldali logika kell.

### 3.2 Réteg: szerveroldali validáció (Cloud Function)

A döntő lépés a pontszámítás áthelyezése a kliensről a szerverre. A `redeemQr`
hívható Cloud Function (`functions/`) fogadja a **nyers QR-kódot**, és Admin
SDK jogosultsággal (a rules megkerülésével) maga végzi:

```
Mobil app ──(csak a nyers kód)──► redeemQr Cloud Function
                                     │  1. kód → cél feloldás (qr_codes)
                                     │  2. tranzakció: pont + lista jóváírás
                                     │  3. túra-teljesítés + jutalom-feloldás
                                     │  4. ranglista-szinkron
                                     ▼
                                 Firestore (Admin SDK)
```

Mivel a kliens már csak a nyers kódot küldi, a `user_progress` kliensoldali
írása **teljesen lezárható** (T2 zárva) — ezt a `firestore.lockdown.rules`
tartalmazza: az egyetlen megengedett kliens-update a jutalom-banner
nyugtázása, minden más mezőt kizárólag a függvény vagy admin írhat.

Két tervezési részlet emelendő ki:

- **Atomicitás**: a jóváírás Firestore-tranzakcióban fut (`arrayUnion` +
  `increment` transzformokkal), így két párhuzamos feldolgozás (pl. élő
  beolvasás és az offline sor szinkronja) nem tud ugyanazért a kódért kétszer
  pontot írni. Ezt emulátor ellen futó konkurrencia-teszt bizonyítja: négy
  párhuzamos hívásból pontosan egy ír.
- **Fokozatos bevezetés**: a mobil kliens „függvény-először" működik, de ha a
  függvény nincs deployolva, visszaesik a régi kliensoldali útra. Így a
  migráció nem igényel egyszerre-váltást, és a régi app-verziók sem törnek el.

### 3.3 Réteg: a QR-értékek elrejtése (T7)

A `stations` és `events` kollekciók publikusan olvashatók (a térképhez és a
listákhoz kell), és eredetileg a `qrCode` mezőt is tartalmazták — így a teljes
QR-készlet lekérdezhető volt beolvasás nélkül, otthonról (T7). A megoldás egy
**privát leképező kollekció** (`qr_codes`): a kód → cél hozzárendelés ide
kerül, amit csak admin és a szerver olvashat, a kliens egyáltalán nem. A
végső lépésben a `qrCode` mező kivezethető a publikus dokumentumokból is,
miközben a kinyomtatott QR-matricák érvényben maradnak (értékük a
leképezésben él tovább).

### 3.4 Réteg: helyszín-ellenőrzés (T9)

A QR-kód enumeráció lezárása után is marad egy fizikai vektor: a matrica
**lefényképezhető és megosztható**, így a kód önmagában megszerezhető a
helyszínen járás nélkül (T9). Az ellenszer a beolvasáskori pozíció
ellenőrzése: a kliens rögzíti az eszköz GPS-koordinátáját, és beküldi a
`redeemQr`-nek, amely az állomás koordinátáihoz méri (Haversine-távolság). Ha
a távolság meghaladja a küszöböt — állomásonként a `radius` mező, vagy
alapból 150 m —, a jóváírás elmarad (`rejected: 'out_of_range'`).

A védelem a szerveren dől el (a kliens megkerülhető), de a mobil a beolvasás
pillanatában is ad UX-visszajelzést („Menj közelebb az állomáshoz"), és az
offline sorba tett beolvasásokhoz elmenti a pozíciót, hogy a szinkronkor a
szerver azt is ellenőrizhesse. A `latitude/longitude` mező nélküli célok
(pl. helyhez nem kötött események) mentesülnek az ellenőrzés alól.

Fontos, hogy ez **defense in depth réteg, nem tökéletes zár**: a pozíció
opcionális (a GPS-mentes vagy engedélyt megtagadó eszközök is használhassák az
appot), ezért a szerver a *hiányzó* pozíciót átengedi — egy elszánt támadó
tehát pozíció nélkül küld, vagy hamis GPS-t szimulál. A réteg értéke, hogy a
triviális távoli lekérdezést megszünteti, és a legitim felhasználót a
helyszínre irányítja; a maradék kockázat tudatosan vállalt és dokumentált
(lásd 5. szakasz).

## 4. A védekezés bizonyítása: tesztelés

A biztonság állítás, amíg nincs bizonyítva — ezért minden réteg automatizált
teszttel van alátámasztva, több szinten:

| Szint | Mit bizonyít | Eszköz |
|---|---|---|
| Rules-tesztek (emulátor) | Minden támadási vektor elutasítva; a nyitott T2 dokumentált külön teszttel | `@firebase/rules-unit-testing` |
| Lockdown rules-tesztek | Élesítés után T2 is zárul, a legitim banner-nyugtázás viszont megy | ua. |
| Cloud Function (stub) | A jóváírási logika minden ága (állomás, esemény, túra, top-N) + a helyszín-ellenőrzés (Haversine, radius, out_of_range) | `node:test` + in-memory stub |
| Cloud Function (emulátor) | Valós tranzakció-szemantika, konkurrencia-védelem, helyszín-elutasítás valós adaton | valós Firestore-emulátor |
| Mobil (Flutter) | A legacy úti helyszín-kapu és a Haversine-számítás | `flutter test` + fake Firestore |

A rules-tesztek külön futtatják a **jelenlegi** és az **előkészített
lockdown** szabálykészletet, így egyszerre látszik a mostani állapot és a
deploy utáni cél. A T2 vektor tudatosan van bent egy `ISMERT KORLÁT` nevű
tesztben: a rendszer őszintén dokumentálja, hogy a Cloud Function deploy-ja
(Blaze-csomag) előtt ez a kockázat fennáll.

## 5. Maradék kockázatok és korlátok

Egyetlen rendszer sem tökéletesen biztonságos; a felelős tervezés a maradék
kockázatok kimondását is jelenti.

- **A deploy előtti állapot**: amíg a `redeemQr` függvény nincs éles környezetbe
  telepítve (ehhez a Firebase Blaze, azaz fizetős csomag kell), a T2 vektor
  nyitva marad, és a rendszer a kliensoldali úton működik. A kód, a tesztek és
  a lockdown szabályok készen állnak; a váltás egyetlen deploy + a szigorított
  szabályok élesítése.
- **GPS-hamisítás és a pozíció opcionalitása**: a helyszín-ellenőrzés (3.4)
  a lefényképezett QR-kód triviális távoli beolvasását megszünteti, de nem
  tökéletes zár. Egyrészt a pozíció opcionális (GPS-mentes eszközök miatt), így
  egy támadó pozíció nélkül is küldhet; másrészt a GPS-koordináta szoftveresen
  szimulálható (mock location). Szigorúbb módban a `redeemQr` elutasíthatná a
  pozíció nélküli beolvasást, és integritás-ellenőrzést (pl. Play Integrity)
  köthetne be — ez a jelen projekt keretein túlmutat.
- **Ismételt beolvasás elleni védelem**: a jóváírás idempotens (egy állomás
  egyszer ér pontot), de ez játékmenetbeli, nem biztonsági korlát.

## 6. Összegzés

A rendszer a „bízz a kliensben" modellből a rétegzett, szerveroldali
validációval megtámogatott „bízz a szerverben" modellbe került. A kilenc
azonosított támadási vektorból ötöt már a deklaratív szabályréteg zár; a
maradék négyet a nullázott létrehozás (T1), a szerveroldali jóváírás (T2), a
privát leképező kollekció (T7) és a GPS-alapú helyszín-ellenőrzés (T9) zárja
vagy szorítja vissza. Minden réteget automatizált teszt bizonyít, valós
Firestore-emulátor ellen is. A megoldás fokozatosan vezethető be, és a maradék
kockázatok (deploy előtti állapot, GPS-hamisíthatóság) dokumentáltak — ez a
felelős biztonsági tervezés mintája egy hallgatói projekt keretei között.

---

### Hivatkozott források a repóban

- `firestore.rules` — a jelenlegi (élő) szabálykészlet
- `firestore.lockdown.rules` — az előkészített, deploy utáni végső szabályok
- `functions/lib/redeem-core.js` — a szerveroldali jóváírás magja
- `functions/lib/notification-builder.js` — push-üzenet összeállítás
- `firestore-tests/tests/` — rules- és emulátoros tesztek
- `docs/SERVER_VALIDATION.md` — üzembe helyezési (deploy) útmutató
