import 'package:package_info_plus/package_info_plus.dart';

String? _cached;

/// Az alkalmazás tényleges verziója (`verzió+buildszám`, pl. `1.0.0+7`) a
/// hibabejelentésekhez. Egyszer olvassa ki, utána a gyorsítótárból adja;
/// ha a platform nem adja meg, `ismeretlen`.
Future<String> appVersionLabel() async {
  final cached = _cached;
  if (cached != null) return cached;
  try {
    final info = await PackageInfo.fromPlatform();
    final build = info.buildNumber.isEmpty ? '' : '+${info.buildNumber}';
    return _cached = '${info.version}$build';
  } catch (_) {
    return 'ismeretlen';
  }
}
