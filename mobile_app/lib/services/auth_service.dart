import 'package:firebase_auth/firebase_auth.dart';

/// Többeszközös fiók: a felhasználó email + név párral vissza tud lépni a
/// haladásába egy másik eszközön.
///
/// A "jelszó" a névből képzett determinisztikus érték – így a felhasználónak
/// nem kell külön jelszót megjegyeznie (a döntés szerint: „ne legyen pin, legyen
/// név"). Fontos: mivel a nevek a nyilvános ranglistán megjelennek, ez
/// helyreállítás-szintű (nem magas biztonságú) védelem – pont-gyűjtő fiókhoz
/// elfogadható. Az emailt meg nem adó felhasználók továbbra is eszközhöz
/// kötöttek maradnak.
class AuthService {
  /// Tesztekben lecserélhető (firebase_auth_mocks / injektált példány).
  static FirebaseAuth auth = FirebaseAuth.instance;

  /// A névből képzett determinisztikus jelszó. A normalizálás megegyezik a
  /// felhasználónév-egyediségnél használttal (kis-nagybetű- és
  /// szóköz-független), hogy másik eszközön is ugyanaz jöjjön ki. A `nvkey:`
  /// előtag garantálja a Firebase által elvárt minimum 6 karaktert.
  static String passwordFromName(String name) {
    final normalized =
        name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return 'nvkey:$normalized';
  }

  /// A jelenlegi (anonim) fiók összekötése email/jelszó hitelesítővel, hogy
  /// másik eszközön email+névvel visszaállítható legyen. A meglévő UID
  /// megmarad, így a haladás nem vész el.
  ///
  /// Dobhat `email-already-in-use` / `credential-already-in-use` hibát, ha az
  /// email már egy másik fiókhoz tartozik – ezt a hívó kezeli.
  static Future<void> linkEmailPassword({
    required String email,
    required String name,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'Nincs bejelentkezett felhasználó a linkeléshez.',
      );
    }
    final credential = EmailAuthProvider.credential(
      email: email.trim(),
      password: passwordFromName(name),
    );
    await user.linkWithCredential(credential);
  }

  /// Bejelentkezés másik eszközön email + névvel. Siker esetén a hívó a korábbi
  /// (haladást tartalmazó) UID-ra vált, és az auth_gate a főképernyőre visz.
  static Future<UserCredential> signInWithEmailName({
    required String email,
    required String name,
  }) {
    return auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: passwordFromName(name),
    );
  }
}
