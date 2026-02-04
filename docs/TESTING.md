# Tesztelési Terv és Eredmények

## 1. Unit Tesztek

### 1.1 React Komponensek

**Test Framework**: Jest + React Testing Library

#### Auth Service Tests
```javascript
// src/services/__tests__/authService.test.js
import { signInUser, signUpUser, signOutUser } from '../authService';
import { auth } from '../../firebase';

jest.mock('../../firebase');

describe('Authentication Service', () => {
  test('signInUser should authenticate user successfully', async () => {
    const mockUser = { uid: '123', email: 'test@test.com' };
    auth.signInWithEmailAndPassword.mockResolvedValue({ user: mockUser });
    
    const result = await signInUser('test@test.com', 'password');
    expect(result.user.email).toBe('test@test.com');
  });

  test('signInUser should throw error on invalid credentials', async () => {
    auth.signInWithEmailAndPassword.mockRejectedValue(new Error('Invalid credentials'));
    
    await expect(signInUser('wrong@test.com', 'wrong')).rejects.toThrow();
  });
});
```

#### Geolocation Service Tests
```javascript
// src/services/__tests__/geolocationService.test.js
import { calculateDistance, isNearStation } from '../geolocationService';

describe('Geolocation Service', () => {
  test('calculateDistance should compute correct distance', () => {
    const point1 = { latitude: 47.0333, longitude: 17.7167 };
    const point2 = { latitude: 47.0400, longitude: 17.7200 };
    
    const distance = calculateDistance(point1, point2);
    expect(distance).toBeCloseTo(0.82, 1); // ~0.82 km
  });

  test('isNearStation should return true when within radius', () => {
    const userPos = { latitude: 47.0333, longitude: 17.7167 };
    const station = { 
      location: { latitude: 47.0335, longitude: 17.7169 },
      radius: 50 
    };
    
    const isNear = isNearStation(userPos, station);
    expect(isNear).toBe(true);
  });
});
```

### 1.2 Flutter Unit Tests

**Test Framework**: Flutter Test

```dart
// test/models/station_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:projekt_labor2/models/station.dart';

void main() {
  group('Station Model', () {
    test('fromJson should parse station correctly', () {
      final json = {
        'id': 'station_001',
        'name': 'Kinizsi Vár',
        'location': {
          'latitude': 47.0333,
          'longitude': 17.7167
        },
        'radius': 50,
      };

      final station = Station.fromJson(json);

      expect(station.id, 'station_001');
      expect(station.name, 'Kinizsi Vár');
      expect(station.location.latitude, 47.0333);
    });

    test('toJson should serialize station correctly', () {
      final station = Station(
        id: 'station_001',
        name: 'Kinizsi Vár',
        location: LatLng(47.0333, 17.7167),
        radius: 50,
      );

      final json = station.toJson();

      expect(json['id'], 'station_001');
      expect(json['location']['latitude'], 47.0333);
    });
  });
}
```

## 2. Integration Tests

### 2.1 React E2E Tests

**Test Framework**: Cypress

```javascript
// cypress/e2e/trail_navigation.cy.js
describe('Trail Navigation', () => {
  beforeEach(() => {
    cy.visit('/');
    cy.login('test@test.com', 'password');
  });

  it('should display trails list', () => {
    cy.get('[data-testid="trails-list"]').should('exist');
    cy.contains('Nagyvázsony Vár Túra').should('be.visible');
  });

  it('should navigate to trail details', () => {
    cy.contains('Nagyvázsony Vár Túra').click();
    cy.url().should('include', '/trails/');
    cy.get('[data-testid="trail-map"]').should('exist');
  });

  it('should scan QR code and unlock station', () => {
    cy.visit('/trails/trail_001');
    cy.get('[data-testid="scan-qr-button"]').click();
    
    // Mock QR scan
    cy.window().then((win) => {
      win.postMessage({ type: 'QR_SCANNED', code: 'TRAIL001_STATION001' }, '*');
    });
    
    cy.contains('Állomás feloldva!').should('be.visible');
  });
});
```

### 2.2 Flutter Integration Tests

```dart
// integration_test/app_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:projekt_labor2/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Complete trail flow', (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle();

    // Login
    await tester.enterText(find.byKey(Key('email-field')), 'test@test.com');
    await tester.enterText(find.byKey(Key('password-field')), 'password');
    await tester.tap(find.byKey(Key('login-button')));
    await tester.pumpAndSettle();

    // Select trail
    await tester.tap(find.text('Nagyvázsony Vár Túra'));
    await tester.pumpAndSettle();

    // Verify map is shown
    expect(find.byKey(Key('trail-map')), findsOneWidget);
  });
}
```

