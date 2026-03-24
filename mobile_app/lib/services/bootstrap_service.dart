import 'package:cloud_firestore/cloud_firestore.dart';
import 'local_cache.dart';

/// Elso indulas es 12 oran-kenti frissitesnel letolti Firestorebol az
/// osszes tura, allomas es jutalom adatot, es elmenti a helyi cache-be.
/// Halozati hiba eseten csendes visszalepes -- a UI sosem blokkolodik.
class BootstrapService {
  static bool _running = false;

  static Future<void> run({bool force = false}) async {
    if (_running) return;
    if (!force && LocalCache.hasData && !LocalCache.isCacheStale) return;
    _running = true;
    try {
      final db = FirebaseFirestore.instance;
      final results = await Future.wait([
        db.collection('trips').get(),
        db.collection('stations').get(),
        db.collection('achievements').get(),
      ]);

      final trips = (results[0] as QuerySnapshot)
          .docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data() as Map})
          .toList();
      final stations = (results[1] as QuerySnapshot)
          .docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data() as Map})
          .toList();
      final achievements = (results[2] as QuerySnapshot)
          .docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data() as Map})
          .toList();

      await Future.wait([
        LocalCache.saveTrips(trips),
        LocalCache.saveStations(stations),
        LocalCache.saveAchievements(achievements),
      ]);
    } catch (_) {
      // Nincs halozat vagy Firestore hiba -- a cache-elt adat tovabbra is hasznalhato.
    } finally {
      _running = false;
    }
  }
}
