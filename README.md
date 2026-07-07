# Nagyvazsonyi Turist App

Turisztikai pontgyujto mobilalkalmazas Nagyvazsony szamara, admin webes fellolettel.

## Projekt attekintes

A rendszer ket fo komponensbol all:
- **Flutter mobilapp** – turistak szamara: utvonalak, QR-beolvaso, pontgyujtes, offline tamogatas
- **React admin panel** – tartalomkezelok szamara: allomások, turak, események, szallasok, ettermek kezelese

---

## 2026-05-02 Minosegi javitasok

Admin oldali clean-code es stabilitasi refaktor keszult:
- Hook refaktor: a kezdeti adatbetoltes aszinkron inditasa kesleltetett effect-triggerrel, hogy ne legyen set-state-in-effect lint hiba.
- Hoisting/hivatkozasi tisztitas: a nagyobb oldalak adatbetolto rutinjai atalakitasra kerultek, hogy ne legyen use-before-declare jellegu kockazat.
- Prop contractek: a belso ujrahasznosithato komponensek (pl. megerosito dialog, foto-racs, terkep valasztok) PropTypes validaciot kaptak.
- Logging tisztitas: felesleges console hivasok eltavolitva vagy fallback kommenttel kivaltva.
- Admin tesztalap: Vitest bevezetve, kezdo automata teszttel a safeString utilhoz.

## Technologiai stack

### Admin (webes felulet)
| Konyvtar | Verzio | Szerep |
|---|---|---|
| React | 19 | UI framework |
| Vite | 7 | Build tool / dev server |
| Material UI | 7 | Komponens konyvtar |
| Firebase JS SDK | 12 | Firestore + Auth + Storage |
| TanStack Query | 5 | Szerver-allapot, cache, automatikus ujratoltés |
| React Router | 7 | Oldal-navigacio |
| @react-google-maps/api | 2 | Google Maps terkep-valaszto |
| jsPDF | 2 | QR kod PDF export |

### Mobilapp (Flutter)
| Csomag | Verzio | Szerep |
|---|---|---|
| Flutter | 3.10+ | Framework |
| firebase_core | 4.4 | Firebase inicializacio |
| cloud_firestore | 6.1 | Adatbazis + offline cache |
| firebase_auth | 6.1 | Felhasznalo-azonositas |
| hive_flutter | - | Helyi perzisztencia (Hive) |
| mobile_scanner | 7 | QR kod beolvaso |
| flutter_map | 7 | Terkep megjelenites |
| google_maps_flutter | 2.13 | Google Maps |
| geolocator | 14 | GPS helymeghatározas |
| connectivity_plus | 6 | Halozati allapot figyelése |
| firebase_crashlytics | 5 | Crash reporting |
| firebase_performance | 0.11 | Teljesitmeny monitorozas |

### Backend / infrastruktura
| Szolgaltatas | Szerep |
|---|---|
| Firebase Firestore | Realtime adatbazis (NoSQL) |
| Firebase Authentication | Google / email bejelentkezes |
| Firebase Storage | Kep / media tarolas |
| Firebase Crashlytics | Mobil crash analytics |
| Firebase Performance | API/kepernyo latencia meres |

---

## Firebase adatmodell

### `stations` kollekcio
```
{
  name:                 string,
  description:          string,
  latitude:             number,
  longitude:            number,
  points:               number,
  qrCode:               string,   // egyedi QR ertek
  tripId:               string,   // refs trips.id
  funFact:              string,
  unlockContent:        string,   // QR beolvasas utan latszik
  extraInfo:            string,
  photos:               [{url: string}],
  photoUrls:            [string],
  imageUrl:             string,   // borítokep
  unlockContentImageUrl:string
}
```

### `trips` kollekcio
```
{
  name:        string,
  description: string,
  difficulty:  string,
  distance:    number,
  duration:    number,
  stationIds:  [string]
}
```

