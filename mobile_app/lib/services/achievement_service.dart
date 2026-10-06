import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'qr_processing_service.dart';

/// A jutalom-feltételek kiértékelése (a felületi előrehaladás-kijelzéshez) és
/// a feloldások szerveroldali egyeztetése.
///
/// A QR-beolvasás a beolvasás pillanatában ellenőriz; egy jutalom azonban
/// beolvasás nélkül is teljesülhet (utólag létrehozott jutalom, top-N
/// rangváltozás). Ezt a `reconcileAchievements` Cloud Function egyezteti –
/// a feloldást a szerver írja, a kliens az unlocked_achievements
/// alkollekciót nem írhatja (lásd firestore.rules).
class AchievementService {
  const AchievementService._();

  /// Tesztekben lecserélhető; élesben a reconcileAchievements függvényt hívja.
  static Future<List<Map<String, dynamic>>> Function()? reconcileOverride;

  /// Teljesült-e egy jutalom feltétele a megadott haladással.
  /// A `rank` a ranglistán elfoglalt hely (1-alapú); 0, ha nem ismert.
  static bool isConditionMet({
    required String type,
    required int target,
    required int stations,
    required int events,
    required int points,
    required int trips,
    required int rank,
  }) {
    switch (type) {
      case 'station_count':
        return stations >= target;
      case 'event_count':
        return events >= target;
      case 'qr_count':
        return (stations + events) >= target;
      case 'points_threshold':
        return points >= target;
      case 'trip_complete':
        return trips >= target;
      case 'top_n':
        return rank > 0 && rank <= target;
      default:
        // 'manual' és ismeretlen: nem oldódik fel automatikusan.
        return false;
    }
  }

  /// A teljesült, de még fel nem oldott jutalmak feloldása a szerveren.
  /// Az újonnan feloldott jutalmakat adja vissza. Hiba esetén üres listát ad:
  /// az egyeztetés nem blokkolhatja a képernyő betöltését.
  static Future<List<Map<String, dynamic>>> reconcile() async {
    try {
      final override = reconcileOverride;
      if (override != null) return await override();

      final response =
          await FirebaseFunctions.instanceFor(region: 'europe-west1')
              .httpsCallable('reconcileAchievements')
              .call<dynamic>({'projectId': AppConfig.projectId});
      final data = QrProcessingService.stringKeyedMap(response.data);
      return ((data['newAchievements'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (e) {
      debugPrint('Jutalom-egyeztetés kihagyva: $e');
      return const [];
    }
  }
}
