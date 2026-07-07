import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Push-értesítések kezelése: engedélykérés és feliratkozás az 'events'
/// topicra, amelyre a notifyOnNewEvent Cloud Function küld új esemény
/// létrehozásakor (lásd functions/lib/notification-builder.js).
class NotificationService {
  const NotificationService._();

  /// Az a topic, amelyre a szerver az esemény-értesítéseket küldi.
  static const String eventsTopic = 'events';

  /// Egyszeri inicializálás a bejelentkezés után. Engedélyt kér (iOS/Android 13+),
  /// majd megadott engedély esetén feliratkozik az esemény-topicra. Hibát
  /// elnyel — az értesítés opcionális, nem törheti meg az app indulását.
  static Future<void> init() async {
    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission();
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      if (!granted) {
        debugPrint('Push-értesítés engedély megtagadva — topic kihagyva.');
        return;
      }

      // Web nem támogatja a topic-feliratkozást kliensoldalról.
      if (!kIsWeb) {
        await messaging.subscribeToTopic(eventsTopic);
      }
    } catch (e) {
      debugPrint('NotificationService init hiba: $e');
    }
  }

  /// Leiratkozás (pl. kijelentkezéskor), hogy a kijelentkezett eszköz ne
  /// kapjon több esemény-értesítést.
  static Future<void> dispose() async {
    try {
      if (!kIsWeb) {
        await FirebaseMessaging.instance.unsubscribeFromTopic(eventsTopic);
      }
    } catch (e) {
      debugPrint('NotificationService dispose hiba: $e');
    }
  }
}
