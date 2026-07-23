# Mobilapp frissítése kábel nélkül (Firebase App Distribution)

Cél: ne kelljen a telefont gépre dugni és `flutter run`-t futtatni. Ehelyett
minden `main`-re pusholt változás után a GitHub Actions **automatikusan buildeli
és feltölti** az APK-t a Firebase App Distribution-be, a telefonodra pedig
**push-értesítés** érkezik — egy koppintással frissítesz.

```
git push (main)  ──►  GitHub Actions
                        1. google-services.json visszaállítása (Secret)
                        2. flutter build apk --release
                        3. feltöltés App Distribution-be
                                    │
                                    ▼
                        push-értesítés a telefonodra → 1 koppintás = frissít
```

A workflow már készen áll (`.github/workflows/release.yml`). Az alábbi
**egyszeri** beállításokat kell elvégezned a fiókodban.

---

## 1. GitHub Secretek beállítása

A repó **Settings → Secrets and variables → Actions → New repository secret**
alatt két titkot kell felvenned.

### `GOOGLE_SERVICES_JSON_BASE64`

A `mobile_app/android/app/google-services.json` (a gépeden megvan, de titkos)
base64-kódolt tartalma. Állítsd elő:

- **PowerShell** (a mobile_app/android/app mappából):
  ```powershell
  [Convert]::ToBase64String([IO.File]::ReadAllBytes("google-services.json")) | Set-Clipboard
  ```
  (a vágólapra másolja — illeszd be a Secret értékébe)

- **vagy Git Bash / Linux:**
  ```bash
  base64 -w0 mobile_app/android/app/google-services.json
  ```

### `FIREBASE_SERVICE_ACCOUNT`

Egy service account JSON, amivel a CI feltölthet:

1. Firebase konzol → ⚙ **Project settings** → **Service accounts** fül
2. **Generate new private key** → letölt egy JSON-fájlt
3. A JSON **teljes tartalmát** másold be a Secret értékébe.

> Ha a feltöltés jogosultság-hibát ad, add hozzá a Google Cloud konzol → IAM
> alatt ehhez a service accounthoz a **Firebase App Distribution Admin**
> szerepet.

---

## 2. Tesztelői csoport a Firebase konzolban

1. Firebase konzol → **App Distribution** (bal oldali menü) → ha először
   nyitod meg, **Get started**.
2. **Testers & Groups** fül → **Add group** → a csoport neve pontosan:
   **`testers`** (a workflow ezt a nevet használja).
3. Add hozzá a **saját email-címedet** a csoporthoz.

---

## 3. A telefonod egyszeri beállítása

1. Az első feltöltés után a Firebase **meghívó emailt** küld a címedre.
2. A telefonon nyisd meg, fogadd el a meghívót, és telepítsd a **Firebase App
   Tester** appot (a link elvezet hozzá).
3. Engedélyezd az **ismeretlen forrásból** való telepítést (Android ezt kéri,
   mert nem a Play Store-ból jön).

Ezután minden új verziónál értesítést kapsz az App Tester appban, és egy
koppintással frissítesz.

---

## Használat

Ettől kezdve nincs más dolgod:

```bash
git push          # a main ágra
```

~5-10 perc múlva (a build ideje) jön az értesítés a telefonodra. A kiadási
jegyzet a commit üzenete lesz.

## Korlátok / megjegyzések

- **Csak Android.** iOS-hez a feltöltéshez macOS-runner és Apple-aláírás kell;
  ha kell, külön bekötjük.
- Ez **teljes APK-t** cserél (nem „élő" kódcsere) — tehát natív változás
  (új csomag) is átjön, nem csak a Dart-kód. Cserébe a build ~perceket vesz.
- A `develop` ágra pusholt build csak GitHub-artifactként töltődik fel
  (App Distribution csak `main`-ről megy ki), így a tesztelők csak a kész
  verziókat kapják.
- Ha a build a `google-services.json` visszaállításán bukna el, a
  `GOOGLE_SERVICES_JSON_BASE64` Secret hiányzik vagy hibás.
