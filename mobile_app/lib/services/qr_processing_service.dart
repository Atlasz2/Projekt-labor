import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'leaderboard_service.dart';

/// Mit azonosított a beolvasott QR-kód: állomást vagy eseményt.
enum QrTargetKind { station, event }

class QrProcessResult {
  const QrProcessResult({
    required this.target,
    required this.kind,
    required this.alreadyDone,
    required this.newAchievements,
    required this.updatedPoints,
    required this.completedStationsCount,
    required this.completedEventsCount,
  });

  /// A beolvasott állomás vagy esemény dokumentuma (`kind` mondja meg, melyik).
  final Map<String, dynamic> target;
  final QrTargetKind kind;
  final bool alreadyDone;
  final List<Map<String, dynamic>> newAchievements;
  final int updatedPoints;
  final int completedStationsCount;
  final int completedEventsCount;
}

/// Permanent failure: the scanned code maps to no existing station or event.
/// Distinct from transient (network/Firestore) errors so the offline queue
/// can drop poison codes instead of retrying them forever.
class QrCodeNotFoundException implements Exception {
  const QrCodeNotFoundException(this.code);

  final String code;

  @override
  String toString() => 'Ismeretlen QR kod: $code';
}

/// A szerveroldali jóváírás (redeemQr Cloud Function) nem elérhető — pl.
/// még nincs deployolva. Ilyenkor a legacy kliensoldali útra váltunk.
/// Tranziens hálózati hiba NEM ez: az továbbdobódik, hogy az offline
/// várólista újrapróbálja.
class QrServerUnavailableException implements Exception {
  const QrServerUnavailableException();
}

/// A szerveroldali jóváírás hívása — tesztekben lecserélhető.
typedef ServerRedeem = Future<Map<String, dynamic>> Function(String code);

class _ProgressOutcome {
  const _ProgressOutcome({
    required this.alreadyDone,
    required this.updatedPoints,
    required this.completedStations,
    required this.completedEvents,
    required this.progressData,
  });

  final bool alreadyDone;
  final int updatedPoints;
  final List<String> completedStations;
  final List<String> completedEvents;
  final Map<String, dynamic> progressData;
}

class QrProcessingService {
  /// Tesztekben lecserélhető (fake_cloud_firestore); élesben az alapértelmezett.
  static FirebaseFirestore firestore = FirebaseFirestore.instance;

  /// Tesztekben lecserélhető; élesben a redeemQr Cloud Functiont hívja.
  static ServerRedeem? serverRedeemOverride;

  /// Ha a függvény nem elérhető (nincs deployolva), az első hiba után erre a
  /// futásra kikapcsoljuk a szerver-utat, és a legacy kliensoldali jóváírás fut.
  static bool serverRedeemEnabled = true;

  static Future<QrProcessResult> processByCode({
    required String uid,
    required String code,
  }) async {
    // Szerver-először: a validáció és jóváírás a redeemQr Cloud Functionben
    // fut (lásd functions/ és docs/SERVER_VALIDATION.md). A legacy út addig
    // marad, amíg a függvény minden környezetben deployolva nincs.
    if (serverRedeemEnabled) {
      try {
        final payload =
            await (serverRedeemOverride ?? _callRedeemFunction)(code);
        if (payload['found'] == false) {
          throw QrCodeNotFoundException(code);
        }
        return _resultFromServerPayload(payload);
      } on QrServerUnavailableException {
        serverRedeemEnabled = false;
      }
    }

    final station = await _findByCode('stations', code);
    if (station != null) {
      return _applyProgress(
        uid: uid,
        kind: QrTargetKind.station,
        targetId: station['id'] as String,
        targetData: station,
      );
    }

    final event = await _findByCode('events', code);
    if (event != null) {
      return _applyProgress(
        uid: uid,
        kind: QrTargetKind.event,
        targetId: event['id'] as String,
        targetData: event,
      );
    }

    throw QrCodeNotFoundException(code);
  }

  static Future<Map<String, dynamic>> _callRedeemFunction(String code) async {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('redeemQr');
    try {
      final response = await callable.call<dynamic>({'code': code});
      return _stringKeyedMap(response.data);
    } on FirebaseFunctionsException catch (e) {
      // 'not-found'/'unimplemented': maga a függvény nem létezik (a szerver
      // ismeretlen kódra nem hibát, hanem found:false-t ad) -> legacy út.
      if (e.code == 'not-found' || e.code == 'unimplemented') {
        throw const QrServerUnavailableException();
      }
      // Minden más (unavailable, deadline-exceeded, internal, ...) tranziens:
      // továbbdobjuk, a hívó/offline várólista kezeli.
      rethrow;
    }
  }

  /// A callable válaszában a beágyazott map-ek `Map<Object?, Object?>`-ként
  /// érkeznek — rekurzívan String-kulcsos map-ekké alakítjuk.
  static Map<String, dynamic> _stringKeyedMap(dynamic value) {
    final map = value as Map;
    return map.map((key, v) {
      dynamic converted = v;
      if (v is Map) {
        converted = _stringKeyedMap(v);
      } else if (v is List) {
        converted = v.map((e) => e is Map ? _stringKeyedMap(e) : e).toList();
      }
      return MapEntry(key.toString(), converted);
    });
  }

