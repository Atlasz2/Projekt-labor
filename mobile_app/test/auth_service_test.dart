import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/auth_service.dart';

void main() {
  group('AuthService.passwordFromName', () {
    test('determinisztikus: ugyanaz a név ugyanazt a jelszót adja', () {
      expect(
        AuthService.passwordFromName('Kiss János'),
        AuthService.passwordFromName('Kiss János'),
      );
    });

    test('normalizál: kis-nagybetű és többszörös szóköz nem számít', () {
      final a = AuthService.passwordFromName('Kiss János');
      final b = AuthService.passwordFromName('  kiss   jános ');
      expect(a, b);
    });

    test('legalább 6 karakter (Firebase követelmény), rövid névre is', () {
      expect(AuthService.passwordFromName('Ő').length, greaterThanOrEqualTo(6));
      expect(AuthService.passwordFromName('Jó').length, greaterThanOrEqualTo(6));
    });

    test('különböző nevek különböző jelszót adnak', () {
      expect(
        AuthService.passwordFromName('Kiss János'),
        isNot(AuthService.passwordFromName('Nagy Béla')),
      );
    });
  });
}