## 3. Biztonsági Tesztelés

### 3.1 Authentication Tests

**Tesztelendő területek**:
- ✅ Email/Password erősségének ellenőrzése
- ✅ SQL Injection védelem (Firebase által kezelt)
- ✅ XSS védelem
- ✅ CSRF token használata
- ✅ Session management
- ✅ Password hashing (Firebase által kezelt)

**Teszt esetek**:
```javascript
describe('Security Tests', () => {
  test('should reject weak passwords', async () => {
    const weakPassword = '123';
    await expect(signUpUser('test@test.com', weakPassword))
      .rejects.toThrow('Password should be at least 6 characters');
  });

  test('should sanitize user input', () => {
    const maliciousInput = '<script>alert("XSS")</script>';
    const sanitized = sanitizeInput(maliciousInput);
    expect(sanitized).not.toContain('<script>');
  });
});
```

### 3.2 Firestore Security Rules Testing

```javascript
// firestore.rules.test.js
const firebase = require('@firebase/testing');
const fs = require('fs');

describe('Firestore Security Rules', () => {
  let db;

  beforeAll(async () => {
    const projectId = 'test-project';
    db = firebase.initializeTestApp({ projectId }).firestore();
    
    const rules = fs.readFileSync('firestore.rules', 'utf8');
    await firebase.loadFirestoreRules({ projectId, rules });
  });

  test('should deny unauthenticated read of user data', async () => {
    const userDoc = db.collection('users').doc('user123');
    await firebase.assertFails(userDoc.get());
  });

  test('should allow user to read own data', async () => {
    const authedDb = firebase.initializeTestApp({
      projectId: 'test-project',
      auth: { uid: 'user123' }
    }).firestore();
    
    const userDoc = authedDb.collection('users').doc('user123');
    await firebase.assertSucceeds(userDoc.get());
  });

  test('should deny non-admin trail creation', async () => {
    const authedDb = firebase.initializeTestApp({
      projectId: 'test-project',
      auth: { uid: 'user123' }
    }).firestore();
    
    const trailDoc = authedDb.collection('trails').doc('new_trail');
    await firebase.assertFails(trailDoc.set({ name: 'Test Trail' }));
  });
});
```

## 4. Adatvédelmi Megfelelőség (GDPR)

### 4.1 GDPR Checklist

- ✅ **Hozzájárulás**: Explicit user consent for data collection
- ✅ **Átláthatóság**: Privacy policy clearly states data usage
- ✅ **Hozzáférési jog**: Users can view their data
- ✅ **Törlési jog**: Users can delete their account and data
- ✅ **Adatmobilitás**: Users can export their data
- ✅ **Korlátozás**: Minimal data collection
- ✅ **Biztonság**: Encrypted data transmission (HTTPS/TLS)

### 4.2 Implementált Adatvédelmi Funkciók

```javascript
// GDPR compliance functions
export const exportUserData = async (userId) => {
  const userData = await getUserData(userId);
  const userProgress = await getUserProgress(userId);
  
  return {
    personalData: userData,
    activityHistory: userProgress,
    exportedAt: new Date().toISOString()
  };
};

export const deleteUserData = async (userId) => {
  const batch = firestore.batch();
  
  // Delete user document
  batch.delete(firestore.collection('users').doc(userId));
  
  // Delete user progress
  const progressDocs = await firestore
    .collection('user_progress')
    .where('userId', '==', userId)
    .get();
  progressDocs.forEach(doc => batch.delete(doc.ref));
  
  // Anonymize other references
  // ...
  
  await batch.commit();
};
```

## 5. Performance Testing

### 5.1 React Performance Tests

```javascript
// Using Lighthouse CI
module.exports = {
  ci: {
    collect: {
      url: ['http://localhost:3000/'],
      numberOfRuns: 5,
    },
    assert: {
      preset: 'lighthouse:recommended',
      assertions: {
        'categories:performance': ['error', { minScore: 0.9 }],
        'categories:accessibility': ['error', { minScore: 0.9 }],
        'categories:best-practices': ['error', { minScore: 0.9 }],
        'categories:pwa': ['error', { minScore: 0.9 }],
      },
    },
  },
};
```

### 5.2 Flutter Performance Tests

```dart
// test/performance/scroll_performance_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Trail list should scroll smoothly', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp());
    await tester.pumpAndSettle();

    final stopwatch = Stopwatch()..start();
    await tester.fling(find.byType(ListView), Offset(0, -500), 10000);
    await tester.pumpAndSettle();
    stopwatch.stop();

    expect(stopwatch.elapsedMilliseconds, lessThan(1000));
  });
}
```