  static QrProcessResult _resultFromServerPayload(Map<String, dynamic> payload) {
    final rawAchievements = (payload['newAchievements'] as List?) ?? const [];
    return QrProcessResult(
      target: _stringKeyedMap(payload['target'] ?? const <String, dynamic>{}),
      kind: payload['kind'] == 'event'
          ? QrTargetKind.event
          : QrTargetKind.station,
      alreadyDone: payload['alreadyDone'] == true,
      newAchievements: rawAchievements
          .whereType<Map>()
          .map(_stringKeyedMap)
          .toList(),
      updatedPoints: (payload['updatedPoints'] as num?)?.toInt() ?? 0,
      completedStationsCount:
          (payload['completedStationsCount'] as num?)?.toInt() ?? 0,
      completedEventsCount:
          (payload['completedEventsCount'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<Map<String, dynamic>?> _findByCode(
    String collection,
    String code,
  ) async {
    final snap = await firestore
        .collection(collection)
        .where('qrCode', isEqualTo: code)
        .limit(1)
        .get();

    if (snap.docs.isNotEmpty) {
      final d = snap.docs.first;
      return <String, dynamic>{'id': d.id, ...d.data()};
    }

    // Doc-id fallback. A '/'-t tartalmazó kód nem lehet érvényes dokumentum-út,
    // és a doc() hívás ArgumentError-t dobna rá.
    if (!code.contains('/')) {
      final byId = await firestore.collection(collection).doc(code).get();
      if (byId.exists) {
        return <String, dynamic>{'id': byId.id, ...byId.data()!};
      }
    }

    return null;
  }

  static Future<QrProcessResult> _applyProgress({
    required String uid,
    required QrTargetKind kind,
    required String targetId,
    required Map<String, dynamic> targetData,
  }) async {
    final progressRef = firestore.collection('user_progress').doc(uid);
    final listField = kind == QrTargetKind.station
        ? 'completedStations'
        : 'completedEvents';
    final points = (targetData['points'] as num?)?.toInt() ?? 10;

    // A security rules a user_progress létrehozását csak nullázott számlálókkal
    // engedik, ezért az increment előtt biztosítjuk, hogy a doksi létezzen.
    // (Normál esetben a regisztráció hozza létre; ez a legacy/edge eseteket fedi.)
    final existing = await progressRef.get();
    if (!existing.exists) {
      await progressRef.set({
        'totalPoints': 0,
        'completedStations': <String>[],
        'completedEvents': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // Atomi jóváírás: az olvasás és a feltételes írás egy tranzakcióban fut,
    // így két párhuzamos feldolgozás (pl. élő beolvasás + offline szinkron)
    // nem tudja ugyanazt a kódot kétszer jóváírni.
    final outcome = await firestore.runTransaction<_ProgressOutcome>((
      tx,
    ) async {
      final snap = await tx.get(progressRef);
      final data = snap.data() ?? <String, dynamic>{};

      final completedStations = List<String>.from(
        data['completedStations'] ?? [],
      );
      final completedEvents = List<String>.from(data['completedEvents'] ?? []);
      final currentPoints = (data['totalPoints'] as num?)?.toInt() ?? 0;

      final completedList = kind == QrTargetKind.station
          ? completedStations
          : completedEvents;
      final alreadyDone = completedList.contains(targetId);

      if (!alreadyDone) {
        completedList.add(targetId);
        // update (nem set+merge): a doksi létezését fentebb garantáltuk, és
        // így a transzformok a meglévő értékekre épülnek.
        tx.update(progressRef, {
          listField: FieldValue.arrayUnion([targetId]),
          'totalPoints': FieldValue.increment(points),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      return _ProgressOutcome(
        alreadyDone: alreadyDone,
        updatedPoints: alreadyDone ? currentPoints : currentPoints + points,
        completedStations: completedStations,
        completedEvents: completedEvents,
        progressData: data,
      );
    });

    var completedTripIds = List<String>.from(
      outcome.progressData['completedTripIds'] ?? [],
    );

    List<Map<String, dynamic>> newAchievements = const [];
    if (!outcome.alreadyDone) {
      completedTripIds = await _detectTripCompletion(
        uid: uid,
        kind: kind,
        targetData: targetData,
        completedStations: outcome.completedStations,
        completedTripIds: completedTripIds,
      );

      // Előbb a leaderboard, hogy a top_n feltétel már a friss pontszámmal
      // értékelődjön ki.
      await LeaderboardService.syncEntry(
        uid: uid,
        points: outcome.updatedPoints,
        completedStationsCount: outcome.completedStations.length,
        completedEventsCount: outcome.completedEvents.length,
        displayName: outcome.progressData['name']?.toString(),
      );

      newAchievements = await _checkAchievements(
        uid: uid,
        completedStations: outcome.completedStations,
        completedEvents: outcome.completedEvents,
        completedTripIds: completedTripIds,
        totalPoints: outcome.updatedPoints,
      );
    }

    return QrProcessResult(
      target: targetData,
      kind: kind,
      alreadyDone: outcome.alreadyDone,
      newAchievements: newAchievements,
      updatedPoints: outcome.updatedPoints,
      completedStationsCount: outcome.completedStations.length,
      completedEventsCount: outcome.completedEvents.length,
    );
  }

  /// Túra-teljesítés detektálása állomás-jóváírás után: ha a beolvasott
  /// állomás túrájának minden állomása megvan, a túra bekerül a
  /// completedTripIds-be. A bővített listát adja vissza.
  static Future<List<String>> _detectTripCompletion({
    required String uid,
    required QrTargetKind kind,
    required Map<String, dynamic> targetData,
    required List<String> completedStations,
    required List<String> completedTripIds,
  }) async {
    final result = List<String>.from(completedTripIds);
    if (kind != QrTargetKind.station) return result;

    final tripId = (targetData['tripId'] ?? '').toString().trim();
    if (tripId.isEmpty || result.contains(tripId)) return result;

    try {
      final tripStations = await firestore
          .collection('stations')
          .where('tripId', isEqualTo: tripId)
          .get();
      if (tripStations.docs.isEmpty) return result;

      final allDone = tripStations.docs.every(
        (d) => completedStations.contains(d.id),
      );
      if (!allDone) return result;

      result.add(tripId);
      await firestore.collection('user_progress').doc(uid).update({
        'completedTripIds': FieldValue.arrayUnion([tripId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e, stack) {
      // A túra-detektálás hibája nem blokkolja a beolvasást.
      try {
        await FirebaseCrashlytics.instance.recordError(
          e,
          stack,
          reason: 'trip completion detection failed',
        );
      } catch (_) {
        // Crashlytics nem elérhető (pl. tesztfuttatásban).
      }
      return List<String>.from(completedTripIds);
    }
    return result;
  }

  static Future<List<Map<String, dynamic>>> _checkAchievements({
    required String uid,
    required List<String> completedStations,
    required List<String> completedEvents,
    required List<String> completedTripIds,
    required int totalPoints,
  }) async {
    try {
      final results = await Future.wait([
        firestore.collection('achievements').get(),
        firestore
            .collection('user_progress')
            .doc(uid)
            .collection('unlocked_achievements')
            .get(),
      ]);

      final achSnap = results[0] as QuerySnapshot;
      final unlockedSnap = results[1] as QuerySnapshot;
      final alreadyUnlocked = unlockedSnap.docs.map((d) => d.id).toSet();

      final newlyUnlocked = <Map<String, dynamic>>[];

      final batch = firestore.batch();
      for (final doc in achSnap.docs) {
        final id = doc.id;
        if (alreadyUnlocked.contains(id)) continue;

        final achData = doc.data() as Map<String, dynamic>;
        final type = achData['conditionType']?.toString() ?? '';
        final target = (achData['conditionValue'] as num?)?.toInt() ?? 1;

        bool met = false;
        if (type == 'station_count') {
          met = completedStations.length >= target;
        } else if (type == 'event_count') {
          met = completedEvents.length >= target;
        } else if (type == 'qr_count') {
          met = (completedStations.length + completedEvents.length) >= target;
        } else if (type == 'points_threshold') {
          met = totalPoints >= target;
        } else if (type == 'trip_complete') {
          met = completedTripIds.length >= target;
        } else if (type == 'top_n') {
          // A leaderboard-szinkron előbb futott, így a saját friss
          // pontszámunkkal versenyzünk.
          final top = await firestore
              .collection('public_leaderboard')
              .orderBy('points', descending: true)
              .limit(target)
              .get();
          met = top.docs.any((d) => d.id == uid);
        }

        if (met) {
          batch.set(
            firestore
                .collection('user_progress')
                .doc(uid)
                .collection('unlocked_achievements')
                .doc(id),
            {'unlockedAt': FieldValue.serverTimestamp()},
          );
          // NOTE: we intentionally do NOT increment achievements/{id}.unlockedCount
          // here — that collection is admin-write-only, so including it would make
          // the whole batch fail with permission-denied and the unlock (plus its
          // notification) would never commit.
          newlyUnlocked.add({'id': id, ...achData});
        }
      }

      if (newlyUnlocked.isNotEmpty) {
        final first = newlyUnlocked.first;
        batch.set(
          firestore.collection('user_progress').doc(uid),
          {
            'pendingAchievementBanner': {
              'title': first['name']?.toString() ?? 'Jutalom feloldva!',
              'subtitle': newlyUnlocked.length == 1
                  ? (first['description']?.toString() ?? '')
                  : "${newlyUnlocked.length} új jutalom feloldva!",
            },
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
      return newlyUnlocked;
    } catch (e, stack) {
      // A jutalom-ellenőrzés hibája nem blokkolja a beolvasást, de ne
      // vesszen el nyomtalanul.
      try {
        await FirebaseCrashlytics.instance.recordError(
          e,
          stack,
          reason: 'QR achievement check failed',
        );
      } catch (_) {
        // Crashlytics nem elérhető (pl. tesztfuttatásban).
      }
      return [];
    }
  }
}
