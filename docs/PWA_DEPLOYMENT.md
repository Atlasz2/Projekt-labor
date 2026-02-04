# PWA Publikálási Útmutató

## 1. PWA Követelmények Ellenőrzése

### 1.1 Core PWA Requirements

✅ **HTTPS**
- Production environment HTTPS-en fut
- SSL tanúsítvány érvényes
- Minden resource HTTPS-en keresztül

✅ **Web App Manifest**
- `manifest.json` létezik és valid
- Tartalmazza az összes kötelező mezőt
- Ikonok megfelelő méretekben (192x192, 512x512)

✅ **Service Worker**
- Service Worker regisztrálva
- Offline működés biztosítva
- Cache stratégia implementálva

✅ **Responsive Design**
- Minden képernyőméreten működik
- Mobile-first approach
- Touch-friendly UI elemek

## 2. Build Process

### 2.1 React Build

```bash
# Production build
npm run build

# Build optimalizálás
# package.json scripts:
{
  "scripts": {
    "build": "react-scripts build",
    "build:prod": "cross-env NODE_ENV=production react-scripts build",
    "analyze": "source-map-explorer 'build/static/js/*.js'"
  }
}
```

### 2.2 Build Optimalizálás

**1. Code Splitting**
```javascript
// App.jsx
import React, { lazy, Suspense } from 'react';

const TrailDetailsPage = lazy(() => import('./pages/TrailDetailsPage'));
const AdminPanel = lazy(() => import('./pages/AdminPanel'));

function App() {
  return (
    <Suspense fallback={<div>Loading...</div>}>
      <Routes>
        <Route path="/trails/:id" element={<TrailDetailsPage />} />
        <Route path="/admin" element={<AdminPanel />} />
      </Routes>
    </Suspense>
  );
}
```

**2. Image Optimization**
```json
// package.json
{
  "devDependencies": {
    "imagemin": "^8.0.1",
    "imagemin-webp": "^7.0.0"
  }
}
```

**3. Gzip Compression**
```javascript
// server.js (if using custom server)
const compression = require('compression');
app.use(compression());
```

## 3. Service Worker Konfigurál

### 3.1 Enhanced Service Worker

```javascript
// public/service-worker.js
const CACHE_NAME = 'tour-trail-v1.0.0';
const RUNTIME_CACHE = 'runtime-cache';
const STATIC_CACHE = 'static-cache-v1';

// Cache strategies
const CACHE_FIRST = [
  '/static/',
  '/images/',
  '/icons/'
];

const NETWORK_FIRST = [
  '/api/',
  '/firestore/'
];

// Install - cache static assets
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(STATIC_CACHE).then(cache => {
      return cache.addAll([
        '/',
        '/index.html',
        '/manifest.json',
        '/static/css/main.css',
        '/static/js/main.js',
        '/offline.html'
      ]);
    })
  );
  self.skipWaiting();
});

// Activate - clean old caches
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(cacheNames => {
      return Promise.all(
        cacheNames
          .filter(name => name !== STATIC_CACHE && name !== RUNTIME_CACHE)
          .map(name => caches.delete(name))
      );
    })
  );
  self.clients.claim();
});

// Fetch - intelligent caching
self.addEventListener('fetch', event => {
  const { request } = event;
  const url = new URL(request.url);

  // Cache-first strategy for static assets
  if (CACHE_FIRST.some(pattern => url.pathname.startsWith(pattern))) {
    event.respondWith(cacheFirst(request));
    return;
  }

  // Network-first strategy for API calls
  if (NETWORK_FIRST.some(pattern => url.pathname.startsWith(pattern))) {
    event.respondWith(networkFirst(request));
    return;
  }

  // Stale-while-revalidate for everything else
  event.respondWith(staleWhileRevalidate(request));
});

async function cacheFirst(request) {
  const cached = await caches.match(request);
  return cached || fetch(request);
}

async function networkFirst(request) {
  try {
    const response = await fetch(request);
    const cache = await caches.open(RUNTIME_CACHE);
    cache.put(request, response.clone());
    return response;
  } catch (error) {
    return caches.match(request) || caches.match('/offline.html');
  }
}

async function staleWhileRevalidate(request) {
  const cache = await caches.open(RUNTIME_CACHE);
  const cached = await cache.match(request);
  
  const fetchPromise = fetch(request).then(response => {
    cache.put(request, response.clone());
    return response;
  });

  return cached || fetchPromise;
}

// Background sync for offline actions
self.addEventListener('sync', event => {
  if (event.tag === 'sync-progress') {
    event.waitUntil(syncUserProgress());
  }
});

// Push notifications
self.addEventListener('push', event => {
  const data = event.data.json();
  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: '/icon-192.png',
      badge: '/badge-72.png',
      data: data.url
    })
  );
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil(
    clients.openWindow(event.notification.data)
  );
});
```

### 3.2 Service Worker Registration

