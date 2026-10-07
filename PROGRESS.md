# Projekt állapot

Nagyvázsonyi turisztikai QR-pontgyűjtő rendszer — szakdolgozati projekt. Az
architektúra és a használat leírása a [README.md](README.md)-ben található; ez a
fájl a készültségi állapotot követi.

## Elkészült

### Mobilapp (Flutter)
- Anonim fiók névvel, egyedi névfoglalás tranzakcióval; opcionális e-mailes
  visszaállítás másik eszközön.
- QR-beolvasás állomásra és rendezvényre; a jóváírás kizárólag a szerveren
  (`redeemQr`), GPS-pozícióval és a kiadás településével.
- Offline működés: Firestore- és Hive-gyorsítótár, offline QR-sor hibaosztályozással,
  offline térképcsempék (helyi csempeszolgáltató), offline képek.
- Térkép, túranavigáció, gyalogos útvonal (Valhalla → OSRM → egyenes).
- Jutalmak (szerveroldali egyeztetéssel), települési ranglista, profil, előzmények.
- Rendezvények, szállás és vendéglátás, a település története, kapcsolat,
  hibabejelentés (offline is, valódi verziószámmal).
- Push-értesítés új rendezvényről (FCM topic), GDPR-adatexport és fióktörlés.
- App Check, Crashlytics, Performance Monitoring, akadálymentesítés.
- Adatkezelési tájékoztató (regisztrációkor és a profilból elérhető).
- Kötelező helymeghatározás állomásonként; offline kódfelismerés QR-lenyomattal.

### Adminisztrációs felület (React)
- Szerepkör-alapú belépés (admin / developer), white-label településkezelés.
- CRUD: túrák, állomások (térkép, helyben generált QR, PDF), rendezvények,
  szállások, vendéglátóhelyek, jutalmak, történet, elérhetőségek.
- Áttekintő napi pillanatképekkel, szerveroldali analitika, felhasználókezelés
  (meghívás, kitiltás, törlés), hibabejelentések, CSV-export, sötét mód.

### Backend és biztonság
- 12 Cloud Function (lásd README).
- Lezárt Firestore-szabályok: pontot, teljesített listát és feloldott jutalmat
  kliens nem írhat; tenant-izoláció; szerepkör-emelés tiltva; privát,
  település szerint elkülönített `qr_codes`, nyilvánosan csak a kód lenyomata.
- Atomi jóváírás (pont + ranglista egy tranzakcióban), önjavító utólépések.
- Indulásra kész: QR-migrációs szkript, konfigurációs kapcsolók
  (`ENFORCE_APP_CHECK`, `QR_LEGACY_FALLBACK`), hosting-konfiguráció kézi
  telepítéssel, indulási ellenőrzőlista: [docs/LAUNCH.md](docs/LAUNCH.md).

## Tesztek és minőség

| Ellenőrzés | Állapot |
|---|---|
| Admin: Vitest (195 teszt, 27 fájl) | zöld |
| Cloud Functions: node:test (109 teszt) | zöld |
| Szabályok + integráció Firestore-emulátor ellen (44 teszt) | zöld |
| Mobil: flutter test (118 teszt) | zöld |
| Lefedettség: functions lib 100% sor; admin 44%; mobil 45% (betöltött fájlok) | mérve, CI-ban is |
| ESLint (0 figyelmeztetés), flutter analyze | hibamentes |
| npm audit (admin, functions, tesztek) | 0 sebezhetőség |
| CI: GitHub Actions (admin + functions + rules-emulátor + Flutter) | bekötve |

## Ismert korlátok

- A helyszín-ellenőrzés a pozíció hiányát átengedi (kivéve a kötelező
  helymeghatározású állomásokat), a pozíció hamisítható.
- Az éles rendszer még a migráció előtti állapotban fut; az élesítés lépései:
  [docs/LAUNCH.md](docs/LAUNCH.md).
- A mobilfiók visszaállítási jelszava a névből képződik (tudatos egyszerűsítés).
- Admin e-mail-értesítések: nem implementált.
