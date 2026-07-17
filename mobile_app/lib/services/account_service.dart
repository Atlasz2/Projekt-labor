import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// GDPR adatjogok kliensoldali kapuja: a szerveroldali exportUserData /
/// deleteMyAccount Cloud Functionöket hívja (lásd functions/lib/gdpr-core.js).
class AccountService {
  const AccountService._();

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
