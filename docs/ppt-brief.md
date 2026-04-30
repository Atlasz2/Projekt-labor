# PPT Segédlet – AI Promkt a Szakdolgozati Előadáshoz

Ezt a fájlt adjuk az AI-nak (pl. ChatGPT, Gemini, Copilot), hogy ebből PowerPoint prezentációt készítsen.

---

## INSTRUKCIÓ AZ AI SZÁMÁRA

Készíts egy 12-15 diás PowerPoint prezentációt az alábbi szakdolgozati projektből.
A prezentáció egy ~15 perces szakdolgozati védésre készül. Legyen szakmai, de érthető.
Minden diának legyen: cím, 3-5 rövid bullet pont (max 1 sor/pont), és opcionálisan egy diagram / illusztracio javaslat.
A nyelv: Magyar.

---

## PROJEKT ÖSSZEFOGLALÓ

**Projekt neve:** Nagyvázsonyi Turisztikai QR Pontgyűjtő Rendszer
**Típus:** Szakdolgozat – Mobil + Web alkalmazás
**Firebase azonosító:** projekt-labor-a4b1c

### Mi ez a rendszer?
Egy teljes turisztikai digitalizációs rendszer Nagyvázsony számára, amely:
- Turistákat ösztönöz az látványosságok felkeresésére QR kódos pontgyűjtéssel
- Lehetővé teszi az útvonalak, állomások és tartalmak kezelését admin felületen
- Offline módban is működik, internethiány esetén is használható

---

## TECHNIKAI STACK

### Admin webes felület
- React 19 + Vite 7 (SPA, gyors fejlesztés)
- Material UI 7 (professzionális megjelenés)
- TanStack Query 5 (szerver-állapot kezelés, automatikus cache)
- Firebase JS SDK 12 (Firestore, Auth, Storage)
- React Router 7 (SPA navigáció)
- Google Maps API (térképes helyszín-kijelölés)
- jsPDF (QR kód PDF nyomtatás)

### Flutter mobilalkalmazás
- Flutter 3.10+ (iOS + Android + Windows egyszerre)
- cloud_firestore 6.1 (realtime adatbázis + offline cache)
- mobile_scanner 7 (QR kód beolvasó)
- flutter_map 7 + google_maps_flutter 2.13 (térkép)
- geolocator 14 (GPS helymeghatározás)
- hive_flutter (helyi gyors tárolás)
- firebase_crashlytics + firebase_performance (monitoring)
- connectivity_plus (hálózati állapot figyelés)

### Backend infrastruktúra
- Firebase Firestore (NoSQL adatbázis, valós idejű szinkron)
- Firebase Authentication (Google + email bejelentkezés)
- Firebase Storage (képek, médiafájlok)
- Firebase Crashlytics (mobil crash riport)
- Firebase Performance Monitoring

---

## FŐBB FUNKCIÓK

### Mobilalkalmazás (turista nézetből)
1. **QR kód beolvasó** – állomásokat lehet "checkinelni"
2. **Pontgyűjtés** – minden beolvasás pontot ér, ranglista
3. **Feltárt tartalom** – QR beolvasás után exkluzív helytörténet jelenik meg
4. **Interaktív térkép** – GPS-alapú, offline is elérhető útvonalak
5. **Offline mód** – internet nélkül is működik (Firestore + Hive cache)
6. **Jelvények / díjak** – gamification elemek
7. **Rendezvények, szállások, éttermek** listája
8. **Hibabejelentés** – felhasználók visszajelzést küldhetnek

### Admin webes felület (tartalomkezelők számára)
1. **Állomás-kezelő** – GPS koordináta, QR kód, fotók, feltárt tartalom
2. **Túra szerkesztő** – állomások sorrendbe rendezése
3. **Rendezvény, szállás, étterem** CRUD
4. **Felhasználó-kezelés** – role-ok (admin/user), pontok
5. **QR PDF export** – nyomtatható QR kódok
6. **Adatbázis seeder** – teszt adatok feltöltése
7. **Hibajelentések** adminisztrátor nézet
8. **Interaktív térkép** – összes állomás egy helyen

---

## RENDSZERARCHITEKTÚRA (diagramhoz)

```
[Tourist Mobile App]          [Admin Web Panel]
  Flutter 3.10+                 React 19 + Vite
  iOS / Android / Windows       http://localhost:5173
       |                               |
       v                               v
  [Firebase SDK]              [Firebase JS SDK]
       |                               |
       v                               v
+--------------+    +------------------+    +------------------+
| Firestore    |    | Firebase Auth    |    | Firebase Storage |
| (NoSQL DB)   |    | (Google + email) |    | (képek, QR)      |
+--------------+    +------------------+    +------------------+
       |
  [Offline Cache]
  Firestore persist + Hive
```

