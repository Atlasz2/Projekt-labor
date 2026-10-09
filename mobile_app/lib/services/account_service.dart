import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'auth_service.dart';
import 'data_export_pdf.dart';
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

/// Az adatexport eredménye: a fájl neve és – ha a Letöltések mappába került –
/// a megnyitásához szükséges azonosító.
class ExportResult {
  const ExportResult({required this.fileName, this.uri});

  final String fileName;
  final String? uri;

  bool get savedToDownloads => uri != null;
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

  static const _downloads = MethodChannel('nagyvazsony/downloads');
  static const _pdfMime = 'application/pdf';

  /// Tesztekben lecserélhető adatlekérés (élesben az exportUserData függvény).
  static Future<Map<String, dynamic>> Function()? exportDataOverride;

  /// A felhasználó összes tárolt adatának lekérése a szerverről és olvasható
  /// PDF-dokumentummá alakítása (nem nyers JSON: technikai azonosítók nélkül,
  /// az állomások és jutalmak nevével).
  static Future<Uint8List> buildExportPdf() async {
    final dataFuture =
        (exportDataOverride ?? _fetchExportData)(); // a lassú rész – indul
    final names = _exportNames(); // közben a nevek a helyi tárból
    final fonts = Future.wait([
      rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
      rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
    ]);
    final data = await dataFuture;
    final (stations, events, achievements) = await names;
    final [regular, bold] = await fonts;
    return DataExportPdf.build(
      data,
      regular: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
      stationNames: stations,
      eventNames: events,
      achievementNames: achievements,
    );
  }

  static Future<Map<String, dynamic>> _fetchExportData() async {
    final response = await _functions
        .httpsCallable('exportUserData')
        .call<dynamic>();
    return Map<String, dynamic>.from(_stringKeyed(response.data) as Map);
  }

  static Future<(Map<String, String>, Map<String, String>, Map<String, String>)>
  _exportNames() async {
    Map<String, String> byId(Iterable<Map<String, dynamic>> docs) => {
      for (final d in docs)
        if (d['id'] != null)
          d['id'].toString(): (d['name'] ?? d['title'] ?? '').toString(),
    }..removeWhere((_, v) => v.isEmpty);

    var events = <String, String>{};
    try {
      final snap = await FirebaseFirestore.instance
          .collection('events')
          .get(const GetOptions(source: Source.cache));
      events = byId(snap.docs.map((d) => {'id': d.id, ...d.data()}));
    } catch (_) {
      // A rendezvénynevek nélkül is elkészül a dokumentum.
    }
    return (
      byId(LocalCache.getStations()),
      events,
      byId(LocalCache.getAchievements()),
    );
  }

  /// Az adatexport letöltése: a PDF a telefon Letöltések mappájába kerül
  /// (Android 10+). Ahol ez nem lehetséges (régebbi Android, iOS), a
  /// rendszer mentés/megosztás lapja nyílik meg. A letöltött fájl
  /// megnyitásához használható azonosítót adja vissza (vagy null-t).
  static Future<ExportResult> exportToDownloads() async {
    final bytes = await buildExportPdf();
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final fileName =
        'nagyvazsony-adataim-${now.year}-${two(now.month)}-${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}.pdf';

    if (Platform.isAndroid) {
      try {
        final uri = await _downloads.invokeMethod<String>('save', {
          'name': fileName,
          'mime': _pdfMime,
          'bytes': bytes,
        });
        if (uri != null) return ExportResult(fileName: fileName, uri: uri);
      } on PlatformException catch (e) {
        debugPrint('Mentés a Letöltésekbe sikertelen: $e');
      }
    }

    // Tartalék: ideiglenes fájl + a rendszer lapja (ott „Mentés fájlba”).
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: _pdfMime)],
        subject: 'Nagyvázsony – adataim',
      ),
    );
    return ExportResult(fileName: fileName);
  }

  /// A letöltött PDF megnyitása a telefon PDF-olvasójával.
  static Future<bool> openDownloaded(String uri) async {
    try {
      return await _downloads.invokeMethod<bool>('open', {
            'uri': uri,
            'mime': _pdfMime,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
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
