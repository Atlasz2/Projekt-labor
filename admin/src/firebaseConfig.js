import { initializeApp } from 'firebase/app';
import { initializeAppCheck, ReCaptchaV3Provider } from 'firebase/app-check';
import { connectAuthEmulator, getAuth } from 'firebase/auth';
import { connectFirestoreEmulator, getFirestore } from 'firebase/firestore';
import { connectStorageEmulator, getStorage } from 'firebase/storage';
import { connectFunctionsEmulator, getFunctions } from 'firebase/functions';

// Helyi fejlesztés / vizuális tesztelés a Firebase Emulator Suite ellen
// (VITE_USE_EMULATORS=true): az éles adatok érintése nélkül.
const useEmulators = import.meta.env.VITE_USE_EMULATORS === 'true';

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID
};

const app = initializeApp(firebaseConfig);

// App Check (reCAPTCHA v3): a backend csak a valódi adminból érkező hívásokat
// fogadja el (ha az enforce be van kapcsolva). A reCAPTCHA site key nyilvános,
// ezért beágyazható; env-változóval felülírható. Nem blokkoló: ha az init
// elhasal, az admin akkor is betölt.
const appCheckSiteKey =
  import.meta.env.VITE_FIREBASE_APPCHECK_SITE_KEY ||
  '6LeIv6QtAAAAAK7shTgh466rLa6-ZGIwkJ1AWawr';
if (typeof window !== 'undefined' && appCheckSiteKey && !useEmulators) {
  try {
    initializeAppCheck(app, {
      provider: new ReCaptchaV3Provider(appCheckSiteKey),
      isTokenAutoRefreshEnabled: true,
    });
  } catch (err) {
    // eslint-disable-next-line no-console
    console.warn('App Check init kihagyva:', err);
  }
}

export const auth = getAuth(app);
export const db = getFirestore(app);
export const storage = getStorage(app);
// A Cloud Functions ugyanabban a régióban futnak, mint a callable-ök
// (redeemQr, tripAnalytics, …).
export const functions = getFunctions(app, 'europe-west1');

if (useEmulators) {
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  connectFirestoreEmulator(db, '127.0.0.1', 8080);
  connectStorageEmulator(storage, '127.0.0.1', 9199);
  connectFunctionsEmulator(functions, '127.0.0.1', 5001);
}
