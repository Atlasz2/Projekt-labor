# Firebase Adatstruktúra és Adatmodell

## Adatbázis Architektúra

### 1. Firestore Collections

```
firestore
├── trails/              # Túraútvonalak
├── stations/            # Állomások
├── users/               # Felhasználók
├── user_progress/       # Előrehaladás
├── qr_codes/            # QR-kód információk
└── admin_users/         # Adminisztrátorok
```

## Részletes Adatmodellek

### 1.1 Trails (Túraútvonalak)

**Collection**: `trails`
**Document ID**: Auto-generated vagy egyedi azonosító

```json
{
  "id": "trail_001",
  "name": "Nagyvázsony Vár Túra",
  "description": "Történelmi séta Nagyvázsony várának környékén",
  "difficulty": "közepes",
  "duration": 120,
  "distance": 5.2,
  "stationIds": ["station_001", "station_002", "station_003"],
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
  "polyline": [
    {"lat": 47.0333, "lng": 17.7167},
    {"lat": 47.0350, "lng": 17.7180},
    {"lat": 47.0400, "lng": 17.7200}
  ],
  "imageUrl": "https://storage.firebase.com/trails/nagyvazsony.jpg",
  "isActive": true,
  "createdAt": "2026-01-15T10:00:00Z",
  "updatedAt": "2026-02-01T14:30:00Z"
}
```

**Mezők**:
- `id`: Egyedi azonosító
- `name`: Útvonal neve
- `description`: Leírás
- `difficulty`: Nehézség (könnyű, közepes, nehéz)
- `duration`: Várható idő percben
- `distance`: Távolság km-ben
- `stationIds`: Állomások ID-i sorrendben
- `startPoint`, `endPoint`: Kezdő/végpont koordináták
- `polyline`: Útvonal pontjai
- `imageUrl`: Borítókép
- `isActive`: Aktív-e az útvonal
- `createdAt`, `updatedAt`: Időbélyegek

### 1.2 Stations (Állomások)