### `events` kollekcio
```
{
  name:        string,
  date:        string,
  description: string,
  location:    string,
  points:      number,
  qrCode:      string,
  photos:      [{url: string}],
  photoUrls:   [string],
  imageUrl:    string
}
```

### `accommodations` kollekcio
```
{
  name:          string,
  type:          hotel | guesthouse | apartment | campsite,
  pricePerNight: string,
  capacity:      string,
  description:   string,
  photos:        [{url: string}],
  photoUrls:     [string],
  imageUrl:      string
}
```

### `restaurants` kollekcio
```
{
  name:        string,
  type:        hungarian | fish | cafe | pizzeria | icecream | bar,
  cuisine:     string,
  priceRange:  string,
  description: string,
  photos:      [{url: string}],
  photoUrls:   [string],
  imageUrl:    string
}
```

### `about` kollekcio
```
{
  year:        string,
  title:       string,
  description: string,
  imageUrl:    string   // opcionalis, a tortenet esemeny kepje
}
```

### `users` kollekcio
```
{
  email:     string,
  role:      admin | user,
  points:    number,
  name:      string,
  createdAt: timestamp
}
```

### `achievements` kollekcio
```
{
  title:       string,
  description: string,
  threshold:   number,  // pont kuszob
  icon:        string
}
```

---

## Admin architektura

```
admin/src/
├── App.jsx                        # Gyoker: QueryClientProvider + AdminAuthProvider + lazy routes
├── context/
│   └── AdminAuthContext.jsx       # Egyetlen auth forrás; logout(); isLoggedIn, userRole, userEmail
├── hooks/
│   ├── useFirestoreCollection.js  # Generikus CRUD hook (TanStack Query)
│   └── usePhotoManager.js         # Fotokezeles: feltoltes, eltavolitás, Storage torles
├── components/
│   ├── Layout.jsx                 # Oldalsav, navigació, kijelentkezes
│   ├── PhotoGrid.jsx              # Ujrahasznosithato foto-rasteres feltolto UI
│   └── ConfirmDialog.jsx          # MUI modal megerosito dialog
├── pages/
│   ├── Login.jsx                  # Firebase Auth bejelentkezes
│   ├── Dashboard.jsx              # Statisztikak, gyors muveletek
│   ├── Stations.jsx               # Allomas CRUD – terkep, QR PDF export, 4-szekcious modal
│   ├── Trips.jsx                  # Tura CRUD
│   ├── Events.jsx                 # Rendezveny CRUD + foto + QR
│   ├── Accommodations.jsx         # Szallas CRUD + foto
│   ├── Restaurants.jsx            # Vendeglatohely CRUD + foto
│   ├── Users.jsx                  # Felhasznalok es jogosultsagok
│   ├── Achievements.jsx           # Dijak, jelvények kezelese
│   ├── Map.jsx                    # Interaktiv terkep az osszes allomással
│   ├── BugReports.jsx             # Mobil hibajelentesek megtekintése
│   ├── SeedDatabase.jsx           # Adatbazis feltoltes teszt-adatokkal
│   ├── Contact.jsx                # Kapcsolati informaciok szerkesztese
│   └── About.jsx                  # Nagyvazsony tortenete timeline szerkesztese – imageUrl feltoltesssel
└── utils/
    ├── photoHelpers.js            # normalizePhotosFromDoc() + buildPhotoFields()
    ├── qrHelpers.js               # getQrValue() + getQrImageUrl()
    ├── safeString.js              # Firestore adatokhoz biztonságos string-konverzio
    ├── imageUpload.js             # Firebase Storage feltoltes 5mp timeout + base64 fallback
    └── resolveUserRole.js         # UID / email alapjan role lekerdezés
```

### Kulcs tervezési döntések

**TanStack Query** (`useFirestoreCollection`):
- A kollekcio neve lesz a cache kulcs (`['events']`, `['stations']`, stb.)
- `staleTime: 60s` – visszanavigalaskor nincs felesleges ujratoltés
- `invalidateQueries` mutacio utan – automatikus frissites

