# Firestore adatmodell

> Ez a dokumentum a **tényleges** adatszerkezetet írja le (a mezőneveket az éles
> adatbázisból és a forráskódból ellenőrizve). Ha a kód változik, ezt is
> frissíteni kell — a dokumentáció ne mondjon ellent a kódnak.

## 1. Áttekintés

A rendszer három komponensből áll, mind ugyanazt a Firestore adatbázist
használja:

- **Mobilalkalmazás** (Flutter) — a látogatók appja
- **Admin panel** (React) — tartalomkezelés
- **Cloud Functions** (Node 22) — szerveroldali validáció és jóváírás

### 1.1 White-label: a `projectId` elv

A rendszer **több települést** tud kiszolgálni. Minden tartalom-dokumentum egy
`projectId` mezővel jelöli, melyik településhez tartozik.

> **Fontos szabály:** a `projectId` **hiánya** az alapértelmezett települést
> (`nagyvazsony`) jelenti. Ezt a szabályt az admin, a mobil és a szerver is
> egyformán alkalmazza, így a migráció előtti (jelöletlen) adat is helyesen
> működik.

A szabályt megvalósító helyek:
- admin: `admin/src/utils/projects.js` → `docProjectId()`
- mobil: `mobile_app/lib/utils/project_filter.dart` → `projectIdOf()`
- szerver: `functions/lib/redeem-core.js` → `projectOf()`
- biztonsági szabályok: `firestore.rules` → `docProject()`

A mobil kiadás települése **build-időben** dől el
(`mobile_app/lib/config/app_config.dart`):

```bash
flutter build apk --dart-define=PROJECT_ID=nagyvazsony   # alapértelmezés
```

### 1.2 Szerepkörök

| Szerep | Jogosultság |
|---|---|
| `user` | Az app látogatója. Az admin panelbe nem léphet be. |
| `admin` | **Egy** település kezelője. Csak a saját települése tartalmát írhatja. |
| `developer` | Platform-szintű. Minden települést kezel, szerepet adhat, felhasználót törölhet/kitilthat. |

Az admin települését a `users/{uid}.projectId` mező adja meg.

---

## 2. Kollekciók

### 2.1 `projects` — települések

A white-label „bérlők" listája.

| Mező | Típus | Leírás |
|---|---|---|
| `name` | string | A település megjelenített neve |
| `isActive` | bool | Aktív-e |
| `createdAt` | timestamp | Létrehozás |

A dokumentum azonosítója a település „slug"-ja (pl. `nagyvazsony`). Az
alapértelmezett projekt akkor is használható, ha nincs külön dokumentuma.

---

### 2.2 `trips` — túrák

| Mező | Típus | Leírás |
|---|---|---|
| `name` | string | Túra neve |
| `description` | string | Leírás |
| `isActive` | bool | Megjelenjen-e az appban |
| `distance`, `duration` | string | Az útvonalból számított táv/idő (gyorsítótárazva) |
| `projectId` | string | **Település** |
| `createdAt` | timestamp | |

---

### 2.3 `stations` — állomások

| Mező | Típus | Leírás |
|---|---|---|
| `name`, `description` | string | Alapadatok |
| `latitude`, `longitude` | number | Koordináta (alternatívaként beágyazott `location.{latitude,longitude}`) |
| `radius` | number | Opcionális; a helyszín-ellenőrzés sugara méterben (alap: 150) |
| `points` | number | A beolvasásért járó pont (alap: 10) |
| `qrCode` | string | A kihelyezett QR-kód szövege |
| `tripIds` | string[] | Mely túráknak megállója (**0, 1 vagy TÖBB** is lehet) |
| `tripOrder` | map | `{ [tripId]: number }` — sorrend AZ ADOTT túrán belül, túránként külön |
| `photos`, `photoUrls`, `imageUrl` | array/string | Képek (lásd lentebb) |
| `unlockContent` | string | A teljesítés után feloldódó szöveg |
| `unlockContentImageUrl` | string | A feloldott tartalom képe |
| `isActive` | bool | |
| `projectId` | string | **Település** |

> **Képek:** a `photos` a forrás, a `photoUrls`/`imageUrl` visszamenőleges
> kompatibilitási másolatok. A képek **Firebase Storage URL-ek** — a korábbi,
> dokumentumba ágyazott base64 képeket migráltuk
> (`functions/scripts/migrate-inline-images.mjs`), mert 460 KB-os
> dokumentumokat okoztak. **Új képet mindig Storage-ba kell tölteni.**

> **Megszűnt mezők:** `funFact`, `funFactImageUrl`, `extraInfo` — eltávolítva,
> csak a feloldott tartalom maradt. A régi egyszeres `tripId`/`orderIndex`
> mezőt a `tripIds`/`tripOrder` váltotta fel
> (`functions/scripts/migrate-station-trip-memberships.mjs`); az olvasó kód
> (mobil, admin, functions) visszamenőleg kompatibilis, ha a migráció még
> nem futott le egy dokumentumon.

---