**Collection**: `stations`
**Document ID**: Auto-generated vagy egyedi azonosító

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
  "qrCodeId": "qr_001",
  "pointsValue": 10,
  "content": {
    "text": "A várat a 15. században építették...",
    "images": [
      "https://storage.firebase.com/stations/var_001.jpg",
      "https://storage.firebase.com/stations/var_002.jpg"
    ],
    "audioUrl": "https://storage.firebase.com/audio/var_guide.mp3",
    "videoUrl": null,
    "quiz": {
      "question": "Mikor épült a vár?",
      "options": ["13. század", "14. század", "15. század", "16. század"],
      "correctAnswer": 2,
      "points": 5
    }
  },
  "isActive": true,
  "createdAt": "2026-01-15T10:00:00Z"
}
```

**Mezők**:
- `id`: Egyedi azonosító
- `trailId`: Melyik útvonalhoz tartozik
- `name`: Állomás neve
- `description`: Rövid leírás
- `location`: GPS koordináták
- `radius`: Közelség detektáláshoz (méterben)
- `order`: Sorrend az útvonalon
- `qrCodeId`: Kapcsolódó QR-kód
- `pointsValue`: Pont értéke
- `content`: Részletes tartalom (szöveg, kép, hang, videó, kvíz)
- `isActive`: Aktív-e
- `createdAt`: Létrehozás időpontja

### 1.3 Users (Felhasználók)

**Collection**: `users`
**Document ID**: Firebase Auth UID

```json
{
  "uid": "user_firebase_uid_123",
  "email": "user@example.com",
  "displayName": "Kovács János",
  "photoURL": "https://storage.firebase.com/avatars/user123.jpg",
  "totalPoints": 150,
  "level": 3,
  "badges": ["early_adopter", "trail_master"],
  "preferences": {
    "notifications": true,
    "geofencing": true,
    "theme": "light"
  },
  "createdAt": "2026-01-20T09:00:00Z",
  "lastLoginAt": "2026-02-03T08:30:00Z"
}
```

**Mezők**:
- `uid`: Firebase Auth User ID
- `email`: E-mail cím
- `displayName`: Megjelenítendő név
- `photoURL`: Profilkép
- `totalPoints`: Összesített pontszám
- `level`: Felhasználói szint
- `badges`: Elért jelvények
- `preferences`: Beállítások
- `createdAt`, `lastLoginAt`: Időbélyegek

### 1.4 User Progress (Felhasználói Előrehaladás)

**Collection**: `user_progress`
**Document ID**: `{userId}_{trailId}` vagy auto-generated

```json
{
  "id": "progress_user123_trail001",
  "userId": "user_firebase_uid_123",
  "trailId": "trail_001",
  "status": "in_progress",
  "startedAt": "2026-02-03T10:00:00Z",
  "completedAt": null,
  "visitedStations": [
    {
      "stationId": "station_001",
      "visitedAt": "2026-02-03T10:15:00Z",
      "pointsEarned": 10,
      "qrScanned": true,
      "quizCompleted": true,
      "quizScore": 5
    },
    {
      "stationId": "station_002",
      "visitedAt": "2026-02-03T11:00:00Z",
      "pointsEarned": 10,
      "qrScanned": true,
      "quizCompleted": false,
      "quizScore": 0
    }
  ],
  "totalPointsEarned": 25,
  "completionPercentage": 66,
  "lastActiveAt": "2026-02-03T11:00:00Z"
}
```

**Mezők**:
- `id`: Egyedi azonosító
- `userId`, `trailId`: Felhasználó és útvonal
- `status`: Állapot (not_started, in_progress, completed)
- `startedAt`, `completedAt`: Kezdés/befejezés időpontja
- `visitedStations`: Meglátogatott állomások részletei
- `totalPointsEarned`: Összesített pontszám
- `completionPercentage`: Teljesítés százalék
- `lastActiveAt`: Utolsó aktivitás

### 1.5 QR Codes

**Collection**: `qr_codes`
**Document ID**: QR kód egyedi azonosítója

```json
{
  "id": "qr_001",
  "code": "TRAIL001_STATION001",
  "stationId": "station_001",
  "type": "station_unlock",
  "isActive": true,
  "scanCount": 127,
  "createdAt": "2026-01-15T10:00:00Z",
  "expiresAt": null
}
```

**Mezők**:
- `id`: Egyedi azonosító
- `code`: QR kód tartalma (amit beolvas)
- `stationId`: Kapcsolódó állomás
- `type`: Típus (station_unlock, bonus_content, stb.)
- `isActive`: Aktív-e
- `scanCount`: Beolvasások száma (statisztika)
- `createdAt`: Létrehozás
- `expiresAt`: Lejárati dátum (opcionális)

### 1.6 Admin Users (Adminisztrátorok)

**Collection**: `admin_users`
**Document ID**: Firebase Auth UID

```json
{
  "uid": "admin_uid_456",
  "email": "admin@nagyvazsony.hu",
  "role": "admin",
  "permissions": [
    "manage_trails",
    "manage_stations",
    "manage_users",
    "view_analytics"
  ],
  "createdAt": "2026-01-10T08:00:00Z",
  "lastLoginAt": "2026-02-03T09:00:00Z"
}
```

**Mezők**:
- `uid`: Firebase Auth User ID
- `email`: Admin e-mail
- `role`: Szerep (admin, moderator)
- `permissions`: Jogosultságok listája
- `createdAt`, `lastLoginAt`: Időbélyegek

## Firestore Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Trails - Mindenki olvashatja, admin írhatja
    match /trails/{trailId} {
      allow read: if true;
      allow write: if isAdmin();
    }
    
    // Stations - Mindenki olvashatja, admin írhatja
    match /stations/{stationId} {
      allow read: if true;
      allow write: if isAdmin();
    }
    
    // Users - Csak saját profil olvasható/írható
    match /users/{userId} {
      allow read: if request.auth != null && request.auth.uid == userId;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    
    // User Progress - Csak saját előrehaladás
    match /user_progress/{progressId} {
      allow read: if request.auth != null && 
                    resource.data.userId == request.auth.uid;
      allow create, update: if request.auth != null && 
                              request.resource.data.userId == request.auth.uid;
      allow delete: if false; // Előrehaladás nem törölhető
    }
    
    // QR Codes - Mindenki olvashatja, admin írhatja
    match /qr_codes/{qrId} {
      allow read: if request.auth != null;
      allow write: if isAdmin();
    }
    
    // Admin Users - Csak admin olvashatja
    match /admin_users/{adminId} {
      allow read: if isAdmin();
      allow write: if isSuperAdmin();
    }
    
    // Helper functions
    function isAdmin() {
      return request.auth != null && 
             exists(/databases/$(database)/documents/admin_users/$(request.auth.uid));
    }
    
    function isSuperAdmin() {
      return request.auth != null && 
             get(/databases/$(database)/documents/admin_users/$(request.auth.uid)).data.role == 'super_admin';
    }
  }
}
```

## Indexek

### Compound Indexes (firebase.json)

```json
{
  "firestore": {
    "indexes": [
      {
        "collectionGroup": "user_progress",
        "queryScope": "COLLECTION",
        "fields": [
          {"fieldPath": "userId", "order": "ASCENDING"},
          {"fieldPath": "status", "order": "ASCENDING"},
          {"fieldPath": "lastActiveAt", "order": "DESCENDING"}
        ]
      },
      {
        "collectionGroup": "stations",
        "queryScope": "COLLECTION",
        "fields": [
          {"fieldPath": "trailId", "order": "ASCENDING"},
          {"fieldPath": "order", "order": "ASCENDING"}
        ]
      }
    ]
  }
}
```

## Best Practices

1. **Denormalizáció**: Gyakran használt adatok duplikálása (pl. `stationIds` a trail-ben)
2. **Shallow Queries**: Ne tároljunk túl mély nested objektumokat
3. **Batch Operations**: Több írás egyszerre (pl. station + QR kód létrehozása)
4. **Security First**: Minden művelet előtt jogosultság ellenőrzés
5. **Indexelés**: Összetett lekérdezésekhez index szükséges

## Scaling Considerations

- **Sharding**: Túl nagy collection-ök felosztása
- **Caching**: Firestore cache + React/Flutter cache réteg
- **Pagination**: Nagy listák lapozva
- **Real-time vs Snapshot**: Csak szükséges helyen real-time listener
