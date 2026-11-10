// Accessibility audit: Flutter's guideline checks on key screens, light and
// dark, plus 200 % text size (no overflow) and Simple Mode.
import 'package:aria/core/router/app_router.dart';
import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';
import 'helpers/pump_app.dart';

const screens = [
  '/today',
  '/reminder/new',
  '/lists',
  '/me',
  '/settings',
  '/settings/appearance',
  '/settings/voice',
  '/settings/reminder-style',
  '/settings/simplify',
  '/settings/privacy',
  '/settings/connected-apps',
  '/settings/places',
  '/circle',
  '/subscription',
  '/paywall?feature=routines',
  '/routines',
  '/notes',
  '/people',
  '/notifications',
  '/search',
];

Future<TestApp> seeded(
  WidgetTester t, {
  Map<String, dynamic> prefs = const {},
}) async {
  final app = await pumpApp(
    t,
    auth: FakeAuthRepository(userId: 'u1'),
    prefs: prefs,
  );
  final repo = app.container.read(reminderRepositoryProvider)!;
  DateTime at(int h) => fromWall(DateTime.utc(2026, 11, 9, h), kTestZone);
  await repo.save(
    Reminder(
      id: 'a',
      circleId: kTestCircle,
      createdBy: 'u1',
      title: 'Take BP tablet',
      startAt: at(9),
      timezone: kTestZone,
      category: ReminderCategory.health,
      priority: Priority.urgent,
    ),
  );
  await repo.save(
    Reminder(
      id: 'b',
      circleId: kTestCircle,
      createdBy: 'u1',
      title: 'Pay electricity bill',
      startAt: at(18),
      timezone: kTestZone,
      category: ReminderCategory.bills,
      amount: 1840,
      rrule: 'FREQ=MONTHLY',
    ),
  );
  await t.pumpAndSettle();
  return app;
}

Future<void> open(TestApp app, WidgetTester t, String path) async {
  app.container.read(routerProvider).go(path);
  await t.pumpAndSettle();
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('guidelines on key screens (${dark ? 'dark' : 'light'})', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      final app = await seeded(t);
      if (dark) {
        app.container
            .read(themeControllerProvider.notifier)
            .setMode(ThemeMode.dark);
        await t.pumpAndSettle();
      }
      final failures = <String>[];
      for (final path in screens) {
        await open(app, t, path);
        for (final (name, g) in [
          ('tap target (Android 48dp)', androidTapTargetGuideline),
          ('tap target (iOS 44pt)', iOSTapTargetGuideline),
          ('labelled tap targets', labeledTapTargetGuideline),
          ('text contrast', textContrastGuideline),
        ]) {
          final r = await g.evaluate(t);
          if (!r.passed) failures.add('$path · $name\n${r.reason}');
        }
      }
      handle.dispose();
      expect(failures, isEmpty, reason: failures.join('\n\n'));
    });
  }

  for (final lang in ['en', 'hi']) {
    testWidgets('200 % text size ($lang): no overflow on key screens', (
      t,
    ) async {
      t.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(() => L10n.lang = 'en');
      final app = await seeded(t, prefs: {'app_language': lang});
      final errors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (d) => errors.add(
        '${app.container.read(routerProvider).state.uri}: ${d.exceptionAsString().split('\n').first}',
      );
      addTearDown(() => FlutterError.onError = previous);
      for (final path in screens) {
        await open(app, t, path);
      }
      FlutterError.onError = previous;
      expect(errors, isEmpty, reason: errors.toSet().join('\n'));
    });
  }

  testWidgets('Simple Mode: big targets, guidelines pass', (t) async {
    final handle = t.ensureSemantics();
    final app = await seeded(t);
    app.container
        .read(appPrefsProvider.notifier)
        .update((p) => p.copyWith(simpleMode: true));
    await t.pumpAndSettle();
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(t, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