**Foto-pipeline** (`usePhotoManager` + `buildPhotoFields`):
- Feltoltes: Firebase Storage, 5s timeout, base64 fallback ha a Storage nem valaszol
- Menteskor: `photos[{url}]`, `photoUrls[]`, `imageUrl` – mindhármat irja, Flutter barmely mezőt olvassa
- Torleskor: `commitRemovals()` – csak mentés siker utan torli a Storage fajlt (cancel nem torli)

**AdminAuthContext**:
- Egyetlen `onAuthStateChanged` szukription az egesz alkalmazasban
- `logout()` = `signOut(auth)`, a context kezeli a navigaciot
- `resolveUserRole()` – UID, majd email-doc, majd email-query fallback lancban

---

## Flutter architektura

```
mobile_app/lib/
├── main.dart                         # Init: Hive, Firebase, Crashlytics, Performance, offline-cache
├── firebase_options.dart             # Auto-generalt Firebase config
├── screens/
│   ├── auth_gate.dart                # Bejelentkezes kapujá (Firebase Auth stream)
│   ├── name_screen.dart              # Felhasznalonev beallitas (jatekos profil)
│   ├── main_menu_screen.dart         # Fooldal: turak, terkep, profil, QR
│   ├── map_trips_screen.dart         # Interaktiv terkep az utvonalakkal
│   ├── camera_screen.dart            # QR kod beolvaso
│   ├── unlocked_content_screen.dart  # QR beolvasas utan feltart tartalom
│   ├── history_screen.dart           # Beolvasasi elozmenyek
│   ├── profile_screen.dart           # Pont egyenleg, jelvények
│   ├── achievement_progress_screen.dart # Dijak előrehaladasa
│   ├── events_screen.dart            # Esemenyek listaja
│   ├── accommodation_screen.dart     # Szallasok listaja
│   ├── contact_screen.dart           # Kapcsolat oldal
│   └── bug_report_screen.dart        # Hibabejelentes
└── services/
    ├── bootstrap_service.dart        # App indit ellenorzesek
    ├── local_cache.dart              # Hive wrapperek
    ├── offline_image_service.dart    # Kepek helyi cachealasa
    ├── offline_sync_service.dart     # Adatok letoltese offline hasznalatra
    ├── offline_tiles_service.dart    # Terkep csempek offline cacheje
    ├── pending_qr_sync_service.dart  # Offline QR beolvasasok szinkronizalása
    └── qr_processing_service.dart    # QR kod feldolgozas, pont szamitas
```

### Offline tamogatas stratégia

1. **Firestore offline cache** (`Settings.persistenceEnabled = true`) – Firestore automatikusan cacheli a dokumentumokat
2. **Hive lokalis tarolas** – Gyors eleres, QR elozmények, felhasznalo adatok
3. **Pending QR szinkron** – Ha offline QR-t olvasnak be, `pending_qr_sync_service` menti Hive-ba, majd szinkronizal ha halozat visszater
4. **Offline terkep csempek** – `offline_tiles_service` letolti a terkep csempeket elore
5. **Kepek cacheje** – `offline_image_service` local fajlba menti az allomask kepeeit

---

## Fejlesztesi kornyezet

### Elokovetelmeny

- Node.js 18+
- Flutter SDK 3.10+
- Firebase CLI (`npm install -g firebase-tools`)
- Google Maps API kulcs (`.env.local` ban)

### Telepites

```bash
# Gyoker dependencies
npm install

# Admin dependencies
npm --prefix admin install

# Flutter dependencies
cd mobile_app
flutter pub get
```

### Futtatás

```bat
# Windows – mindkét app egyszerre
start.bat
```

Vagy manuálisan:
```bash
# Admin (http://localhost:5173)
npm --prefix admin run dev

# Flutter Windows desktop
flutter run --project-dir mobile_app -d windows
```

### Build

