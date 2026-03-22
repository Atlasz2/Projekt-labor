import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/screens/name_screen.dart';

void main() {
  testWidgets('NameScreen megjeleniti az alap mezoket', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: NameScreen()));

    expect(find.text('Nagyvázsony'), findsOneWidget);
    expect(find.text('Teljes név *'), findsOneWidget);
    expect(find.text('Email (opcionális)'), findsOneWidget);
    expect(find.text('Folytatás'), findsOneWidget);
  });
}
