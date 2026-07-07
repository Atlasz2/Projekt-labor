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

A három **nyitott** vektor (T1, T2, T7) adta a munka fókuszát.

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

## 4. A védekezés bizonyítása: tesztelés

A biztonság állítás, amíg nincs bizonyítva — ezért minden réteg automatizált
teszttel van alátámasztva, több szinten:

| Szint | Mit bizonyít | Eszköz |
|---|---|---|
| Rules-tesztek (emulátor) | Minden támadási vektor elutasítva; a nyitott T2 dokumentált külön teszttel | `@firebase/rules-unit-testing` |
| Lockdown rules-tesztek | Élesítés után T2 is zárul, a legitim banner-nyugtázás viszont megy | ua. |
| Cloud Function (stub) | A jóváírási logika minden ága (állomás, esemény, túra, top-N) | `node:test` + in-memory stub |
| Cloud Function (emulátor) | Valós tranzakció-szemantika, konkurrencia-védelem | valós Firestore-emulátor |

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
- **A QR-kódok fizikai másolhatósága**: a QR-matrica lefényképezhető és
  megosztható. A rendszer a *helyszínt* nem hitelesíti (nincs GPS-ellenőrzés a
  jóváíráskor) — ez a geocaching-jellegű alkalmazások általános korlátja. Ha a
  helyszínhez kötöttség kritikus lenne, a `redeemQr` bővíthető a beküldött
  GPS-pozíció és az állomás koordinátái közti távolság ellenőrzésével.
- **Ismételt beolvasás elleni védelem**: a jóváírás idempotens (egy állomás
  egyszer ér pontot), de ez játékmenetbeli, nem biztonsági korlát.

## 6. Összegzés

A rendszer a „bízz a kliensben" modellből a rétegzett, szerveroldali
validációval megtámogatott „bízz a szerverben" modellbe került. A nyolc
azonosított támadási vektorból ötöt már a deklaratív szabályréteg zár; a
maradék hármat (pont-felfújás létrehozáskor és módosításkor, QR-enumeráció) a
nullázott létrehozás, a szerveroldali jóváírás és a privát leképező kollekció
zárja. Minden réteget automatizált teszt bizonyít, valós Firestore-emulátor
ellen is. A megoldás fokozatosan vezethető be, és a maradék kockázatok
dokumentáltak — ez a felelős biztonsági tervezés mintája egy hallgatói
projekt keretei között.

---

### Hivatkozott források a repóban

- `firestore.rules` — a jelenlegi (élő) szabálykészlet
- `firestore.lockdown.rules` — az előkészített, deploy utáni végső szabályok
- `functions/lib/redeem-core.js` — a szerveroldali jóváírás magja
- `functions/lib/notification-builder.js` — push-üzenet összeállítás
- `firestore-tests/tests/` — rules- és emulátoros tesztek
- `docs/SERVER_VALIDATION.md` — üzembe helyezési (deploy) útmutató
