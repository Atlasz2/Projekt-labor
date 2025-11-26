## Hozzájárulási útmutató

Köszi, hogy hozzájárulsz a Projekt-laborhoz! Ez a rövid leírás segít abban, hogy egységes módon dolgozzunk együtt.

1) Fork & branch workflow (ajánlott)
- Kliens oldali fejlesztéshez készíts forkot vagy hozz létre feature branchet a repóban.
- Branch nevei: `feature/<rövid-leírás>` vagy `fix/<rövid-leírás>`.

2) Fejlesztés
- Klónozás: `git clone https://github.com/Atlasz2/Projekt-labor.git`
- Válassz branch-et: `git checkout -b feature/nev`
- Telepítsd a függőségeket: `flutter pub get`
- Futtasd helyben: `flutter run -d edge` vagy `flutter run -d windows`

3) Commit üzenetek
- Rövid, tömör üzeneteket írjunk: `git commit -m "feat: add qr scan screen"`

4) Pull Request
- Push-olás után nyiss PR-t GitHubon és kérj review-t egy csapattárstól.
- A PR-nek tartalmaznia kell: rövid leírás, mi változott, hogyan tesztelhető.

5) CI és kódellenőrzés
- Minden PR futtatja majd a statikus ellenőrzéseket (ha beállítjuk a CI-t). Kérjük, javítsd a lint- és analizálási hibákat a merge előtt.

6) Egyéb
- Ne tölts fel érzékeny adatot (pl. API kulcs, service account file). A `lib/config/firebase_config.dart` jelenleg placeholder-eket tartalmaz.

Köszönjük! Ha kérdésed van a folyamatban, írj ide a repo Issues részébe vagy jelezd Messenger-en.