```javascript
// src/serviceWorkerRegistration.js
export function register() {
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      const swUrl = `${process.env.PUBLIC_URL}/service-worker.js`;

      navigator.serviceWorker
        .register(swUrl)
        .then(registration => {
          console.log('SW registered:', registration);
          
          // Check for updates periodically
          setInterval(() => {
            registration.update();
          }, 60000); // Every minute

          // Listen for updates
          registration.addEventListener('updatefound', () => {
            const newWorker = registration.installing;
            newWorker.addEventListener('statechange', () => {
              if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
                // New version available
                if (confirm('Új verzió elérhető! Frissítés most?')) {
                  window.location.reload();
                }
              }
            });
          });
        })
        .catch(error => {
          console.error('SW registration failed:', error);
        });
    });
  }
}
```

## 4. Deployment Platformok

### 4.1 Firebase Hosting

**1. Firebase beállítása**
```bash
# Install Firebase CLI
npm install -g firebase-tools

# Login
firebase login

# Initialize hosting
firebase init hosting
```

**2. firebase.json konfiguráció**
```json
{
  "hosting": {
    "public": "build",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**"
    ],
    "rewrites": [
      {
        "source": "**",
        "destination": "/index.html"
      }
    ],
    "headers": [
      {
        "source": "**/*.@(jpg|jpeg|gif|png|svg|webp)",
        "headers": [
          {
            "key": "Cache-Control",
            "value": "max-age=31536000"
          }
        ]
      },
      {
        "source": "service-worker.js",
        "headers": [
          {
            "key": "Cache-Control",
            "value": "no-cache"
          }
        ]
      }
    ]
  }
}
```

**3. Deploy**
```bash
# Build és deploy
npm run build
firebase deploy --only hosting

# Preview deploy
firebase hosting:channel:deploy preview
```

### 4.2 Netlify

**1. netlify.toml konfiguráció**
```toml
[build]
  command = "npm run build"
  publish = "build"

[[redirects]]
  from = "/*"
  to = "/index.html"
  status = 200

[[headers]]
  for = "/*.js"
  [headers.values]
    Cache-Control = "public, max-age=31536000, immutable"

[[headers]]
  for = "/*.css"
  [headers.values]
    Cache-Control = "public, max-age=31536000, immutable"

[[headers]]
  for = "/service-worker.js"
  [headers.values]
    Cache-Control = "no-cache"
```

**2. Deploy**
```bash
# Install Netlify CLI
npm install -g netlify-cli

# Deploy
netlify deploy --prod
```

### 4.3 Vercel

**1. vercel.json**
```json
{
  "buildCommand": "npm run build",
  "outputDirectory": "build",
  "routes": [
    {
      "src": "/service-worker.js",
      "headers": {
        "cache-control": "no-cache"
      },
      "dest": "/service-worker.js"
    },
    {
      "src": "/(.*)",
      "dest": "/"
    }
  ]
}
```

**2. Deploy**
```bash
# Install Vercel CLI
npm install -g vercel

# Deploy
vercel --prod
```

## 5. PWA Tesztelés Production-ben

### 5.1 Lighthouse Audit

```bash
# Install Lighthouse
npm install -g lighthouse

# Run audit
lighthouse https://yourapp.com --view

# Programmatic usage
lighthouse https://yourapp.com \
  --only-categories=pwa,performance,accessibility \
  --output=html \
  --output-path=./lighthouse-report.html
```

**Minimum követelmények**:
- PWA Score: ≥ 90
- Performance: ≥ 85
- Accessibility: ≥ 90
- Best Practices: ≥ 90

### 5.2 PWA Checklist

```bash
# Chrome DevTools
# 1. Open DevTools (F12)
# 2. Application tab
# 3. Check:
#    - Manifest valid ✓
#    - Service Worker active ✓
#    - Offline works ✓
#    - Add to Home Screen works ✓
```

## 6. App Store Distribution (Optional)

### 6.1 Google Play Store (TWA - Trusted Web Activities)

**1. Build Android App Wrapper**
```bash
# Using Bubblewrap
npm install -g @bubblewrap/cli

bubblewrap init --manifest https://yourapp.com/manifest.json
bubblewrap build
```

**2. Sign APK**
```bash
# Generate keystore
keytool -genkey -v -keystore release.keystore \
  -alias my-app -keyalg RSA -keysize 2048 -validity 10000

# Sign APK
jarsigner -verbose -sigalg SHA1withRSA -digestalg SHA1 \
  -keystore release.keystore app-release-unsigned.apk my-app
```

### 6.2 Apple App Store (via PWABuilder)

```bash
# Use PWABuilder.com to generate iOS package
# Or use Capacitor:

npm install @capacitor/core @capacitor/ios
npx cap init
npx cap add ios
npx cap sync
npx cap open ios
```

## 7. Monitoring & Analytics

### 7.1 Google Analytics 4