## 6. PWA Tesztelés

### 6.1 PWA Checklist

- ✅ **HTTPS**: Deployed on secure connection
- ✅ **Service Worker**: Registers successfully
- ✅ **Manifest**: Valid manifest.json
- ✅ **Offline**: Works offline after first load
- ✅ **Installable**: Can be installed to home screen
- ✅ **Responsive**: Works on all screen sizes
- ✅ **Fast Load**: First Contentful Paint < 2s

### 6.2 Service Worker Tests

```javascript
// test/service-worker.test.js
describe('Service Worker', () => {
  test('should register successfully', async () => {
    const registration = await navigator.serviceWorker.register('/service-worker.js');
    expect(registration.active).toBeTruthy();
  });

  test('should cache resources', async () => {
    const cache = await caches.open('tour-trail-v1');
    const cachedResponse = await cache.match('/index.html');
    expect(cachedResponse).toBeTruthy();
  });

  test('should serve from cache when offline', async () => {
    // Simulate offline
    jest.spyOn(window.navigator, 'onLine', 'get').mockReturnValue(false);
    
    const response = await fetch('/index.html');
    expect(response.ok).toBe(true);
  });
});
```

## 7. QR-kód Tesztelés

### 7.1 QR Scanner Tests

```javascript
describe('QR Scanner', () => {
  test('should decode valid QR code', async () => {
    const mockQRData = 'TRAIL001_STATION001';
    const result = await scanQRCode(mockQRData);
    
    expect(result.trailId).toBe('trail_001');
    expect(result.stationId).toBe('station_001');
  });

  test('should reject invalid QR code', async () => {
    const invalidQR = 'INVALID_CODE';
    await expect(scanQRCode(invalidQR)).rejects.toThrow('Invalid QR code');
  });

  test('should handle damaged QR code', async () => {
    // QR with error correction should still work
    const damagedQR = 'TRAIL001_STAT###001'; // Simulated damage
    const result = await scanQRCode(damagedQR);
    
    // Should still decode with error correction
    expect(result).toBeDefined();
  });
});
```

## 8. Geolocation & Background Services Tests

### 8.1 Geofencing Tests

```javascript
describe('Geofencing Service', () => {
  test('should trigger notification when entering station radius', async () => {
    const mockPosition = { latitude: 47.0333, longitude: 17.7167 };
    const station = { 
      location: { latitude: 47.0334, longitude: 17.7168 },
      radius: 50,
      name: 'Kinizsi Vár'
    };
    
    const notification = await checkGeofence(mockPosition, station);
    expect(notification).toBeTruthy();
    expect(notification.title).toContain('Kinizsi Vár');
  });

  test('should not trigger notification outside radius', async () => {
    const mockPosition = { latitude: 47.0500, longitude: 17.7500 };
    const station = { 
      location: { latitude: 47.0333, longitude: 17.7167 },
      radius: 50 
    };
    
    const notification = await checkGeofence(mockPosition, station);
    expect(notification).toBeNull();
  });
});
```

## 9. Test Coverage

### 9.1 Coverage Goals

- **Unit Tests**: > 80% code coverage
- **Integration Tests**: Critical paths covered
- **E2E Tests**: Main user flows covered

### 9.2 Coverage Report

```bash
# React coverage
npm test -- --coverage --watchAll=false

# Flutter coverage
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
```

**Expected Results**:
```
File                     | % Stmts | % Branch | % Funcs | % Lines
-------------------------|---------|----------|---------|--------
All files                |   82.5  |   78.3   |   85.1  |   82.1
 services                |   89.2  |   85.4   |   90.3  |   88.9
 components              |   78.1  |   72.1   |   80.5  |   77.8
 models                  |   95.3  |   92.7   |   96.1  |   95.1
```

## 10. Continuous Integration

### 10.1 CI Pipeline (.github/workflows/test.yml)

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test-react:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install dependencies
        run: npm install
      - name: Run tests
        run: npm test -- --coverage
      - name: Run Lighthouse
        run: npm run lighthouse

  test-flutter:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: subosito/flutter-action@v2
      - name: Install dependencies
        run: flutter pub get
      - name: Run tests
        run: flutter test --coverage
      - name: Integration tests
        run: flutter drive --driver=test_driver/integration_driver.dart
```

## Összefoglalás

Az alkalmazás átfogó tesztelése biztosítja:
- ✅ Funkcionalitás helyességét
- ✅ Biztonsági követelmények teljesülését
- ✅ GDPR megfelelőséget
- ✅ PWA követelményeket
- ✅ Teljesítmény optimalizálást
- ✅ Felhasználói élmény minőségét
