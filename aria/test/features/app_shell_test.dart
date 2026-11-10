import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/theme/presets.dart';
import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/core/theme/theme_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

Color scaffoldBg(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first))
        .scaffoldBackgroundColor;

void main() {
  testWidgets('signed out → sign-in screen; OTP signs in → Today', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    await pumpApp(tester, auth: auth);

    expect(find.text('Send code'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('sign-in-field')), '12');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid mobile number'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('sign-in-field')),
      '9999999999',
    );
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(auth.sent, ['+919999999999']);
    expect(find.text('Enter code'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('otp-field')), '123456');
    await tester.pumpAndSettle();
    expect(find.text('Nothing planned yet'), findsOneWidget);
  });

  testWidgets('shell: Today ↔ Lists tabs and the mic sheet', (tester) async {
    await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));

    expect(find.text('Nothing planned yet'), findsOneWidget);
    expect(find.bySemanticsLabel('Talk to Aria'), findsOneWidget);

    await tester.tap(find.text('Lists'));
    await tester.pumpAndSettle();
    expect(find.text('New list'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Talk to Aria'));
    await tester.pumpAndSettle();
    expect(find.text('Talk to Aria'), findsOneWidget);
  });

  testWidgets('offline banner appears when there is no network', (
    tester,
  ) async {
    await pumpApp(
      tester,
      auth: FakeAuthRepository(userId: 'u1'),
      online: false,
    );
    expect(find.textContaining("You're offline"), findsOneWidget);
  });

  testWidgets('theme, dark mode and font size apply instantly', (tester) async {
    final c = (await pumpApp(
      tester,
      auth: FakeAuthRepository(userId: 'u1'),
    )).container;
    final ctl = c.read(themeControllerProvider.notifier)
      ..setMode(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(scaffoldBg(tester), ThemePresets.lavender.light.background);

    ctl.setPreset('ocean');
    await tester.pumpAndSettle();
    expect(scaffoldBg(tester), ThemePresets.ocean.light.background);

    ctl.setMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(scaffoldBg(tester), ThemePresets.ocean.dark.background);

    ctl.setFontSize(FontSizeOption.xl);
    await tester.pumpAndSettle();
    final ctx = tester.element(find.text('Nothing planned yet'));
    expect(MediaQuery.textScalerOf(ctx).scale(10), closeTo(13, 0.01));

    // Persisted for the next cold start.
    final prefs = c.read(sharedPreferencesProvider);
    expect(prefs.getString('aria.theme.v1'), contains('"preset":"ocean"'));
  });

  testWidgets('Appearance screen swatch changes the whole app', (tester) async {
    final c = (await pumpApp(
      tester,
      auth: FakeAuthRepository(userId: 'u1'),
    )).container;
    c.read(themeControllerProvider.notifier).setMode(ThemeMode.light);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Profile and settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance & theme'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Mint Green theme'));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.text('Vitamin D'));
    expect(ctx.palette.primary, ThemePresets.mint.light.primary);
    expect(c.read(themeControllerProvider).presetId, 'mint');
  });

  testWidgets('sign out returns to sign-in', (tester) async {
    final auth = FakeAuthRepository(userId: 'u1');
    await pumpApp(tester, auth: auth);
    await tester.tap(find.byTooltip('Profile and settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Send code'), findsOneWidget);
  });

  testWidgets('meets Android tap-target and text-contrast guidelines', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
