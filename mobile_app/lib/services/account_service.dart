import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'auth_service.dart';
import 'local_cache.dart';

/// GDPR adatjogok kliensoldali kapuja: a szerveroldali exportUserData /
/// deleteMyAccount Cloud Functionöket hívja (lásd functions/lib/gdpr-core.js).
/// A névmódosítás olyan okból hiúsult meg, amelyet a felhasználónak meg kell
/// mutatni (foglalt név, érvénytelen név).
class RenameRejectedException implements Exception {
  const RenameRejectedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Az e-mail utólagos hozzáadása olyan okból hiúsult meg, amelyet a
/// felhasználónak meg kell mutatni (foglalt vagy érvénytelen cím).
class AddEmailRejectedException implements Exception {
  const AddEmailRejectedException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AccountService {
  const AccountService._();

  /// Tesztekben lecserélhető; élesben a renameMe Cloud Functiont hívja.
  static Future<String> Function(String name)? renameOverride;

  /// A megjelenített név módosítása a szerveren (névfoglalás, profil,
  /// ranglisták és az e-mailes visszaállítás jelszava együtt frissül).
  /// Az új, elmentett nevet adja vissza.
  static Future<String> rename(String name) async {
    final override = renameOverride;
    if (override != null) return override(name);
    try {
      final response = await _functions.httpsCallable('renameMe').call<dynamic>(
        {'name': name},
      );
      final data = _stringKeyed(response.data);
      return (data['displayName'] ?? name).toString();
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'already-exists') {
        throw const RenameRejectedException(
          'Ez a név már foglalt. Válassz másikat.',
        );
      }
      if (e.code == 'invalid-argument') {
        throw RenameRejectedException(e.message ?? 'Érvénytelen név.');
      }
      rethrow;
    }
  }

  /// Tesztekben lecserélhető e-mail-hozzáadás.
  static Future<void> Function(String email, String name)? addEmailOverride;

  /// E-mail-cím utólagos hozzáadása a (regisztrációkor e-mail nélkül
  /// létrehozott) fiókhoz: a fiók e-mail/jelszó hitelesítővel kapcsolódik
  /// össze, így másik eszközön vagy újratelepítés után visszaállítható.
  static Future<void> addEmail(String email, String name) async {
    final override = addEmailOverride;
    if (override != null) return override(email, name);
    final trimmed = email.trim();
    try {
      await AuthService.linkEmailPassword(email: trimmed, name: name);
    } on FirebaseAuthException catch (e) {
      final code = e.code.toLowerCase();
      if (code.contains('email-already-in-use') ||
          code.contains('credential-already-in-use')) {
        throw const AddEmailRejectedException(
          'Ehhez az e-mail-címhez már tartozik fiók.',
        );
      }
      if (code.contains('invalid-email')) {
        throw const AddEmailRejectedException('Érvénytelen e-mail-cím.');
      }
      if (code.contains('provider-already-linked')) {
        throw const AddEmailRejectedException(
          'Ehhez a fiókhoz már tartozik e-mail-cím.',
        );
      }
      rethrow;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'email': trimmed,
      }, SetOptions(merge: true));
    }
  }

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// A felhasználó összes adatának lekérése és JSON-fájlba írása a készülék
  /// ideiglenes könyvtárába. A fájl útját adja vissza (a hívó megoszthatja/
  /// megnyithatja). Hitelesítést és deployolt függvényt igényel.
  static Future<File> exportToFile() async {
    final callable = _functions.httpsCallable('exportUserData');
    final response = await callable.call<dynamic>();
    final data = _stringKeyed(response.data);

    const encoder = JsonEncoder.withIndent('  ');
    final json = encoder.convert(data);

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/nagyvazsony-adataim-$stamp.json');
    await file.writeAsString(json, flush: true);
    return file;
  }

  /// Export + a rendszer megosztó lapjának megnyitása (mentés fájlba,
  /// e-mail, felhő stb.), hogy a felhasználó ténylegesen hozzáférjen az
  /// adataihoz.
  static Future<void> exportAndShare() async {
    final file = await exportToFile();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'Nagyvázsony – exportált adataim',
      ),
    );
  }

  /// A fiók és minden kapcsolódó adat törlése a szerveren, majd helyi
  /// kijelentkezés. A hívás után a felhasználó nincs bejelentkezve.
  static Future<void> deleteAccount() async {
    final callable = _functions.httpsCallable('deleteMyAccount');
    await callable.call<dynamic>();
    await LocalCache.clearPendingQr();
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      // A szerver már törölt; a helyi kijelentkezés hibája nem kritikus.
      debugPrint('signOut a fiók törlése után: $e');
    }
  }

  /// A callable válasz map-jeit rekurzívan String-kulcsossá alakítja
  /// (a natív réteg Map&lt;Object?, Object?&gt;-et ad).
  static dynamic _stringKeyed(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _stringKeyed(v)));
    }
    if (value is List) {
      return value.map(_stringKeyed).toList();
    }
    return value;
  }
}