```bash
# Admin production build
npm run admin:build

# Flutter
cd mobile_app
flutter build windows
flutter build apk
```

### Kornyezeti valtozok

`admin/.env.local`:
```
VITE_FIREBASE_API_KEY=...
VITE_FIREBASE_AUTH_DOMAIN=...
VITE_FIREBASE_PROJECT_ID=...
VITE_FIREBASE_STORAGE_BUCKET=...
VITE_FIREBASE_MESSAGING_SENDER_ID=...
VITE_FIREBASE_APP_ID=...
VITE_GOOGLE_MAPS_API_KEY=...
```

---

## Firebase biztonsag

### Firestore szabalyok (`firestore.rules`)

- **Olvasas**: barmely bejelentkezett felhasznalo
- **Iras `users` gyjtemeny**: csak a sajat doc-jat modosithatja (role mezo kivételevel)
- **Iras tobbi gyjtemeny**: csak `admin` role-u felhasznalo
- **`isAdmin()`**: UID-alapu elsodleges ellenorzes; email-doc fallback csak ha a doc `uid` mezoje megegyezik a caller UID-javal
- **`user_progress` letrehozas**: felhasznalo csak nullazott szamlalokkal hozhatja letre (totalPoints == 0, ures completed-listak)
- **`user_progress` iras**: felhasznalo csak monoton novelhet pontot / allomast (csokkenetes tiltva)
- **`public_leaderboard` iras**: pontszam csak akkor fogadott el, ha megegyezik a `user_progress.totalPoints`-al (Firestore cross-referencia)

### Ismert biztonsagi korlatok

A pontjovairast a kliens szamolja es irja a Firestore-ba. A szabalyok a
pontcsokkentest es a hamis kezdoertekkel valo letrehozast tiltjak, de egy
modositott kliens az update-agon tetszoleges mertekben novelhetne a sajat
pontszamat, es a `stations`/`events` kollekciok publikus olvashatosaga miatt
a QR-ertekek beolvasas nelkul is lekerdezhetok. Teljes vedelemhez a beolvasast
szerveroldalon kellene validalni (Cloud Function: a kliens csak a nyers kodot
kuldi be, a pontjovairast a fuggveny vegzi Admin SDK-val). Ez a projekt
kereteben tudatosan vallalt korlat; a szakdolgozat reszletesen targyalja.

### Storage szabalyok (`storage.rules`)

- **Olvasas**: nyilvanos
- **Iras**: csak bejelentkezett, admin role-u felhasznalok

---

## Projekt statusz

| Funkció | Státusz |
|---|---|
| Admin bejelentkezes (Firebase Auth) | Kész |
| Allomás CRUD + terkep + QR PDF | Kész |
| Tura CRUD + allomas-rendelés | Kész |
| Rendezvény CRUD + foto + QR | Kész |
| Szallas CRUD + foto | Kész |
| Vendeglatohely CRUD + foto | Kész |
| Felhasznalók és jogosultságok | Kész |
| Dijak / jelvények | Kész |
| Hibabejelentések admin kezelőfelület | Kész |
| Flutter auth + profil | Kész |
| Flutter QR beolvaso | Kész |
| Flutter pont szamlas | Kész |
| Esemény-QR beolvasas (mobil) | Kész |
| Tranzakcios pontjovairas (dupla jóváírás ellen) | Kész |
| Flutter offline mod | Kész |
| Flutter terkep | Kész |
| Admin UI teljes újratervezés (kék/slate téma, Inter betűtípus) | Kész |
| Dark mode (Admin panel, localStorage-perzisztált) | Kész |
| Nagyvázsony Történet képfeltöltés | Kész |
| Flutter Push notifications | Nem implementalt |
| Admin email ertesitok | Nem implementalt |

---

## Fejleszto

Szakdolgozati projekt – Nagyvazsony turisztikai QR pontgyujto rendszer.
Firebase projektazonosito: `projekt-labor-a4b1c`
