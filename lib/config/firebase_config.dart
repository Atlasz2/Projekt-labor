import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseConfig {
  // Replace these values with your Firebase Web app credentials from
  // Firebase Console -> Project settings -> Web app.
  static final FirebaseOptions webOptions = FirebaseOptions(
    apiKey: "AIzaSyCIsx5WnBFKwpDfmwV2wynrWqi-Vf6QY8I",
    authDomain: "turavonal-app.firebaseapp.com",
    projectId: "turavonal-app",
    storageBucket: "turavonal-app.appspot.com",
    messagingSenderId: "123456789012",
    appId: "1:123456789012:web:abc123def456ghi789jkl",
  );

  /// Attempts to initialize Firebase for web. If the placeholder values
  /// are still present (the developer hasn't filled in the Firebase
  /// credentials), initialization will be skipped and a warning will be
  /// printed. This avoids hard crashes during frontend development when
  /// only the UI is needed.
  static Future<void> initializeApp() async {
    try {
      if (kIsWeb) {
        final placeholder = webOptions.apiKey.startsWith('YOUR_') ||
            webOptions.projectId.startsWith('YOUR_');
        if (placeholder) {
          // Skip initializing Firebase on web if the developer hasn't
          // supplied the real credentials. Map/Firestore calls should be
          // guarded elsewhere so the app can still run for UI work.
          debugPrint(
              'FirebaseConfig: webOptions contain placeholder values; skipping Firebase.initializeApp(). Fill in lib/config/firebase_config.dart to enable Firebase.');
          return;
        }

        await Firebase.initializeApp(options: webOptions);
        debugPrint('FirebaseConfig: Firebase initialized for web.');
      } else {
        // On mobile/desktop the default initialization will read native
        // config files when present (GoogleServices-Info.plist /
        // google-services.json), so just call initializeApp() normally.
        await Firebase.initializeApp();
        debugPrint('FirebaseConfig: Firebase initialized for native platform.');
      }
    } catch (e) {
      debugPrint('FirebaseConfig: failed to initialize Firebase: $e');
      // Do not rethrow — allow the app to continue so front-end work can
      // proceed even without a working Firebase backend.
    }
  }
}