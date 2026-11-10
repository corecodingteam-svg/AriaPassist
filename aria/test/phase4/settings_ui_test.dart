import 'package:aria/core/router/app_router.dart';
import 'package:aria/features/account/application/app_lock.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/voice/application/voice_providers.dart';
import 'package:aria/features/voice/domain/voice_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

DateTime at(int d, int h, [int m = 0]) =>
    fromWall(DateTime.utc(2026, 11, d, h, m), kTestZone);

Reminder rem(String id, String title, DateTime start) => Reminder(
  id: id,
  circleId: kTestCircle,
  createdBy: 'u1',
  title: title,
  startAt: start,
  timezone: kTestZone,
);

Future<void> go(TestApp app, WidgetTester t, String path) async {
  app.container.read(routerProvider).push(path).ignore();
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Simple Mode: only Today + mic, no filters/search, big text', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      auth: FakeAuthRepository(userId: 'u1'),
      prefs: {'simple_mode': true},
    );
    expect(find.text('Lists'), findsNothing);
    expect(find.text('All'), findsNothing, reason: 'category chips hidden');
    expect(find.byTooltip('Search'), findsNothing);
    expect(find.bySemanticsLabel('Talk to Aria'), findsOneWidget);
    final ctx = tester.element(find.textContaining('Good'));
    expect(MediaQuery.textScalerOf(ctx).scale(10), closeTo(13, 0.01));
    app.container
        .read(appPrefsProvider.notifier)
        .update((p) => p.copyWith(simpleMode: false));
    await tester.pumpAndSettle();
    expect(find.text('Lists'), findsOneWidget);
  });

  testWidgets('quick action opens a pre-filled editor (2 taps total)', (
    tester,
  ) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    await tester.tap(find.text('Water'));
    await tester.pumpAndSettle();
    expect(find.text('Drink water'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final r = await app.db.select(app.db.reminders).getSingle();
    expect(r.title, 'Drink water');
    expect(r.category, 'health');
    expect(r.startAt!.toUtc(), at(9, 11), reason: 'next whole hour');
  });

  testWidgets('swipe left = delete (configured) with confirmation + undo', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      auth: FakeAuthRepository(userId: 'u1'),
      prefs: {'swipe_left': 'delete', 'confirm_delete': true},
    );
    final repo = app.container.read(reminderRepositoryProvider)!;
    await repo.save(rem('a', 'Old task', at(9, 18)));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Old task'),
      find.byType(ListView).first,
      const Offset(0, -120),
    );
    await tester.drag(find.text('Old task'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete this reminder?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect((await repo.get('a'))!.deletedAt, isNotNull);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect((await repo.get('a'))!.deletedAt, isNull);
  });

  testWidgets('24-hour time format applies everywhere', (tester) async {
    final app = await pumpApp(
      tester,
      auth: FakeAuthRepository(userId: 'u1'),
      prefs: {'time_format': 'h24'},
    );
    await app.container
        .read(reminderRepositoryProvider)!
        .save(rem('a', 'Dinner', at(9, 20, 30)));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Dinner'),
      find.byType(ListView).first,
      const Offset(0, -120),
    );
    expect(find.text('20:30'), findsOneWidget);
  });

  testWidgets('settings search finds individual settings', (tester) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    await go(app, tester, '/settings');
    await tester.enterText(find.byType(TextField), 'snooze');
    await tester.pumpAndSettle();
    expect(find.text('Simplify the app'), findsOneWidget);
    expect(find.text('Appearance & theme'), findsNothing);
    await tester.enterText(find.byType(TextField), 'fingerprint');
    await tester.pumpAndSettle();
    expect(find.text('Privacy & security'), findsOneWidget);
  });

  testWidgets('Simplify screen: default snooze + reset', (tester) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    await go(app, tester, '/settings/simplify');
    await tester.tap(find.byKey(const Key('simple-mode')));
    await tester.pumpAndSettle();
    expect(app.container.read(appPrefsProvider).simpleMode, isTrue);
    await tester.dragUntilVisible(
      find.byKey(const Key('reset-defaults')),
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    await tester.ensureVisible(find.byKey(const Key('reset-defaults')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reset-defaults')));
    await tester.pumpAndSettle();
    expect(app.container.read(appPrefsProvider).simpleMode, isFalse);
    expect(app.container.read(appPrefsProvider).onboarded, isTrue);
  });

  testWidgets('troubleshooter: problems, fixes, test reminder', (tester) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    app.gateway.current = const NotificationStatusOff();
    await go(app, tester, '/settings/help/troubleshooter');
    expect(
      find.text('2 things to fix'),
      findsOneWidget,
      reason: 'notifications + battery',
    );
    expect(
      find.textContaining('Autostart'),
      findsOneWidget,
      reason: 'Xiaomi guide',
    );
    await tester.tap(find.text('Allow').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Don’t optimise'));
    await tester.pumpAndSettle();
    expect(find.text('Everything looks good ✅'), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const Key('send-test')),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await tester.ensureVisible(find.byKey(const Key('send-test')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('send-test')));
    await tester.pumpAndSettle();
    expect(app.gateway.testsSent, 1);
  });

  testWidgets('onboarding: full flow saves name, language, mode', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      auth: FakeAuthRepository(userId: 'u1'),
      onboarded: false,
    );
    expect(find.text('Hi, I’m Aria 👋'), findsOneWidget);
    expect(app.speaker.spoken.single, contains("Let's set things up"));
    await tester.enterText(find.byKey(const Key('onboarding-name')), 'Rahul');
    Future<void> next() async {
      await tester.tap(find.byKey(const Key('onboarding-next')));
      await tester.pumpAndSettle();
    }

    await next(); // → language
    await tester.tap(find.text('Hinglish'));
    await next(); // → voice
    await tester.tap(find.byTooltip('Preview Aria'));
    await next(); // → mode
    await tester.tap(find.byKey(const Key('mode-text')));
    await next(); // → theme
    await next(); // → permissions
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Battery'), findsOneWidget, reason: 'Android');
    await next(); // → circle
    await next(); // → first reminder
    expect(find.textContaining('drink water at 11 AM'), findsOneWidget);
    await next(); // Finish
    expect(
      find.textContaining('Rahul'),
      findsOneWidget,
      reason: 'greeting uses the name',
    );
    final v = app.container.read(voiceSettingsProvider);
    expect(v.language, VoiceLanguage.hinglish);
    expect(v.defaultMode, NotifyMode.text);
    expect(app.container.read(appPrefsProvider).onboarded, isTrue);
  });

  testWidgets('onboarding can be skipped after step 1', (tester) async {
    final app = await pumpApp(
      tester,
      auth: FakeAuthRepository(userId: 'u1'),
      onboarded: false,
    );
    expect(find.text('Skip'), findsNothing);
    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(app.container.read(appPrefsProvider).onboarded, isTrue);
    expect(find.text('Nothing planned yet'), findsOneWidget);
  });

  testWidgets('app lock: covers the app until unlocked', (tester) async {
    final app = await pumpApp(
      tester,
      auth: FakeAuthRepository(userId: 'u1'),
      prefs: {'app_lock': true},
    );
    // FakeAuthenticator succeeds immediately at launch.
    expect(find.text('Aria is locked'), findsNothing);
    expect(
      app.container.read(authenticatorProvider) is FakeAuthenticator,
      isTrue,
    );
  });

  testWidgets('app lock: stays locked when authentication fails', (
    tester,
  ) async {
    final auth = FakeAuthenticator()..succeed = false;
    final app = await pumpApp(
      tester,
      auth: FakeAuthRepository(userId: 'u1'),
      prefs: {'app_lock': true},
      authenticator: auth,
    );
    expect(find.text('Aria is locked'), findsOneWidget);
    auth.succeed = true;
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Aria is locked'), findsNothing);
    expect(auth.prompts, 2);
    expect(app.container.read(appPrefsProvider).appLock, isTrue);
  });

  testWidgets('privacy: turning on app lock requires authenticating', (
    tester,
  ) async {
    final auth = FakeAuthenticator();
    final app = await pumpApp(
      tester,
      auth: FakeAuthRepository(userId: 'u1'),
      authenticator: auth,
    );
    await go(app, tester, '/settings/privacy');
    await tester.scrollUntilVisible(
      find.byKey(const Key('app-lock')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('app-lock')));
    await tester.pumpAndSettle();
    expect(auth.prompts, 1);
    expect(app.container.read(appPrefsProvider).appLock, isTrue);
  });

  testWidgets('privacy: delete account asks, then signs out and wipes', (
    tester,
  ) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    await app.container
        .read(reminderRepositoryProvider)!
        .save(rem('a', 'Secret', at(9, 18)));
    await go(app, tester, '/settings/privacy');
    await tester.dragUntilVisible(
      find.byKey(const Key('delete-account')),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await tester.ensureVisible(find.byKey(const Key('delete-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-account')));
    await tester.pumpAndSettle();
    expect(find.text('Delete your account?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Send code'), findsOneWidget, reason: 'signed out');
    expect(await app.db.select(app.db.reminders).get(), isEmpty);
  });

  testWidgets('aria:///talk (widgets, tile, shortcuts) opens the Talk sheet', (
    tester,
  ) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    app.container.read(routerProvider).go('/talk');
    await tester.pumpAndSettle();
    expect(find.text('Talk to Aria'), findsWidgets);
    expect(app.speech.listening, isTrue);

    // A second tap (Today already showing) opens it again.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('talk-status')), findsNothing);
    app.container.read(routerProvider).go('/talk');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('talk-status')), findsOneWidget);
  });
}
