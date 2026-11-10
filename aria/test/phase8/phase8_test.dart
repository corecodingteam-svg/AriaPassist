import 'package:aria/core/router/app_router.dart';
import 'package:aria/core/telemetry/telemetry.dart';
import 'package:aria/features/calendar/calendar.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/reminder_logic.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/suggestions/suggestions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

DateTime at(int m, int d, int h, [int min = 0]) =>
    fromWall(DateTime.utc(2026, m, d, h, min), kTestZone);

Future<void> go(TestApp app, WidgetTester t, String path) async {
  app.container.read(routerProvider).push(path).ignore();
  await t.pumpAndSettle();
}

Reminder rem(
  String id,
  String title,
  DateTime start, {
  String? rrule,
  ReminderStatus status = ReminderStatus.active,
}) => Reminder(
  id: id,
  circleId: kTestCircle,
  createdBy: 'u1',
  title: title,
  startAt: start,
  rrule: rrule,
  timezone: kTestZone,
  status: status,
);

ReminderEvent ev(
  String rid,
  ReminderEventType t,
  DateTime when, {
  DateTime? occ,
}) => ReminderEvent(
  id: '$rid-${when.millisecondsSinceEpoch}',
  reminderId: rid,
  userId: 'u1',
  type: t,
  at: when,
  occurrenceAt: occ,
);

