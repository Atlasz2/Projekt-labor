// lib/config/firebase_config.dart
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

class FirebaseConfig {
  static Future<void> initializeApp() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      // Ha szeretnél debug üzenetet:
      print('✅ Firebase initialized successfully.');
    } catch (e) {
      print('❌ Firebase initialization failed: $e');
    }
  }
}
