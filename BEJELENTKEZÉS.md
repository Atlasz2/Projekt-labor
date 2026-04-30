# Bejelentkezes es Firebase Beallitas

Ez a dokumentum az aktualis, aktiv alkalmazasokhoz tartozik:

- admin (Vite): admin felulet
- mobile_app (Flutter): felhasznaloi app

## Fontos

A korabbi, gyokerben levo statikus admin.html admin.js admin.css felulet mar nem aktiv.
Az archivumban talalhato: legacy/root-cleanup-2026-04-14

## Admin belepes tesztelese

1. Inditas: npm run admin:dev
2. Nyisd meg: http://localhost:5173
3. Jelentkezz be admin fiokkal

## Firebase minimum beallitas

1. Firebase projekt legyen letrehozva
2. Authentication engedelyezve (Email/Password)
3. Firestore es Storage aktiv
4. Firestore rules deployolva a firestore.rules alapjan

Deploy parancs:

- firebase deploy --only firestore:rules

## Tipikus hibak

### missing or insufficient permissions

- Ellenorizd, hogy a bejelentkezett userhez tartozik-e users dokumentum
- Ellenorizd, hogy a kliens csak engedelyezett mezoket frissit
- Ellenorizd a frissen deployolt rules verziot

### Admin nem erheto el

- Gyoker URL mar nem admin.html
- Az aktualis admin URL: http://localhost:5173
