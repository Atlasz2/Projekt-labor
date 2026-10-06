import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/account_service.dart';

void main() {
  tearDown(() => AccountService.renameOverride = null);

  test('a szerver által elmentett nevet adja vissza', () async {
    AccountService.renameOverride = (name) async => name.trim();
    expect(await AccountService.rename('  Kinizsi Pál '), 'Kinizsi Pál');
  });

  test('a foglalt név a felületnek szóló üzenettel jelez', () async {
    AccountService.renameOverride = (_) async =>
        throw const RenameRejectedException('Ez a név már foglalt. Válassz másikat.');
    await expectLater(
      AccountService.rename('Foglalt'),
      throwsA(
        isA<RenameRejectedException>().having((e) => e.message, 'message', contains('foglalt')),
      ),
    );
  });
}
