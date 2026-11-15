import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plantsage_app/main.dart';
import 'package:plantsage_app/screens/splash_screen.dart';

void main() {
  testWidgets('Restored app starts with the original splash and theme', (tester) async {
    await tester.pumpWidget(const PlantSageApp());

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('PlantSage'), findsOneWidget);
    expect(find.text('Your Smart Nursery Advisor'), findsOneWidget);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.useMaterial3, isTrue);
    expect(app.theme!.colorScheme.brightness, Brightness.light);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
}
