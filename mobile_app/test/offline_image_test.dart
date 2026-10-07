import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/widgets/offline_image.dart';

/// Regresszió: a `width: double.infinity` („töltse ki a szélességet”) nem
/// okozhat kivételt a dekódolási méret számításakor.
void main() {
  testWidgets('végtelen szélességű kép sem dob kivételt', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: OfflineImage.network(
              'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
              width: double.infinity,
              height: 120,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsOneWidget);
  });
}
