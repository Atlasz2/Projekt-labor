# Projekt állapot

Nagyvázsonyi turisztikai QR-pontgyűjtő rendszer — szakdolgozati projekt.
A technológiai stack, az adatmodell és az architektúra részletes leírása a [README.md](README.md)-ben található; ez a fájl csak a készültségi állapotot követi.

## Elkészült funkciók

### Admin panel (React 19 + Vite + MUI + TanStack Query)
- Firebase Auth bejelentkezés, admin-jogosultság ellenőrzéssel
- CRUD felületek: állomások (térkép + QR PDF export), túrák, események, szállások, éttermek, jutalmak, Nagyvázsony-történet
- Felhasználók és jogosultságok kezelése, CSV-export
- Hibabejelentések (mobil appból érkező) kezelőfelülete
- Dashboard statisztikákkal, napi snapshot mentéssel (`stats_daily`)
- Dark mode (localStorage-perzisztált, MUI témával szinkronban)

### Mobilapp (Flutter)
- Firebase Auth + játékosprofil (felhasználónév-foglalás tranzakcióval)
- QR-beolvasás (mobile_scanner): állomás- ÉS esemény-QR-ek, tranzakciós
  pontjóváírás (párhuzamos feldolgozás nem duplázhat), jutalom-feloldás
- Offline működés: Firestore cache, Hive, offline QR-várólista szinkronnal,
  offline térképcsempék és képek
- Interaktív térkép a túraútvonalakkal, esemény- és szálláslisták
- Ranglista (`public_leaderboard`), profil, beolvasási előzmények
- Crashlytics + Performance monitoring
- Push értesítések (FCM): feliratkozás az esemény-topicra, a szerver új
  esemény létrehozásakor küld (notifyOnNewEvent Cloud Function)
- Natív splash screen (flutter_native_splash) és launcher ikonok

### Backend / biztonság
- **Szerveroldali QR-validáció**: redeemQr Cloud Function (Node 22) — a
  kliens csak a nyers kódot küldi, a jóváírás Admin SDK-val fut; privát
  `qr_codes` leképező kollekció ütközésvédelemmel, admin oldali automatikus
  karbantartással és backfill szkripttel (deploy: Blaze-csomag szükséges,
  részletek: docs/SERVER_VALIDATION.md)
- Firestore security rules: szerepkör-alapú admin-ellenőrzés (UID-elsődleges),
  felhasználó csak saját progress-dokumentumát írhatja, monoton pontszabály,
  leaderboard-pontszám kereszt-ellenőrzése a `user_progress` ellen
- Storage rules: publikus olvasás, csak admin írás

## Tesztek, minőség

| Ellenőrzés | Állapot |
|---|---|
| Admin: Vitest (116 teszt, 14 fájl) | Zöld |
| Mobil: flutter test (49 teszt, fake_cloud_firestore-ral) | Zöld |
| Mobil: flutter analyze | Hibamentes |
| Cloud Functions: node --test (22 teszt, in-memory Firestore-stub) | Zöld |
| Firestore rules + redeem-core emulátor ellen (28 teszt, támadási forgatókönyvek) | Zöld |
| CI: GitHub Actions (admin + functions + rules-emulátor + Flutter) | Bekötve |

A biztonsági architektúra szakdolgozatba emelhető leírása:
[docs/SZAKDOLGOZAT_BIZTONSAG.md](docs/SZAKDOLGOZAT_BIZTONSAG.md).

## Ismert hiányosságok, korlátok

- **Szerveroldali validáció deploy**: a redeemQr Cloud Function kódja és
  tesztjei készek, de a deploy Blaze-csomagot igényel; addig az app a
  legacy kliensoldali úton működik. A végső rules-lockdown lépései:
  docs/SERVER_VALIDATION.md.
- Admin email-értesítők: nem implementált.