### 2.4 `events` — rendezvények

| Mező | Típus | Leírás |
|---|---|---|
| `name`, `description` | string | |
| `date` | string | Az esemény dátuma |
| `location` | string | Helyszín |
| `points` | number | Pecsétért járó pont |
| `qrCode` | string | Opcionális QR-kód |
| `photos`, `photoUrls`, `imageUrl` | array/string | Képek |
| `projectId` | string | **Település** |

Új esemény létrehozásakor a `notifyOnNewEvent` trigger push-értesítést küld az
`events` topicra.

---

### 2.5 `accommodations` / `restaurants` — szállások és vendéglátóhelyek

Közös alap: `name`, `description`, `type`, `photos`/`photoUrls`/`imageUrl`,
`projectId`, `createdAt`.

- `accommodations`: `pricePerNight`, `capacity`, `amenities`
- `restaurants`: `cuisine`, `priceRange`

---

### 2.6 `about` — a település története (idővonal)

| Mező | Típus | Leírás |
|---|---|---|
| `year` | string | Évszám (rendezési kulcs) |
| `title`, `description`, `content` | string | Szöveg |
| `imageUrl` | string | Kép |
| `projectId` | string | **Település** |

---

### 2.7 `contact` — kapcsolati adatok

**Településenként egy dokumentum.**

| Mező | Típus | Leírás |
|---|---|---|
| `mainOffice` | map | `{ name, address, phone, email }` |
| `projectId` | string | **Település** |

> Ismert szépséghiba: néhány régi dokumentumban `cratedAt` (elgépelt
> `createdAt`) mező szerepel; a kód nem használja.

---

### 2.8 `achievements` — jutalmak

| Mező | Típus | Leírás |
|---|---|---|
| `name`, `description` | string | |
| `icon`, `color` | string | Megjelenés |
| `conditionType` | string | `station_count`, `event_count`, `qr_count`, `points_threshold`, `trip_complete`, `top_n`, `manual` |
| `conditionValue` | number | A feltétel küszöbe (N) |
| `rewardInfo` | string | Opcionális: fizikai/kedvezmény jutalom leírása. Ha nem üres, a mobil megjeleníti feloldáskor (felmutatható a helyszínen) |
| `unlockedCount` | number | Hányan oldották fel (**csak szerver írja**) |
| `projectId` | string | **Település** |

---

### 2.9 `users` — fiókok és szerepkörök

| Mező | Típus | Leírás |
|---|---|---|
| `uid` | string | Az Auth-azonosító |
| `email`, `name`, `displayName` | string | |
| `role` | string | `user` / `admin` / `developer` |
| `projectId` | string | Az **admin** települése |
| `banned` | bool | Kitiltva (az Auth-fiók is letiltva) |
| `createdAt` | timestamp | |

> A `role` mezőt **csak developer** írhatja (lásd `firestore.rules`) — így egy
> felhasználó nem tud magának admin jogot adni.

---

### 2.10 `user_progress` — haladás

Dokumentum-azonosító: a felhasználó `uid`-ja.

| Mező | Típus | Leírás |
|---|---|---|
| `name`, `email` | string | |
| `totalPoints` | number | **Globális** összpont (nem településenkénti) |
| `completedStations` | array | Teljesített állomás-azonosítók |
| `completedEvents` | array | Teljesített esemény-azonosítók |
| `completedTripIds` | array | Végigjárt túrák |
| `completedStationsAt` | map | `{ állomásId: timestamp }` — a beolvasás ideje; ebből számol az analitika **átlagos befejezési időt** |
| `pendingAchievementBanner` | map | A mobilnak szóló egyszeri értesítés |
| `createdAt`, `updatedAt` | timestamp | |

**Alkollekció:** `user_progress/{uid}/unlocked_achievements/{achievementId}` →
`{ unlockedAt }`.

> A pontokat **kizárólag a szerver** (`redeemQr`) írja — a kliens csak a nyers
> QR-kódot küldi be. Lásd `docs/SERVER_VALIDATION.md`.

---

### 2.11 Ranglisták

**`leaderboards/{projectId}/entries/{uid}`** — az **aktuális**, településenkénti
ranglista:

| Mező | Típus | Leírás |
|---|---|---|
| `uid`, `projectId` | string | |
| `displayName` | string | |
| `points` | number | Az **adott településen** szerzett pont |
| `completedStationsCount`, `completedEventsCount` | number | |
| `updatedAt` | timestamp | |

Csak a szerver írja (a szabályok a kliens-írást tiltják), így a pontszám nem
hamisítható. A `top_n` jutalom ezen a ranglistán értékelődik ki.

**`public_leaderboard/{uid}`** — a régi, **globális** ranglista. Megmarad, mert
a még nem frissített appverziók ezt olvassák (átmeneti kettős írás).

---

### 2.12 `qr_codes` — QR-leképezés

Dokumentum-azonosító: a QR-kód URI-kódolt alakja.

| Mező | Típus | Leírás |
|---|---|---|
| `kind` | string | `station` vagy `event` |
| `targetId` | string | A cél dokumentum azonosítója |

