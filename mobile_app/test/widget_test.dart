import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/screens/name_screen.dart';

void main() {
  group('NameScreen', () {
    testWidgets('megjeleníti az összes alapmezőt', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: NameScreen()));

      expect(find.text('Fedezd fel Nagyvázsonyt!'), findsOneWidget);
      expect(find.text('Név *'), findsOneWidget);
      expect(find.text('E-mail (opcionális)'), findsOneWidget);
      expect(find.text('Folytatás'), findsOneWidget);
    });

    testWidgets('a Folytatás gomb alapból látható és kattintható',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: NameScreen()));

      final button = find.widgetWithText(FilledButton, 'Folytatás');
      expect(button, findsOneWidget);
      // A gomb nem disabled (nem null onPressed)
      final widget = tester.widget<FilledButton>(button);
      expect(widget.onPressed, isNotNull);
    });

    testWidgets('üres névvel megnyomva Snackbar hibát jelenít meg',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: NameScreen()));

      // Kattintás üres névmezővel
      await tester.ensureVisible(find.text('Folytatás'));
      await tester.tap(find.text('Folytatás'));
      await tester.pump(); // trigger Snackbar

      expect(find.text('A név megadása kötelező!'), findsOneWidget);
    });

    testWidgets('a névmezőbe beírva megjelenik a szöveg',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: NameScreen()));

      await tester.enterText(
        find.widgetWithText(TextField, 'Név *'),
        'Teszt Elek',
      );
      expect(find.text('Teszt Elek'), findsOneWidget);
    });

    testWidgets('az email mező opcionálisan kitölthető',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: NameScreen()));

      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail (opcionális)'),
        'teszt@example.com',
      );
      expect(find.text('teszt@example.com'), findsOneWidget);
    });

    testWidgets('érvénytelen email megadásakor hibát jelez',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: NameScreen()));

      await tester.enterText(
        find.widgetWithText(TextField, 'Név *'),
        'Teszt Elek',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail (opcionális)'),
        'ervenytelen-email',
      );
      await tester.ensureVisible(find.text('Folytatás'));
      await tester.tap(find.text('Folytatás'));
      await tester.pump(); // trigger Snackbar

      expect(
        find.text('Érvénytelen email cím. Hagyd üresen, vagy adj meg helyeset.'),
        findsOneWidget,
      );
    });
  });
}
