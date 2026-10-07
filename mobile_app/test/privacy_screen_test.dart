import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/screens/name_screen.dart';
import 'package:mobile_app/screens/privacy_screen.dart';

void main() {
  group('Adatkezelési tájékoztató', () {
    testWidgets('a fő szakaszok megjelennek', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: PrivacyScreen()));

      for (final title in [
        'Az adatkezelő',
        'Milyen adatot kezelünk, és miért?',
        'Helymeghatározás',
        'Igénybe vett szolgáltatások',
        'Meddig őrizzük?',
        'A jogaid',
      ]) {
        await tester.scrollUntilVisible(find.text(title), 200);
        expect(find.text(title), findsOneWidget);
      }
    });

    testWidgets('kimondja, hogy a pozíciót a szerver nem tárolja', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PrivacyScreen()));
      await tester.scrollUntilVisible(
        find.textContaining('A pozíciót a szerver nem tárolja'),
        200,
      );
      expect(
        find.textContaining('A pozíciót a szerver nem tárolja'),
        findsOneWidget,
      );
    });

    testWidgets(
      'build-időben meg nem adott adatkezelőnél nem talál ki adatot',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: PrivacyScreen()));
        expect(
          find.textContaining('hivatalos kiadásában szerepelnek'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a regisztrációs képernyőről megnyitható', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: NameScreen()));
      final link = find.textContaining('adatkezelési tájékoztatót');
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyScreen), findsOneWidget);
    });
  });
}
