import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/widgets/achievement_chip.dart';

// Akadálymentesítési tesztek: a Flutter beépített guideline-ellenőrzőivel
// (érintőméret, kontraszt, címkézett tap-célok) és a Semantics-fákkal.

void main() {
  testWidgets('AchievementChip státusza felolvasható (Feloldva/Zárolva)',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AchievementChip(
                achievement: Achievement(
                  title: 'Felfedező',
                  description: 'Látogass meg 3 állomást',
                  unlocked: true,
                  iconEmoji: '🧭',
                  condition: '3 állomás',
                ),
              ),
              AchievementChip(
                achievement: Achievement(
                  title: 'Túrahős',
                  description: 'Gyűjts 140 pontot',
                  unlocked: false,
                  iconEmoji: '🏃',
                  condition: '140 pont',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Feloldva'), findsOneWidget);
    expect(find.bySemanticsLabel('Zárolva'), findsOneWidget);
  });

  testWidgets('AchievementChip megfelel a szöveg-kontraszt irányelvnek',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: AchievementChip(
              achievement: Achievement(
                title: 'Felfedező',
                description: 'Látogass meg 3 állomást',
                unlocked: true,
                iconEmoji: '🧭',
                condition: '3 állomás',
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}
