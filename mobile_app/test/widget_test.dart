import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/screens/name_screen.dart';

void main() {
  group('NameScreen', () {
    testWidgets('megjeleníti az összes alapmezőt', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: NameScreen()));

      expect(find.text('Nagyvázsony'), findsOneWidget);
      expect(find.text('Teljes név *'), findsOneWidget);
      expect(find.text('Email (opcionális)'), findsOneWidget);
      expect(find.text('Folytatás'), findsOneWidget);
    });

    testWidgets('a Folytatás gomb alapból látható és kattintható',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: NameScreen()));

      final button = find.widgetWithText(ElevatedButton, 'Folytatás');
      expect(button, findsOneWidget);
      // A gomb nem disabled (nem null onPressed)
      final widget = tester.widget<ElevatedButton>(button);
      expect(widget.onPressed, isNotNull);
    });

    testWidgets('üres névvel megnyomva Snackbar hibát jelenít meg',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: NameScreen()));

      // Kattintás üres névmezővel
      await tester.tap(find.text('Folytatás'));
      await tester.pump(); // trigger Snackbar

      expect(find.text('A név megadása kötelező!'), findsOneWidget);
    });

    testWidgets('a névmezőbe beírva megjelenik a szöveg',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: NameScreen()));

      await tester.enterText(
        find.widgetWithText(TextField, 'Teljes név *'),
        'Teszt Elek',
      );
      expect(find.text('Teszt Elek'), findsOneWidget);
    });

    testWidgets('az email mező opcionálisan kitölthető',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: NameScreen()));

      await tester.enterText(
        find.widgetWithText(TextField, 'Email (opcionális)'),
        'teszt@example.com',
      );
      expect(find.text('teszt@example.com'), findsOneWidget);
    });
  });
}
