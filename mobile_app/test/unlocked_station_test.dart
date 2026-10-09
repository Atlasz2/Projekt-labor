import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/screens/login_screen.dart';
import 'package:mobile_app/widgets/station_detail_sheet.dart';
import 'package:mobile_app/widgets/unlocked_card.dart';

void main() {
  const station = {
    'id': 'st1',
    'name': 'Kinizsi-vár',
    'description': 'A vár rövid leírása.',
    'unlockContent': 'Rejtett érdekesség a várról.',
    'points': 25,
  };

  Future<void> openSheet(WidgetTester tester, {required bool completed}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showStationDetailSheet(
                context,
                station: station,
                isCompleted: completed,
              ),
              child: const Text('nyit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('nyit'));
    await tester.pumpAndSettle();
  }

  group('Állomáslap', () {
    testWidgets('teljesített állomásnál a leírás mellett a feloldott '
        'érdekesség is látszik', (tester) async {
      await openSheet(tester, completed: true);
      expect(find.text('A vár rövid leírása.'), findsOneWidget);
      expect(find.text('FELOLDOTT ÉRDEKESSÉG'), findsOneWidget);
      expect(find.text('Rejtett érdekesség a várról.'), findsOneWidget);
    });

    testWidgets('még nem teljesített állomásnál csak a lakat-jelzés', (
      tester,
    ) async {
      await openSheet(tester, completed: false);
      expect(find.text('Rejtett érdekesség a várról.'), findsNothing);
      expect(find.textContaining('feloldasz egy rejtett'), findsOneWidget);
    });
  });

  testWidgets('a feloldott tartalom kártyájáról az állomás megnyitható', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnlockedCard(
            item: const {
              'stationName': 'Kinizsi-vár',
              'content': 'Rejtett érdekesség a várról.',
              'images': <String>[],
            },
            onTapImage: () {},
            onOpenStation: () => opened = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Kinizsi-vár'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Állomás megnyitása'));
    expect(opened, isTrue);
  });

  testWidgets('a belépő képernyő felépül', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('Üdv újra!'), findsOneWidget);
    expect(find.text('Belépés'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