```javascript
// src/analytics.js
import ReactGA from 'react-ga4';

export const initGA = () => {
  ReactGA.initialize('G-XXXXXXXXXX');
};

export const logPageView = (path) => {
  ReactGA.send({ hitType: 'pageview', page: path });
};

export const logEvent = (category, action, label) => {
  ReactGA.event({
    category,
    action,
    label
  });
};
```

### 7.2 Firebase Analytics

```javascript
// src/firebase.js
import { getAnalytics, logEvent } from 'firebase/analytics';

const analytics = getAnalytics(app);

export const logStationVisit = (stationId) => {
  logEvent(analytics, 'station_visit', {
    station_id: stationId
  });
};

export const logQRScan = (qrCode) => {
  logEvent(analytics, 'qr_scan', {
    qr_code: qrCode
  });
};
```

### 7.3 Error Tracking (Sentry)

```javascript
// src/index.js
import * as Sentry from '@sentry/react';

Sentry.init({
  dsn: 'YOUR_SENTRY_DSN',
  environment: process.env.NODE_ENV,
  integrations: [
    new Sentry.BrowserTracing(),
    new Sentry.Replay()
  ],
  tracesSampleRate: 1.0,
  replaysSessionSampleRate: 0.1,
  replaysOnErrorSampleRate: 1.0
});
```

## 8. CI/CD Pipeline

### 8.1 GitHub Actions

```yaml
# .github/workflows/deploy.yml
name: Deploy PWA

on:
  push:
    branches: [ main ]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v2
      
      - name: Setup Node.js
        uses: actions/setup-node@v2
        with:
          node-version: '18'
          
      - name: Install dependencies
        run: npm ci
        
      - name: Run tests
        run: npm test -- --coverage --watchAll=false
        
      - name: Build
        run: npm run build
        env:
          REACT_APP_FIREBASE_API_KEY: ${{ secrets.FIREBASE_API_KEY }}
          REACT_APP_FIREBASE_PROJECT_ID: ${{ secrets.FIREBASE_PROJECT_ID }}
        
      - name: Run Lighthouse CI
        run: |
          npm install -g @lhci/cli
          lhci autorun
        
      - name: Deploy to Firebase
        uses: FirebaseExtended/action-hosting-deploy@v0
        with:
          repoToken: '${{ secrets.GITHUB_TOKEN }}'
          firebaseServiceAccount: '${{ secrets.FIREBASE_SERVICE_ACCOUNT }}'
          channelId: live
          projectId: your-project-id
```

## 9. Post-Deployment Checklist

### 9.1 Funkcionális Tesztek

- [ ] Login/Logout működik
- [ ] Térképnézet betöltődik
- [ ] QR kód szkenner működik
- [ ] Geolokáció engedélykérés
- [ ] Értesítések működnek
- [ ] Offline mód működik
- [ ] Add to Home Screen működik

### 9.2 Performance Check

- [ ] First Contentful Paint < 2s
- [ ] Time to Interactive < 3.5s
- [ ] Total Bundle Size < 200KB (gzipped)
- [ ] Lighthouse PWA score ≥ 90

### 9.3 Compatibility Check

- [ ] Chrome/Edge (Desktop & Mobile)
- [ ] Firefox (Desktop & Mobile)
- [ ] Safari (Desktop & Mobile)
- [ ] Samsung Internet

## 10. Maintenance

### 10.1 Version Management

```json
// package.json
{
  "version": "1.0.0",
  "scripts": {
    "version:patch": "npm version patch && git push --tags",
    "version:minor": "npm version minor && git push --tags",
    "version:major": "npm version major && git push --tags"
  }
}
```

### 10.2 Update Strategy

```javascript
// src/components/UpdatePrompt.jsx
import { useState, useEffect } from 'react';

export function UpdatePrompt() {
  const [showPrompt, setShowPrompt] = useState(false);

  useEffect(() => {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.ready.then(registration => {
        registration.addEventListener('updatefound', () => {
          const newWorker = registration.installing;
          newWorker.addEventListener('statechange', () => {
            if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
              setShowPrompt(true);
            }
          });
        });
      });
    }
  }, []);

  const handleUpdate = () => {
    window.location.reload();
  };

  if (!showPrompt) return null;

  return (
    <div className="update-prompt">
      <p>Új verzió elérhető!</p>
      <button onClick={handleUpdate}>Frissítés</button>
    </div>
  );
}
```

## Összefoglalás

A PWA sikeres publikálásához:

1. ✅ Build optimalizálás
2. ✅ Service Worker konfigurálás
3. ✅ HTTPS deployment
4. ✅ Lighthouse audit
5. ✅ Analytics beállítása
6. ✅ CI/CD pipeline
7. ✅ Monitoring és hibakövetés
8. ✅ Verziókezelés és frissítési stratégia

**Hasznos linkek**:
- [PWA Checklist](https://web.dev/pwa-checklist/)
- [Workbox (Service Worker Library)](https://developers.google.com/web/tools/workbox)
- [Lighthouse CI](https://github.com/GoogleChrome/lighthouse-ci)
- [Firebase Hosting Docs](https://firebase.google.com/docs/hosting)
