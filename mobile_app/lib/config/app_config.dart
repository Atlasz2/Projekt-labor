/// A kiadás (build) konfigurációja.
///
/// A rendszer több települést (projektet) is ki tud szolgálni, de EGY kiadás
/// alapból EGY településhez tartozik – így a Nagyvázsony-appnak saját neve,
/// arculata és tartalma van, a felhasználót nem terheli településválasztóval.
///
/// A döntés így nem architektúra-, hanem kiadás-kérdés: ha később régiós app
/// kell (több település egy alkalmazásban), elég a [multiProject] kapcsolót
/// bekapcsolni – a tartalom-szűrés ugyanaz marad.
///
/// Build-időben felülírható:
///   flutter build apk --dart-define=PROJECT_ID=mencshely
///   flutter build apk --dart-define=MULTI_PROJECT=true
class AppConfig {
  const AppConfig._();

  /// Az alapértelmezett település azonosítója. Ugyanaz az érték, mint az admin
  /// oldalon (`DEFAULT_PROJECT_ID`), és a `projectId` nélküli – még nem
  /// migrált – dokumentumok is ide tartoznak.
  static const String defaultProjectId = 'nagyvazsony';

  /// Ennek a kiadásnak a települése.
  static const String projectId =
      String.fromEnvironment('PROJECT_ID', defaultValue: defaultProjectId);

  /// Ha igaz, az app több települést kínál (jövőbeli régiós kiadás).
  /// Egy-települési kiadásnál hamis: nincs választó, nincs zavaró extra lépés.
  static const bool multiProject =
      bool.fromEnvironment('MULTI_PROJECT', defaultValue: false);

  /// App Check bekapcsolása. ALAPBÓL KI: amíg a szerveroldali kikényszerítés
  /// (enforcement) nincs bekapcsolva, az App Checknek nincs haszna, viszont
  /// sideloadolt (App Distribution) buildnél a Play Integrity elhasalhat és
  /// lassíthatja a Firebase-hívásokat. Bekapcsolás:
  ///   flutter build apk --dart-define=APP_CHECK=true
  static const bool appCheckEnabled =
      bool.fromEnvironment('APP_CHECK', defaultValue: false);
}