void main() {
  setUpAll(ensureTimeZones);

  group('smart suggestions', () {
    test('same bill on the same day 3 months running → repeat monthly', () {
      final s = computeSuggestions(
        history: [
          rem('a', 'Pay rent', at(8, 5, 9), status: ReminderStatus.done),
          rem('b', 'pay rent', at(9, 5, 9), status: ReminderStatus.done),
          rem('c', 'Pay the rent', at(10, 5, 9), status: ReminderStatus.done),
          rem('d', 'Pay rent', at(11, 5, 9)),
        ],
        events: const [],
        now: kTestNow,
        zone: kTestZone,
      );
      expect(s.single.kind, SuggestionKind.makeRecurring);
      expect(s.single.message, contains('every month on the 5th'));
      expect(s.single.apply().rrule, 'FREQ=MONTHLY');
      expect(s.single.apply().id, 'd', reason: 'applies to the upcoming one');
    });

    test('usually done ~1 h late → move the time', () {
      final r = rem('v', 'Vitamin D', at(11, 9, 8), rrule: 'FREQ=DAILY');
      final events = [
        for (var d = 2; d <= 7; d++)
          ev('v', ReminderEventType.done, at(11, d, 9, 5), occ: at(11, d, 8)),
      ];
      final s = computeSuggestions(
        history: [r],
        events: events,
        now: kTestNow,
        zone: kTestZone,
      );
      expect(s.single.kind, SuggestionKind.moveTime);
      expect(s.single.action, 'Move to 9:00 AM');
      expect(s.single.apply().startAt, at(11, 9, 9));
    });

    test(
      'missed often with follow-ups off → offer follow-ups; quiet otherwise',
      () {
        final r = Reminder(
          id: 'm',
          circleId: kTestCircle,
          createdBy: 'u1',
          title: 'Walk',
          startAt: at(11, 10, 7),
          rrule: 'FREQ=DAILY',
          timezone: kTestZone,
          followUp: FollowUp.off,
        );
        final misses = [
          for (var d = 3; d <= 6; d++)
            ev('m', ReminderEventType.missed, at(11, d, 8)),
        ];
        final s = computeSuggestions(
          history: [r],
          events: misses,
          now: kTestNow,
          zone: kTestZone,
        );
        expect(s.single.kind, SuggestionKind.addFollowUp);
        expect(s.single.apply().followUp.enabled, isTrue);
        expect(
          computeSuggestions(
            history: [r],
            events: const [],
            now: kTestNow,
            zone: kTestZone,
          ),
          isEmpty,
        );
      },
    );

    testWidgets(
      'Today shows one suggestion; accept applies, dismissal sticks',
      (t) async {
        final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
        final repo = app.container.read(reminderRepositoryProvider)!;
        for (final (id, m) in [('a', 8), ('b', 9), ('c', 10)]) {
          await repo.save(
            rem(id, 'Pay rent', at(m, 5, 9), status: ReminderStatus.done),
          );
        }
        await repo.save(rem('d', 'Pay rent', at(12, 5, 9)));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('suggestion')), findsOneWidget);
        await t.tap(find.byKey(const Key('accept-suggestion')));
        await t.pumpAndSettle();
        expect((await repo.get('d'))!.rrule, 'FREQ=MONTHLY');
        expect(find.byKey(const Key('suggestion')), findsNothing);
        expect(
          app.telemetry.events.map((e) => e.$1),
          contains(TelemetryEvent.suggestionAccepted),
        );
      },
    );

    testWidgets('free plan: no suggestions', (t) async {
      final app = await pumpApp(
        t,
        auth: FakeAuthRepository(userId: 'u1'),
        plan: 'free',
      );
      final repo = app.container.read(reminderRepositoryProvider)!;
      for (final (id, m) in [('a', 8), ('b', 9), ('c', 10)]) {
        await repo.save(
          rem(id, 'Pay rent', at(m, 5, 9), status: ReminderStatus.done),
        );
      }
      await repo.save(rem('d', 'Pay rent', at(12, 5, 9)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('suggestion')), findsNothing);
    });
  });

  group('calendar', () {
    test('briefing line', () {
      String time(DateTime d) => '${toWall(d, kTestZone).hour}';
      final e = [
        CalendarEvent(
          id: '1',
          title: 'Standup',
          start: at(11, 9, 10),
          end: at(11, 9, 11),
        ),
        CalendarEvent(
          id: '2',
          title: 'Dentist',
          start: at(11, 9, 16),
          end: at(11, 9, 17),
        ),
      ];
      expect(
        eventsLine(e, time),
        'On your calendar: Standup at 10 and Dentist at 16.',
      );
      expect(eventsLine(const [], time), isNull);
    });

    testWidgets('turning on asks permission, then Today lists events', (
      t,
    ) async {
      final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
      app.calendar.all = [
        CalendarEvent(
          id: '1',
          title: 'Dentist',
          start: at(11, 9, 16),
          end: at(11, 9, 17),
        ),
        CalendarEvent(
          id: '2',
          title: 'Next week',
          start: at(11, 16, 9),
          end: at(11, 16, 10),
        ),
      ];
      expect(find.byKey(const Key('calendar-section')), findsNothing);
      await go(app, t, '/settings/connected-apps');
      await t.tap(find.byKey(const Key('calendar-sync')));
      await t.pumpAndSettle();
      expect(app.calendar.perm, 'granted');
      expect(app.container.read(appPrefsProvider).calendarSync, isTrue);
      app.container.read(routerProvider).go('/today');
      await t.pumpAndSettle();
      expect(find.text('📅 Calendar · 1'), findsOneWidget);
      expect(find.text('Dentist'), findsOneWidget);
      expect(find.text('Next week'), findsNothing);
    });

    testWidgets('permission refused → stays off and explains', (t) async {
      final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
      app.calendar.grantOnRequest = 'denied';
      await go(app, t, '/settings/connected-apps');
      await t.tap(find.byKey(const Key('calendar-sync')));
      await t.pumpAndSettle();
      expect(app.container.read(appPrefsProvider).calendarSync, isFalse);
      expect(find.textContaining('Allow calendar access'), findsOneWidget);
    });
  });

  group('WhatsApp', () {
    testWidgets('Family: opt in shows the number; server errors explained', (
      t,
    ) async {
      final app = await pumpApp(
        t,
        auth: FakeAuthRepository(userId: 'u1'),
        plan: 'family',
      );
      await go(app, t, '/settings/connected-apps');
      await t.tap(find.byKey(const Key('whatsapp')));
      await t.pumpAndSettle();
      expect(find.textContaining('Also sent to +919888888888'), findsOneWidget);

      await t.tap(find.byKey(const Key('whatsapp')));
      await t.pumpAndSettle();
      expect(app.whatsapp.number, isNull);
      app.whatsapp.error = Exception('no_phone');
      await t.tap(find.byKey(const Key('whatsapp')));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Sign in with your phone number'),
        findsOneWidget,
      );
    });

    testWidgets('Personal plan → paywall', (t) async {
      final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
      await go(app, t, '/settings/connected-apps');
      await t.tap(find.byKey(const Key('whatsapp')));
      await t.pumpAndSettle();
      expect(find.text('Included in Family'), findsOneWidget);
      expect(app.whatsapp.number, isNull);
    });
  });

  test(
    'recurring reminder ticked off elsewhere (WhatsApp) advances on sync',
    () {
      final r = rem(
        'v',
        'Vitamin D',
        at(11, 9, 8),
        rrule: 'FREQ=DAILY',
      ).copyWith(lastDoneAt: () => at(11, 9, 8, 5));
      expect(ReminderLogic.catchUpRemoteDone(r)!.startAt, at(11, 10, 8));
      final fresh = rem(
        'v',
        'Vitamin D',
        at(11, 10, 8),
        rrule: 'FREQ=DAILY',
      ).copyWith(lastDoneAt: () => at(11, 9, 8, 5));
      expect(
        ReminderLogic.catchUpRemoteDone(fresh),
        isNull,
        reason: 'already advanced',
      );
    },
  );

  group('telemetry', () {
    testWidgets(
      'consent: analytics off by default, crash reports on; toggles apply',
      (t) async {
        final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
        expect(app.telemetry.consent, (analytics: false, crashes: true));
        await go(app, t, '/settings/privacy');
        await t.tap(find.byKey(const Key('analytics-consent')));
        await t.pumpAndSettle();
        expect(app.telemetry.consent, (analytics: true, crashes: true));
      },
    );

    testWidgets('events carry no reminder content', (t) async {
      final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
      await t.tap(find.byTooltip('New reminder'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('title-field')),
        'Secret medical thing',
      );
      await t.tap(find.text('Tomorrow'));
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      final created = app.telemetry.events
          .where((e) => e.$1 == TelemetryEvent.reminderCreated)
          .single;
      expect(created.$2, {'source': 'tap', 'recurring': 0});
      expect(app.telemetry.events.toString(), isNot(contains('Secret')));
    });

    test('deferred telemetry buffers until Firebase attaches', () async {
      final d = DeferredTelemetry();
      await d.setConsent(analytics: true, crashes: true);
      d
        ..event(TelemetryEvent.appStart, {'ms': startupBucket(1234)})
        ..recordError(StateError('early'), null);
      final real = FakeTelemetry();
      d.attach(real);
      expect(real.consent, (analytics: true, crashes: true));
      expect(real.events.single.$2, {'ms': 1000});
      d.event(TelemetryEvent.reminderDone);
      expect(real.events.length, 2, reason: 'forwards directly once attached');
    });

    test('event names are snake_case', () {
      expect(snake(TelemetryEvent.reminderCreated.name), 'reminder_created');
      expect(snake(TelemetryEvent.paywallShown.name), 'paywall_shown');
    });
  });
}
