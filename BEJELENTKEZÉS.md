# 🔐 Bejelentkezési Adatok és Konfiguráció

## ⚠️ Jelenlegi Státusz

**Firebase konfiguráció szükséges!**

Az alkalmazás teljes működéséhez kell egy Firebase projekt.

## 🚀 Gyors Kezdés (Demo Fiók)

### 1. Firebase Projekt Létrehozása

**Lépések:**
1. Mérj ide: https://console.firebase.google.com/
2. Kattints: "Projekt létrehozása"
3. Adj meg egy nevet: `tour-trail-app` (vagy bármilyen más)
4. Engedélyezd a Google Analytics-et (opcionális)
5. Várd meg az inicializálást

### 2. Firebase Authentikáció Engedélyezése

1. Lépj be a Firestore Settings-be
2. **Authentication** → "Get started"
3. Válaszd ki: **Email/Password**
4. Engedélyezd az "Email/password" opciót
5. Kattints **Save**

### 3. Firestore Adatbázis Beállítása

1. **Firestore Database** → "Create database"
2. Válaszd: **Start in test mode** (fejlesztéshez)
3. Válaszd a legközelebbi régiót (EU-central1)
4. Kattints **Create**

### 4. Firebase Credentials Másolása

1. Menj az **Settings** (fogaskerék) → **Project settings**
2. Görgetess le a **Web apps** szekcióhoz
3. Kattints az alkalmazásodra vagy hozz létre újat
4. Másolj ki az alábbi értékeket:

```javascript
const firebaseConfig = {
  apiKey: "YOUR_API_KEY",
  authDomain: "YOUR_AUTH_DOMAIN",
  projectId: "YOUR_PROJECT_ID",
  storageBucket: "YOUR_STORAGE_BUCKET",
  messagingSenderId: "YOUR_MESSAGING_SENDER_ID",
  appId: "YOUR_APP_ID"
};
```

### 5. .env.local Fájl Frissítése

Frissítsd a projekt gyökér könyvtárában lévő `.env.local` fájlt:

```env
REACT_APP_FIREBASE_API_KEY=YOUR_API_KEY
REACT_APP_FIREBASE_AUTH_DOMAIN=YOUR_AUTH_DOMAIN
REACT_APP_FIREBASE_PROJECT_ID=YOUR_PROJECT_ID
REACT_APP_FIREBASE_STORAGE_BUCKET=YOUR_STORAGE_BUCKET
REACT_APP_FIREBASE_MESSAGING_SENDER_ID=YOUR_MESSAGING_SENDER_ID
REACT_APP_FIREBASE_APP_ID=YOUR_APP_ID
```

### 6. Szerver Újraindítása

Állítsd le az `npm start` processzet (Ctrl+C) és indítsd újra:
```bash
npm start
```

## 🧪 Test Fiók Létrehozása

### Admin Fiók (teljes hozzáférés)

**Email**: admin@nagyvazsony.hu  
**Jelszó**: Admin123456!

**Létrehozás lépések:**
1. Nyisd meg az alkalmazást: http://localhost:3000
2. Kattints "Regisztráció"
3. Add meg az adatokat fent
4. Regisztrálj

### Reguláris Felhasználó Fiók

**Email**: user@nagyvazsony.hu  
**Jelszó**: User123456!

**Létrehozás lépések:**
1. Ugyanaz, mint az admin fióknál
2. Ez egy normál felhasználó lesz

## 📱 Admin Jogosultságok Beállítása

Admin fiók engedélyezéséhez:

1. Mérj ide: https://console.firebase.google.com/
2. **Firestore Database** → **Collections**
3. Hozz létre új collection: `admin_users`
4. Add hozzá a dokumentumot:

```json
{
  "uid": "ADMIN_UID_ITT",
  "email": "admin@nagyvazsony.hu",
  "role": "admin",
  "permissions": [
    "manage_trails",
    "manage_stations",
    "manage_users",
    "view_analytics"
  ]
}
```

**UID megtalálása:**
1. Firebase Console → **Authentication**
2. Keresd meg az admin usert
3. Másold ki az UID-et

## 🔒 Biztonsági Szabályok Beállítása

Másolj be az alábbi Firestore Security Rules-ot:

**Firebase Console → Firestore → Rules**

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Public read for trails and stations
    match /trails/{trailId} {
      allow read: if true;
      allow write: if isAdmin();
    }
    
    match /stations/{stationId} {
      allow read: if true;
      allow write: if isAdmin();
    }
    
    // User-specific data
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    match /user_progress/{progressId} {
      allow read: if request.auth != null && 
                    resource.data.userId == request.auth.uid;
      allow create, update: if request.auth != null && 
                              request.resource.data.userId == request.auth.uid;
    }
    
    match /qr_codes/{qrId} {
      allow read: if request.auth != null;
      allow write: if isAdmin();
    }
    
    match /admin_users/{adminId} {
      allow read: if isAdmin();
      allow write: if isSuperAdmin();
    }
    
    function isAdmin() {
      return request.auth != null && 
             exists(/databases/$(database)/documents/admin_users/$(request.auth.uid));
    }
    
    function isSuperAdmin() {
      return isAdmin() &&
             get(/databases/$(database)/documents/admin_users/$(request.auth.uid)).data.role == 'admin';
    }
  }
}
```

## 🧩 Demo Adatok Feltöltése (Opcionális)

### 1. Túraútvonalak

Firestore → Collections → Create `trails`

**Dokumentum 1:**
```json
{
  "id": "trail_001",
  "name": "Nagyvázsony Vár Túra",
  "description": "Történelmi séta Nagyvázsony várának környékén",
  "difficulty": "közepes",
  "duration": 120,
  "distance": 5.2,
  "stationIds": ["station_001", "station_002"],
  "startPoint": {
    "latitude": 47.0333,
    "longitude": 17.7167,
    "name": "Kinizsi Vár"
  },
  "endPoint": {
    "latitude": 47.0400,
    "longitude": 17.7200,
    "name": "Kilátópont"
  },
  "imageUrl": "https://via.placeholder.com/400x300?text=Trail",
  "isActive": true,
  "createdAt": "2026-02-03T10:00:00Z"
}
```

### 2. Állomások

Firestore → Collections → Create `stations`

**Dokumentum 1:**
```json
{
  "id": "station_001",
  "trailId": "trail_001",
  "name": "Kinizsi Vár",
  "description": "XV. századi vár, Kinizsi Pál egykori birtoka",
  "location": {
    "latitude": 47.0333,
    "longitude": 17.7167
  },
  "radius": 50,
  "order": 1,
  "pointsValue": 10,
  "content": {
    "text": "A várat a 15. században építették..."
  },
  "isActive": true,
  "createdAt": "2026-02-03T10:00:00Z"
}
```

## 🧪 Tesztelés

### Bejelentkezés Tesztelése

1. Nyisd meg: http://localhost:3000
2. Kattints a bejelentkezés gombra
3. Add meg az email és jelszót
4. Kattints "Bejelentkezés"

### Admin Panel Tesztelése

1. Admin fiók bejelentkezéséhez az alkalmazásban
2. Vagy közvetlenül: http://localhost:3000/admin.html
3. Hozz létre új túraútvonalat

## ❓ Hibaelhárítás

### "Firebase is not configured"

**Megoldás**: Szerkeszd a `.env.local` fájlt és add meg a helyes Firebase credentials-t

### "Cannot find module 'firebase/app'"

**Megoldás**: Futtasd le:
```bash
npm install firebase --legacy-peer-deps
```

### Bejelentkezés nem működik

**Ellenőrizd**:
1. Firebase projekt létrehozva-e ✅
2. Authentication engedélyezve-e ✅
3. Email/Password auth aktív-e ✅
4. Fiók létrehozva-e a Firebase Console-ban ✅

## 📚 Dokumentáció

Több információért lásd:
- [docs/DATA_MODEL.md](docs/DATA_MODEL.md) - Adatmodell és Firestore schema
- [docs/TESTING.md](docs/TESTING.md) - Tesztelési útmutató
- [docs/PWA_DEPLOYMENT.md](docs/PWA_DEPLOYMENT.md) - Deployment útmutató

---

**Szükséges segítség?** Nézd meg a Firebase dokumentációt: https://firebase.google.com/docs