Elsődleges feloldási út; ha nincs találat, a szerver a `qrCode` mezőre, majd a
dokumentum-azonosítóra esik vissza.

---

### 2.13 `bug_reports` — hibabejelentések

| Mező | Típus | Leírás |
|---|---|---|
| `title`, `description` | string | |
| `status` | string | `open` / `active` / lezárt |
| `severity` | string | |
| `reported_by` | map | `{ name, email, user_id, app_version, os }` |
| `admin_response`, `response_date` | string/ts | Admin válasza |
| `screenshot_urls` | array | |
| `projectId` | string | **Település** — mindenki a saját tájékán lévőket látja |
| `created_at`, `updated_at` | timestamp | (+ `_ms` / `_text` másolatok az offline sorhoz) |

---

### 2.14 `stats_daily` — napi pillanatképek (trend)

Dokumentum-azonosító: `{projectId}_{YYYY-MM-DD}` — **településenként külön**,
hogy a különböző adminok ne írják felül egymás adatait.

| Mező | Típus |
|---|---|
| `date`, `projectId` | string |
| `trips`, `stations`, `users`, `trackedUsers`, `totalPoints`, `achievements` | number |
| `updatedAt` | number |

---

### 2.15 `usernames` — egyedi nevek

Dokumentum-azonosító: a normalizált (kisbetűs, szóköz-tömörített) név.
`{ uid, displayName, normalized, createdAt }` — a névütközés elkerülésére.

---

## 3. Biztonsági alapelvek

1. **Pontot csak a szerver ír.** A `redeemQr` Cloud Function validál (kód,
   helyszín, település) és ír; a kliens a `user_progress`-t nem módosíthatja.
2. **Helyszín-ellenőrzés**: a beolvasáskori GPS-pozíciót a szerver az állomás
   koordinátájához méri (`radius`, alap 150 m).
3. **Település-ellenőrzés**: másik település QR-kódja nem írható jóvá
   (`wrong_project`).
4. **Tenant-izoláció**: az admin csak a saját települése tartalmát írhatja; a
   developer mindet.
5. **Szerep-emelés tiltva**: a `role` mezőt csak developer állíthatja.
6. **App Check**: a kliensek App Check tokent küldenek (a kikényszerítés a Play
   Store-os kiadás után kapcsolható be).

Részletek: `docs/SERVER_VALIDATION.md`, `docs/SZAKDOLGOZAT_BIZTONSAG.md`.

---

## 4. Cloud Functions

| Függvény | Jogosultság | Feladat |
|---|---|---|
| `redeemQr` | bejelentkezett | QR-jóváírás (validáció + pont + jutalom + ranglista) |
| `exportUserData` | saját | GDPR 20. cikk — adatexport |
| `deleteMyAccount` | saját | GDPR 17. cikk — saját fiók törlése |
| `adminDeleteUser` | developer | Másik felhasználó teljes törlése |
| `setUserBanned` | developer | Kitiltás / feloldás (visszafordítható) |
| `inviteAdmin` | developer | Admin meghívása e-mail alapján |
| `tripAnalytics` | admin/developer | Viselkedési analitika (településre szűrve vagy összesítve) |
| `seedProjectLeaderboards` | developer | A településenkénti ranglista feltöltése meglévő adatból |
| `notifyOnNewEvent` | trigger | Push-értesítés új eseményről |

---

## 5. Migrációs és karbantartó szkriptek

A `functions/scripts/` mappában. A legtöbb **nem igényel service accountot** —
a developer fiók bejelentkezésével (REST) dolgozik.

| Szkript | Feladat |
|---|---|
| `backfill-project-id.mjs` | `projectId` ráírása a régi tartalomra (idempotens, `--dry-run`) |
| `migrate-inline-images.mjs` | Beágyazott base64 képek átmozgatása Storage-ba (`--dry-run`, `--backup-dir`) |
| `cleanup-obsolete-station-fields.mjs` | Megszűnt állomás-mezők törlése (`funFact`, `extraInfo`) |
| `backfill-qr-codes.mjs` | A `qr_codes` leképezés feltöltése |
| `create-developer.mjs` | Developer fiók létrehozása/frissítése |

---

## 6. Skálázási megjegyzések

- Az admin jelenleg **kliensoldalon** szűr településre. Ez a mostani
  adatmennyiségnél (a képmigráció után a teljes tartalom ~30 KB) gyors; sok
  település/tartalom esetén érdemes `where('projectId','==',…)` szerveroldali
  szűrésre váltani (a backfill már lefutott, tehát minden dokumentumnak van
  `projectId`-ja).
- A `tripAnalytics` szerveroldalon aggregál, és csak a szükséges mezőket olvassa
  (`select`), így nem tölti le az összes felhasználói dokumentumot.
- A `user_progress` globális `totalPoints` mezője **nem** településenkénti; a
  települési pontot a `leaderboards` alkollekció, illetve az analitika az adott
  település állomásaiból számolja.
