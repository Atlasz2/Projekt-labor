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
- QR-beolvasás (mobile_scanner), pontjóváírás, jutalom-feloldás
- Offline működés: Firestore cache, Hive, offline QR-várólista szinkronnal,
  offline térképcsempék és képek
- Interaktív térkép a túraútvonalakkal, esemény- és szálláslisták
- Ranglista (`public_leaderboard`), profil, beolvasási előzmények
- Crashlytics + Performance monitoring
- Natív splash screen (flutter_native_splash) és launcher ikonok

### Backend / biztonság
- Firestore security rules: szerepkör-alapú admin-ellenőrzés (UID-elsődleges),
  felhasználó csak saját progress-dokumentumát írhatja, monoton pontszabály,
  leaderboard-pontszám kereszt-ellenőrzése a `user_progress` ellen
- Storage rules: publikus olvasás, csak admin írás

## Tesztek, minőség

| Ellenőrzés | Állapot |
|---|---|
| Admin: Vitest (103 teszt, 13 fájl) | Zöld |
| Mobil: flutter test (22 teszt) | Zöld |
| Mobil: flutter analyze | Hibamentes |
| CI: GitHub Actions (admin lint/test/build + Flutter release build) | Bekötve |

## Ismert hiányosságok, korlátok

- **Esemény-QR beolvasás**: az admin generál QR-t az eseményekhez, de a mobil
  feldolgozó jelenleg csak az állomásokat ismeri fel *(folyamatban)*.
- **Kliensoldali pontszámítás**: a pontjóváírást a kliens írja a Firestore-ba;
  a szabályok a csökkentést tiltják, de a felfújást nem — teljes védelemhez
  Cloud Function-alapú szerveroldali validáció kellene *(a dolgozatban
  korlátként dokumentálva)*.
- Push értesítések: nem implementált.
- Admin email-értesítők: nem implementált.
