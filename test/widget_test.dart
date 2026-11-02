import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova/app.dart';
import 'package:nova/data/storage.dart';

void _setUpPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  // Haptics talk to the platform; answer with "ok" so nothing throws.
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
}

void main() {
  testWidgets('first launch shows the sign in page', (tester) async {
    _setUpPhone(tester);

    await tester.pumpWidget(NovaApp(storage: MemoryStorage()));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
  });

  testWidgets('creating an account opens Home with starter tasks', (tester) async {
    _setUpPhone(tester);

    await tester.pumpWidget(NovaApp(storage: MemoryStorage()));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Create an account', findRichText: true));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'Sara Ahmed');
    await tester.enterText(fields.at(1), 'sara@example.com');
    await tester.enterText(fields.at(2), 'secret123');

    final submit = find.widgetWithText(GestureDetector, 'Create account').last;
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('Plan your week'), findsOneWidget);

    // Let the island's auto-dismiss and the debounced save finish.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('submitting an empty sign in form shows validation errors', (tester) async {
    _setUpPhone(tester);

    await tester.pumpWidget(NovaApp(storage: MemoryStorage()));
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(GestureDetector, 'Sign in').last;
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });
}
