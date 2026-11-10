import 'package:aria/data/local/app_database.dart';
import 'package:aria/data/sync/local_store.dart';
import 'package:aria/features/reminders/application/notification_gateway.dart';
import 'package:aria/features/reminders/application/reminder_service.dart';
import 'package:aria/features/reminders/data/reminder_repository.dart';
import 'package:aria/features/reminders/domain/alert_plan.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/voice/domain/voice_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

DateTime at(int d, int h, [int m = 0]) =>
    fromWall(DateTime.utc(2026, 11, d, h, m), kTestZone);

void main() {
  late AppDatabase db;
  late LocalStore store;
  late ReminderRepository repo;
  late FakeNotificationGateway gateway;
  late ReminderService service;
  late DateTime now;

  Reminder pill({String? rrule = 'FREQ=DAILY'}) => Reminder(
    id: 'pill',
    circleId: kTestCircle,
    createdBy: 'me',
    title: 'Vitamin D',
    category: ReminderCategory.health,
    startAt: at(9, 8, 30),
    rrule: rrule,
    timezone: kTestZone,
  );

  setUp(() async {
    ensureTimeZones();
    now = at(9, 8);
    db = memoryDb();
    store = LocalStore(db, clock: () => now);
    repo = ReminderRepository(db, store, userId: 'me');
    gateway = FakeNotificationGateway();
    service = ReminderService(
      repo: repo,
      gateway: gateway,
      userId: 'me',
      clock: () => now,
    );
  });
  tearDown(() => db.close());

  test('save → persisted, queued for sync, and scheduled', () async {
    await service.save(pill());
    await service.refresh();

    expect((await repo.get('pill'))!.title, 'Vitamin D');
    expect(await store.pendingCount(), 1);
    expect(gateway.reminderAlerts.first.fireAt, at(9, 8, 30));
    expect(gateway.reminderAlerts.first.title, '💊 Vitamin D');
  });

  test('complete recurring → next day, done event, alerts move on', () async {
    await service.save(pill());
    now = at(9, 8, 31);
    final t = await service.complete('pill');
    await service.refresh();

    final r = (await repo.get('pill'))!;
    expect(r.startAt, at(10, 8, 30));
    expect(r.lastDoneAt, now);
    expect(t!.events.single.type, ReminderEventType.done);
    expect(gateway.dismissed, ['pill']);
    expect(
      gateway.reminderAlerts.first.fireAt,
      at(10, 8, 30),
      reason: "today's follow-ups are gone",
    );
  });

  test('undo restores the previous state and retracts the event', () async {
    await service.save(pill(rrule: null));
    final before = (await repo.get('pill'))!;
    final t = await service.complete('pill');
    await service.undo(t!, before);

    final r = (await repo.get('pill'))!;
    expect(r.status, ReminderStatus.active);
    final ev = await db.select(db.reminderEvents).getSingle();
    expect(ev.deletedAt, isNotNull);
  });

  test('refresh marks missed occurrences and lists them', () async {
    await service.save(pill(rrule: null));
    now = at(9, 12);
    await service.refresh();

    expect((await repo.get('pill'))!.status, ReminderStatus.missed);
    final missed = await repo.watchMissed().first;
    expect(missed.single.reminder.id, 'pill');
    expect(gateway.reminderAlerts, isEmpty);

    await service.rescheduleMissed(missed.single, at(9, 18));
    expect((await repo.get('pill'))!.status, ReminderStatus.active);
    expect(await repo.watchMissed().first, isEmpty);
    await service.refresh();
    expect(gateway.reminderAlerts.first.fireAt, at(9, 18));
  });

  test('notification Done for the current occurrence completes it', () async {
    await service.save(pill());
    now = at(9, 8, 35);
    await service.handleAction(AlertAction.done, (
      reminderId: 'pill',
      occurrence: at(9, 8, 30),
    ));
    expect((await repo.get('pill'))!.startAt, at(10, 8, 30));
  });

  test('a stale Done for an already-handled occurrence is ignored', () async {
    await service.save(pill());
    now = at(9, 8, 35);
    await service.complete('pill'); // → 10 Nov
    await service.handleAction(AlertAction.done, (
      reminderId: 'pill',
      occurrence: at(9, 8, 30),
    ));
    expect(
      (await repo.get('pill'))!.startAt,
      at(10, 8, 30),
      reason: 'must not skip tomorrow',
    );
  });

  test('notification Snooze 15 → snoozed, alert rescheduled', () async {
    await service.save(pill(rrule: null));
    now = at(9, 8, 30);
    await service.handleAction(AlertAction.snooze15, (
      reminderId: 'pill',
      occurrence: at(9, 8, 30),
    ));
    final r = (await repo.get('pill'))!;
    expect(r.snoozedUntil, at(9, 8, 45));
    expect(gateway.reminderAlerts.first.fireAt, at(9, 8, 45));
  });

  test('payload round-trips through the OS string', () {
    final p = parsePayload(
      stripFireTime(
        '{"r":"pill","o":"2026-11-09T03:00:00.000Z"}|1762657200000',
      ),
    );
    expect(p!.reminderId, 'pill');
    expect(p.occurrence, DateTime.utc(2026, 11, 9, 3));
  });

  test("other users' reminders in a shared circle are not scheduled", () async {
    await service.save(
      pill(rrule: null).copyWith(assignedTo: () => 'someone-else'),
    );
    await service.refresh();
    expect(gateway.reminderAlerts, isEmpty);
  });

  test('search matches title and notes', () async {
    await service.save(
      pill(rrule: null).copyWith(notes: () => 'after breakfast'),
    );
    expect(await repo.search('vitamin'), hasLength(1));
    expect(await repo.search('BREAKFAST'), hasLength(1));
    expect(await repo.search('rent'), isEmpty);
  });

  group('voice, quiet hours and briefings', () {
    ReminderService withSettings(VoiceSettings vs) => ReminderService(
      repo: repo,
      gateway: gateway,
      userId: 'me',
      clock: () => now,
      voiceSettings: () => vs,
      zone: () => kTestZone,
    );

    test(
      'voice mode attaches a spoken line in the chosen personality',
      () async {
        final s = withSettings(
          const VoiceSettings(personality: Personality.coach),
        );
        await s.save(pill(rrule: null));
        await s.refresh();
        final first = gateway.reminderAlerts.first;
        expect(first.speaks, isTrue);
        expect(first.spoken, startsWith('8:30\u202fAM. Vitamin D.'));
        expect(gateway.reminderAlerts[1].spoken, 'Still waiting: Vitamin D.');
      },
    );

    test('per-category override: Health = voice, Bills = text', () async {
      final s = withSettings(
        const VoiceSettings(
          defaultMode: NotifyMode.text,
          categoryModes: {ReminderCategory.health: NotifyMode.voice},
        ),
      );
      await s.save(pill(rrule: null));
      await s.save(
        pill(rrule: null)
            .copyWith(category: ReminderCategory.bills)
            .copyWithId('bill'),
      );
      await s.refresh();
      final byId = {
        for (final a in gateway.reminderAlerts.where((a) => a.attempt == 0))
          a.reminderId: a,
      };
      expect(byId['pill']!.speaks, isTrue);
      expect(byId['bill']!.speaks, isFalse);
      expect(byId['bill']!.mode, NotifyMode.text);
    });

    test('text-only mode never speaks', () async {
      final s = withSettings(const VoiceSettings(defaultMode: NotifyMode.text));
      await s.save(pill());
      await s.refresh();
      expect(gateway.scheduled.where((a) => a.speaks), isEmpty);
    });

    test('quiet hours silence alerts but let urgent through', () async {
      const qh = QuietHours(enabled: true, start: 7 * 60, end: 9 * 60);
      final s = withSettings(const VoiceSettings(quietHours: qh));
      await s.save(pill(rrule: null));
      await s.save(
        pill(rrule: null)
            .copyWith(priority: Priority.urgent)
            .copyWithId('urgent'),
      );
      await s.refresh();
      final first = {
        for (final a in gateway.reminderAlerts.where((a) => a.attempt == 0))
          a.reminderId: a,
      };
      expect(first['pill']!.quiet, isTrue);
      expect(first['pill']!.speaks, isFalse);
      expect(first['urgent']!.quiet, isFalse);
      expect(first['urgent']!.speaks, isTrue);
    });

    test(
      'morning briefing summarises the day; night wrap offers to move',
      () async {
        final s = withSettings(const VoiceSettings());
        await s.save(pill(rrule: null)); // 9 Nov 8:30
        await s.save(
          pill(rrule: null)
              .copyWith(
                category: ReminderCategory.bills,
                startAt: () => at(10, 10),
                amount: () => 1840,
              )
              .copyWithId('bill')
              .copyWithTitle('Pay electricity bill'),
        );
        await s.refresh();
        final morning = gateway.scheduled.singleWhere(
          (a) => a.kind == AlertKind.morningBriefing,
        );
        // now = 9 Nov 08:00 → next briefing is 10 Nov 07:30.
        expect(morning.fireAt, at(10, 7, 30));
        expect(morning.body, contains('Good morning!'));
        expect(morning.body, contains('Pay electricity bill at 10:00'));
        expect(morning.body, contains('1 bill due'));

        final night = gateway.scheduled.singleWhere(
          (a) => a.kind == AlertKind.nightWrapUp,
        );
        expect(night.fireAt, at(9, 22));
        expect(night.body, contains('still pending'));
        expect(night.body, contains('tomorrow'));
      },
    );

    test('move pending to tomorrow (night wrap-up action)', () async {
      final s = withSettings(const VoiceSettings());
      await s.save(pill(rrule: null)); // due 8:30, now 21:00 → overdue/missed
      now = at(9, 21);
      await s.refresh(); // marks it missed
      await s.handleAction(AlertAction.moveTomorrow, (
        reminderId: 'briefing:night',
        occurrence: at(9, 22),
      ));
      final r = (await repo.get('pill'))!;
      expect(r.status, ReminderStatus.active);
      expect(r.dueAt, at(10, 8, 30));
      expect(await repo.watchMissed().first, isEmpty);
    });
  });
}
