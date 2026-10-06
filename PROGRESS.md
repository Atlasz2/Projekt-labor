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

### Adminisztrációs felület (React)
- Szerepkör-alapú belépés (admin / developer), white-label településkezelés.
- CRUD: túrák, állomások (térkép, helyben generált QR, PDF), rendezvények,
  szállások, vendéglátóhelyek, jutalmak, történet, elérhetőségek.
- Áttekintő napi pillanatképekkel, szerveroldali analitika, felhasználókezelés
  (meghívás, kitiltás, törlés), hibabejelentések, CSV-export, sötét mód.

### Backend és biztonság
- 12 Cloud Function (lásd README).
- Lezárt Firestore-szabályok: pontot, teljesített listát és feloldott jutalmat
  kliens nem írhat; tenant-izoláció; szerepkör-emelés tiltva; privát `qr_codes`.

## Tesztek és minőség

| Ellenőrzés | Állapot |
|---|---|
| Admin: Vitest (161 teszt, 22 fájl) | zöld |
| Cloud Functions: node:test (88 teszt) | zöld |
| Szabályok + integráció Firestore-emulátor ellen (40 teszt) | zöld |
| Mobil: flutter test (101 teszt) | zöld |
| ESLint (0 figyelmeztetés), flutter analyze | hibamentes |
| npm audit (admin, functions, tesztek) | 0 sebezhetőség |
| CI: GitHub Actions (admin + functions + rules-emulátor + Flutter) | bekötve |

## Ismert korlátok

- A helyszín-ellenőrzés a pozíció hiányát átengedi, a pozíció hamisítható.
- A mobilfiók visszaállítási jelszava a névből képződik (tudatos egyszerűsítés).
- Admin e-mail-értesítések: nem implementált.
