import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freshmarket/features/splash/presentation/splash_screen.dart';

void main() {
  testWidgets('FreshMarketApp boots and displays splash branding', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SplashScreen())),
    );

    // Initial frame renders splash screen with FreshMarket branding
    expect(find.text('FreshMarket'), findsOneWidget);
    expect(find.text('Farm-Fresh Meat & Groceries'), findsOneWidget);

    // Pump past the splash delay timer
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
  });
}
