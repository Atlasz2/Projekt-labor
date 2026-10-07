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

  /// App Check bekapcsolása. ALAPBÓL BE: a mobil callable-ök a tokent
  /// mindig ellenőrzik, és a szerver ENFORCE_APP_CHECK kapcsolójával meg is
  /// követelhetik (lásd functions/index.js és docs/LAUNCH.md) – ezért a
  /// kiadási buildben bekapcsolva kell lennie. Kikapcsolás csak
  /// fejlesztéshez / sideloadolt debug buildhez:
  ///   flutter build apk --dart-define=APP_CHECK=false
  static const bool appCheckEnabled =
      bool.fromEnvironment('APP_CHECK', defaultValue: true);

  /// Az adatkezelő neve és címe az adatkezelési tájékoztatóhoz – kiadásonként
  /// adandó meg (a település üzemeltetője), lásd docs/LAUNCH.md:
  ///   --dart-define=PRIVACY_CONTROLLER="Nagyvázsony Község Önkormányzata, …"
  static const String privacyController =
      String.fromEnvironment('PRIVACY_CONTROLLER');

  /// Az adatvédelmi megkeresések e-mail-címe:
  ///   --dart-define=PRIVACY_EMAIL=adatvedelem@pelda.hu
  static const String privacyEmail = String.fromEnvironment('PRIVACY_EMAIL');
}
