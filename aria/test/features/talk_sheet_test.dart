import 'package:aria/core/router/app_router.dart';
import 'package:aria/features/assistant/presentation/talk_sheet.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/voice/application/voice_providers.dart';
import 'package:aria/features/voice/domain/voice_settings.dart';
import 'package:aria/features/voice/presentation/voice_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

DateTime at(int d, int h, [int m = 0]) =>
    fromWall(DateTime.utc(2026, 11, d, h, m), kTestZone);

Future<TestApp> openTalk(WidgetTester tester) async {
  final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
  await tester.tap(find.bySemanticsLabel('Talk to Aria'));
  await tester.pumpAndSettle();
  return app;
}

String reply(WidgetTester t) =>
    t.widget<Text>(find.byKey(const Key('talk-reply'))).data!;

void main() {
  testWidgets(
    'one sentence by voice → confirmation card → ✓ → reminder saved',
    (tester) async {
      final app = await openTalk(tester);
      expect(
        app.speech.listening,
        isTrue,
        reason: 'listens as soon as it opens',
      );
      expect(app.speech.lastLocale, 'en-IN');

      app.speech.say(
        'remind me to pay the electricity bill on the 5th of every month at 10 am',
      );
      await tester.pumpAndSettle();

      expect(find.text('Pay the electricity bill'), findsOneWidget);
      expect(find.textContaining('Every month on the 5th'), findsOneWidget);
      expect(reply(tester), contains('Shall I add it?'));
      expect(app.speaker.spoken.last, contains('Shall I add it?'));

      await tester.tap(find.byKey(const Key('confirm-drafts')));
      await tester.pumpAndSettle();

      final r = await app.db.select(app.db.reminders).getSingle();
      expect(r.title, 'Pay the electricity bill');
      expect(r.rrule, 'FREQ=MONTHLY;BYMONTHDAY=5');
      expect(r.category, 'bills');
      expect(
        r.startAt!.toUtc(),
        fromWall(DateTime.utc(2026, 12, 5, 10), kTestZone),
      );
      expect(
        reply(tester),
        startsWith('Done! I’ll remind you'.replaceAll('’', "'")),
      );
    },
  );

  testWidgets('saying "yes" confirms; Hinglish works', (tester) async {
    final app = await openTalk(tester);
    app.speech.say('kal subah 8 baje dawai lene ki yaad dilana');
    await tester.pumpAndSettle();
    expect(find.text('Dawai lene'), findsOneWidget);

    await tester.tap(find.byTooltip('Speak'));
    await tester.pumpAndSettle();
    app.speech.say('haan');
    await tester.pumpAndSettle();

    final r = await app.db.select(app.db.reminders).getSingle();
    expect(r.startAt!.toUtc(), at(10, 8));
    expect(r.category, 'health');
  });

  testWidgets('multiple reminders in one sentence → two cards', (tester) async {
    final app = await openTalk(tester);
    app.speech.say('take medicine at 8 pm and call mom at 9 pm');
    await tester.pumpAndSettle();
    expect(find.text('Add 2 reminders'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-drafts')));
    await tester.pumpAndSettle();
    expect(await app.db.select(app.db.reminders).get(), hasLength(2));
  });

  testWidgets('no time → asks when; answering "at 6 pm" fills it in', (
    tester,
  ) async {
    final app = await openTalk(tester);
    app.speech.say('remind me to buy a gift');
    await tester.pumpAndSettle();
    expect(reply(tester), 'When should I remind you?');

    await tester.tap(find.byTooltip('Speak'));
    await tester.pumpAndSettle();
    app.speech.say('at 6 pm');
    await tester.pumpAndSettle();
    expect(reply(tester), contains('today at 6:00'));
    await tester.tap(find.byKey(const Key('confirm-drafts')));
    await tester.pumpAndSettle();
    final r = await app.db.select(app.db.reminders).getSingle();
    expect(r.startAt!.toUtc(), at(9, 18));
  });

  testWidgets('keyboard input works the same way', (tester) async {
    final app = await openTalk(tester);
    await tester.tap(find.byTooltip('Type instead'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('talk-input')),
      'water the plants at 6 pm',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(find.text('Water the plants'), findsOneWidget);
    expect(app.speech.listening, isTrue);
  });

  testWidgets('commands: what is on today, mark done, snooze', (tester) async {
    final app = await openTalk(tester);
    final repo = app.container.read(reminderRepositoryProvider)!;
    await repo.save(
      Reminder(
        id: 'vit',
        circleId: kTestCircle,
        createdBy: 'u1',
        title: 'Vitamin D',
        category: ReminderCategory.health,
        startAt: at(9, 11),
        timezone: kTestZone,
      ),
    );
    await tester.pumpAndSettle();

    app.speech.say("what's on today");
    await tester.pumpAndSettle();
    expect(
      reply(tester),
      contains('You have 1 thing today: Vitamin D at 11:00'),
    );

    await tester.tap(find.byTooltip('Speak'));
    await tester.pumpAndSettle();
    app.speech.say('snooze vitamin d for 30 minutes');
    await tester.pumpAndSettle();
    expect(
      (await repo.get('vit'))!.snoozedUntil,
      kTestNow.add(const Duration(minutes: 30)),
    );
    expect(reply(tester), contains("I'll remind you"));

    await tester.tap(find.byTooltip('Speak'));
    await tester.pumpAndSettle();
    app.speech.say('mark vitamin d done');
    await tester.pumpAndSettle();
    expect((await repo.get('vit'))!.status, ReminderStatus.done);
    expect(reply(tester), "Nice! That's done.");
  });

  testWidgets('personality + spoken-confirmation settings are honoured', (
    tester,
  ) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    app.container
        .read(voiceSettingsProvider.notifier)
        .update(
          (s) => s.copyWith(
            personality: Personality.coach,
            spokenConfirmations: false,
            voiceId: 'meera',
          ),
        );
    await tester.tap(find.bySemanticsLabel('Talk to Aria'));
    await tester.pumpAndSettle();
    expect(app.speech.lastLocale, 'hi-IN', reason: 'Meera listens in Hindi');
    app.speech.say('take vitamin d at 8 pm');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-drafts')));
    await tester.pumpAndSettle();
    expect(reply(tester), startsWith('Set.'));
    expect(app.speaker.spoken, isEmpty, reason: 'spoken confirmations off');
  });

  testWidgets('speech unavailable → falls back to typing', (tester) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    app.speech.available = false;
    await tester.tap(find.bySemanticsLabel('Talk to Aria'));
    await tester.pumpAndSettle();
    expect(find.textContaining('type instead'), findsOneWidget);
  });

  testWidgets('sheet can open in keyboard mode', (tester) async {
    await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    final ctx = tester.element(find.byType(Scaffold).first);
    showTalkSheet(ctx, startListening: false).ignore();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('talk-input')), findsOneWidget);
  });

  testWidgets('Today ▶ speaks the briefing', (tester) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    await app.container
        .read(reminderRepositoryProvider)!
        .save(
          Reminder(
            id: 'a',
            circleId: kTestCircle,
            createdBy: 'u1',
            title: 'Call plumber',
            startAt: at(9, 15),
            timezone: kTestZone,
          ),
        );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Play briefing'));
    await tester.pumpAndSettle();
    expect(app.speaker.spoken.single, contains('Good morning!'));
    expect(app.speaker.spoken.single, contains('Call plumber at 3:00'));
  });

  testWidgets('Voice settings: preview, lock, personality, language', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      auth: FakeAuthRepository(userId: 'u1'),
      plan: 'free',
    );
    app.container.read(routerProvider).push('/settings/voice').ignore();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Preview Meera'));
    await tester.pumpAndSettle();
    expect(app.speaker.lastVoice!.locale, 'hi-IN');
    expect(
      app.container.read(voiceSettingsProvider).voiceId,
      'aria',
      reason: 'preview does not select',
    );

    // Locked voice → paywall, selection unchanged.
    await tester.tap(find.text('Sia  🔒'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('paywall-title')), findsOneWidget);
    expect(find.text('All voices'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(app.container.read(voiceSettingsProvider).voiceId, 'aria');

    final coach = find.text('🏋️ Strict coach');
    await tester.dragUntilVisible(
      coach,
      find.descendant(
        of: find.byType(VoiceSettingsScreen),
        matching: find.byType(ListView),
      ),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(coach);
    await tester.pumpAndSettle();
    expect(
      app.container.read(voiceSettingsProvider).personality,
      Personality.coach,
    );
    expect(app.speaker.spoken.last, startsWith('8:30 AM. Vitamin D. Now.'));
  });

  testWidgets('Reminder style: per-category override persists', (tester) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    app.container
        .read(routerProvider)
        .push('/settings/reminder-style')
        .ignore();
    await tester.pumpAndSettle();
    await tester.tap(find.text('💬 Text only'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mode-health')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🔊 Voice').last);
    await tester.pumpAndSettle();
    final s = app.container.read(voiceSettingsProvider);
    expect(s.defaultMode, NotifyMode.text);
    expect(s.categoryModes[ReminderCategory.health], NotifyMode.voice);
  });
}