---

## ADATMODELL (Firestore)

Főbb kollekcók:
- **stations** – állomások (GPS, QR, feltárt tartalom, fotók)
- **trips** – túrák (állomások sorrendje, távolság, nehézség)
- **events** – rendezvények
- **accommodations** – szállások
- **restaurants** – éttermek
- **users** – felhasználók (role, pontszám)
- **achievements** – jelvények (pont küszöb, ikon)

Fotók kompatibilitása: minden elem ír `photos[{url}]`, `photoUrls[]`, `imageUrl` mezőket egyszerre, így a mobil bármelyik formátumot tudja olvasni.

---

## OFFLINE STRATÉGIA

1. **Firestore native cache** – `persistenceEnabled: true`, `CACHE_SIZE_UNLIMITED`
2. **Hive lokális tárolás** – QR előzmények, profil adatok gyorsan elérhetők
3. **Pending QR sync** – offline QR beolvasások tárolása, majd szinkronizálás
4. **Offline térképcsempék** – előre letöltött csempék
5. **Képek offline cache** – helyi fájlba mentett állomás fotók

---

## BIZTONSÁGI MEGOLDÁSOK

- **Firestore Rules** – csak admin role írhat tartalmat, user csak saját dokumentumát módosíthatja (role mező kivételével)
- **Storage Rules** – csak bejelentkezett adminok tölthetnek fel
- **Auth context** – egyetlen Firebase auth forrás, duplikált subscription-ok eltávolítva
- **Role ellenőrzés** – UID + email fallback lánc (`resolveUserRole`)

---

## CLEAN CODE ELVEK (technikai részlet ha kell)

- **TanStack Query** – nincs manuális loading/error state, automatikus cache és refetch
- **useFirestoreCollection** – generikus CRUD hook, 3 sor a lapokban
- **usePhotoManager** – fotó feltöltés, eltávolítás, Storage cleanup egységesen
- **PhotoGrid komponens** – újrahasználható fotórács, nincs copy-paste
- **AdminAuthContext** – egyetlen auth subscription az egész adminban
- **photoHelpers / qrHelpers** – shared utils, eliminálja a duplikált kódot

---

## FEJLESZTÉSI KIHÍVÁSOK (spoke: tanulságok)

1. **Firebase Storage timeout** – 5 másodperces timeout + base64 inline fallback megoldja a lassú hálózatot
2. **Offline QR szinkronizálás** – ha nincs net, Hive-ba kerül, majd sync visszajelzéssel
3. **Fotók multi-platform kompatibilitás** – web és mobil különböző mezőket vár, mindkettőt egyszerre kell írni
4. **Role-alapú hozzáférés** – Firestore rules + kliens-oldali ellenőrzés kétszeres védelmet nyújt
5. **Reaktív adatfrissítés** – TanStack Query cache invalidation helyettesíti a manuális fetch() újrahívásokat

---

## JAVASOLT DIA-STRUKTÚRA

1. **Cím dia** – Projekt neve, fejlesztő, dátum
2. **Motiváció / Probléma** – Miért kell ez Nagyvázsonynak?
3. **Megoldás áttekintése** – 2 komponens (app + admin)
4. **Tech stack** – táblázat / logo grid
5. **Rendszerarchitektúra** – diagram
6. **Mobilapp funkciók** – képernyőképek vagy mockup
7. **Admin felület** – képernyőkép, CRUD
8. **Adatmodell** – Firestore kollekcók
9. **Offline stratégia** – 5 rétegű offline megoldás
10. **QR kód folyamat** – lépésről lépésre (scan → pontok → feltárt tartalom)
11. **Biztonság** – Firestore rules, auth
12. **Clean code / architektura** – hooks, utils, context
13. **Fejlesztési tanulságok** – 3-4 kihívás + megoldás
14. **Eredmények / demo** – mi működik, mit lehetne folytatni
15. **Köszönetnyilvánítás / Kérdések**

---

## MEGJEGYZÉS

Ha vizuálisan szeretnéd – a dia 6-7-hez kérj képernyőképeket az alkalmazásból, és illeszd be a prezentációba.
A dia 4-hez egy logo-grid jól mutat (Firebase, Flutter, React, MUI ikonokkal).
