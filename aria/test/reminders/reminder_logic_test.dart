import 'package:aria/features/reminders/domain/alert_plan.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/reminder_logic.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:flutter_test/flutter_test.dart';

const ist = 'Asia/Kolkata';
const ny = 'America/New_York';

/// IST wall time → UTC instant.
DateTime at(int y, int m, int d, [int h = 0, int min = 0, String z = ist]) =>
    fromWall(DateTime.utc(y, m, d, h, min), z);

Reminder r({
  String title = 'Vitamin D',
  DateTime? start,
  String? rrule,
  bool allDay = false,
  Priority priority = Priority.normal,
  FollowUp followUp = const FollowUp(),
  String zone = ist,
  String? assignedTo,
}) => Reminder(
  id: 'r1',
  circleId: 'c1',
  createdBy: 'me',
  assignedTo: assignedTo,
  title: title,
  category: ReminderCategory.health,
  startAt: start ?? at(2026, 11, 9, 8, 30),
  rrule: rrule,
  allDay: allDay,
  priority: priority,
  followUp: followUp,
  timezone: zone,
);

void main() {
  setUpAll(ensureTimeZones);

  group('timezones', () {
    test('IST wall clock ↔ instant', () {
      expect(at(2026, 11, 9, 8, 30), DateTime.utc(2026, 11, 9, 3));
      expect(
        toWall(DateTime.utc(2026, 11, 9, 3), ist),
        DateTime.utc(2026, 11, 9, 8, 30),
      );
    });

    test('daily reminder keeps 8 AM local across a DST change', () {
      // US DST ends 1 Nov 2026.
      final rem = r(
        start: at(2026, 10, 31, 8, 0, ny),
        rrule: 'FREQ=DAILY',
        zone: ny,
      );
      final next = ReminderLogic.upcomingAfterAnchor(rem, 2);
      expect(next.map((n) => toWall(n, ny).hour), [8, 8]);
      expect(next[1].difference(next[0]), const Duration(hours: 24));
      expect(
        next[0].difference(rem.startAt!),
        const Duration(hours: 25),
        reason: 'the DST day is 25 h long',
      );
    });
  });

  group('complete', () {
    test('one-time → done, follow-ups gone', () {
      final t = ReminderLogic.complete(r(), 'me', at(2026, 11, 9, 8, 31));
      expect(t.reminder.status, ReminderStatus.done);
      expect(t.reminder.lastDoneAt, isNotNull);
      expect(t.events.single.type, ReminderEventType.done);
    });

    test('recurring → advances to the next occurrence, stays active', () {
      final t = ReminderLogic.complete(
        r(rrule: 'FREQ=DAILY'),
        'me',
        at(2026, 11, 9, 9),
      );
      expect(t.reminder.status, ReminderStatus.active);
      expect(t.reminder.startAt, at(2026, 11, 10, 8, 30));
      expect(t.events.single.occurrenceAt, at(2026, 11, 9, 8, 30));
    });

    test('COUNT series finishes on the last one', () {
      var rem = r(rrule: 'FREQ=DAILY;COUNT=2');
      rem = ReminderLogic.complete(rem, 'me', at(2026, 11, 9, 9)).reminder;
      expect(rem.rrule, 'FREQ=DAILY;COUNT=1');
      expect(rem.status, ReminderStatus.active);
      rem = ReminderLogic.complete(rem, 'me', at(2026, 11, 10, 9)).reminder;
      expect(rem.status, ReminderStatus.done);
    });

    test('completing clears a snooze', () {
      final snoozed = r().copyWith(snoozedUntil: () => at(2026, 11, 9, 9));
      final t = ReminderLogic.complete(snoozed, 'me', at(2026, 11, 9, 9));
      expect(t.reminder.snoozedUntil, isNull);
    });
  });

  group('snooze', () {
    test('sets snoozedUntil and dueAt follows it', () {
      final until = at(2026, 11, 9, 9);
      final t = ReminderLogic.snooze(r(), 'me', until, at(2026, 11, 9, 8, 30));
      expect(t.reminder.dueAt, until);
      expect(t.events.single.type, ReminderEventType.snoozed);
    });

    test('smart options resolve in local time', () {
      final now = at(2026, 11, 9, 11); // 11 AM IST
      expect(SnoozeOption.afterLunch.resolve(now, ist), at(2026, 11, 9, 14));
      expect(SnoozeOption.evening.resolve(now, ist), at(2026, 11, 9, 18));
      expect(SnoozeOption.tomorrow.resolve(now, ist), at(2026, 11, 10, 9));
      expect(
        SnoozeOption.min15.resolve(now, ist),
        now.add(const Duration(minutes: 15)),
      );
      expect(
        SnoozeOption.afterLunch.resolve(at(2026, 11, 9, 16), ist),
        isNull,
        reason: 'lunch is over',
      );
    });
  });

  group('missed', () {
    test('not missed while follow-ups are still running', () {
      // default follow-up: every 10 min × 3 → missed 40 min after due.
      final t = ReminderLogic.reconcileMissed(r(), 'me', at(2026, 11, 9, 9, 5));
      expect(t.events, isEmpty);
      expect(t.reminder.status, ReminderStatus.active);
    });

    test('one-time → missed after the follow-up window', () {
      final t = ReminderLogic.reconcileMissed(
        r(),
        'me',
        at(2026, 11, 9, 9, 15),
      );
      expect(t.reminder.status, ReminderStatus.missed);
      expect(t.events.single.type, ReminderEventType.missed);
    });

    test('recurring: each missed day is logged, series continues', () {
      final t = ReminderLogic.reconcileMissed(
        r(rrule: 'FREQ=DAILY'),
        'me',
        at(2026, 11, 11, 12),
      );
      expect(t.events, hasLength(3)); // 9th, 10th, 11th
      expect(t.reminder.status, ReminderStatus.active);
      expect(t.reminder.startAt, at(2026, 11, 12, 8, 30));
    });

    test('is idempotent (deterministic event ids)', () {
      final a = ReminderLogic.reconcileMissed(r(), 'me', at(2026, 11, 10));
      final b = ReminderLogic.reconcileMissed(
        r(),
        'other-device',
        at(2026, 11, 11),
      );
      expect(a.events.single.id, b.events.single.id);
    });

    test('all-day reminders are missed only after the day ends', () {
      final rem = r(start: at(2026, 11, 9), allDay: true);
      expect(
        ReminderLogic.reconcileMissed(rem, 'me', at(2026, 11, 9, 23)).events,
        isEmpty,
      );
      expect(
        ReminderLogic.reconcileMissed(rem, 'me', at(2026, 11, 10, 0, 1)).events,
        hasLength(1),
      );
    });

    test('months away: skips ahead instead of logging hundreds', () {
      final t = ReminderLogic.reconcileMissed(
        r(rrule: 'FREQ=DAILY'),
        'me',
        at(2028, 1, 1, 12),
      );
      expect(t.events, hasLength(400));
      expect(t.reminder.startAt, at(2028, 1, 2, 8, 30));
    });

    test('reschedule brings a missed one-time reminder back', () {
      final missed = ReminderLogic.reconcileMissed(
        r(),
        'me',
        at(2026, 11, 10),
      ).reminder;
      final back = ReminderLogic.reschedule(missed, at(2026, 11, 10, 18));
      expect(back.status, ReminderStatus.active);
      expect(back.dueAt, at(2026, 11, 10, 18));
    });
  });

  group('normalize', () {
    test('weekdays picked on a Saturday start Monday', () {
      final rem = ReminderLogic.normalize(
        r(
          start: at(2026, 11, 14, 9),
          rrule: 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
        ),
      );
      expect(rem.startAt, at(2026, 11, 16, 9));
    });
  });

  group('planAlerts', () {
    final now = at(2026, 11, 9, 8);
    List<PlannedAlert> plan(Iterable<Reminder> rs, {DateTime? when}) =>
        planAlerts(
          rs,
          userId: 'me',
          now: when ?? now,
          defaultMode: NotifyMode.text,
        );

    test('main alert + follow-ups at the configured spacing', () {
      final p = plan([r()]);
      expect(p.map((a) => toWall(a.fireAt, ist).minute), [30, 40, 50, 0]);
      expect(p.first.body, 'Time for this now');
      expect(p.last.body, contains('Last nudge'));
      expect(p.first.title, '💊 Vitamin D');
    });

    test('follow-ups off → single alert; low priority never nudges', () {
      expect(plan([r(followUp: FollowUp.off)]), hasLength(1));
      expect(plan([r(priority: Priority.low)]), hasLength(1));
    });

    test('urgent always nudges', () {
      expect(
        plan([r(priority: Priority.urgent, followUp: FollowUp.off)]),
        hasLength(4),
      );
    });

    test(
      'recurring schedules several days ahead (works if app never opens)',
      () {
        final p = plan([r(rrule: 'FREQ=DAILY', followUp: FollowUp.off)]);
        expect(p.map((a) => toWall(a.fireAt, ist).day), [9, 10, 11, 12]);
      },
    );

    test('past alerts are dropped, remaining follow-ups kept', () {
      final p = plan([r()], when: at(2026, 11, 9, 8, 45));
      expect(p, hasLength(2));
    });

    test('silent mode, done, deleted, and other people’s reminders skip', () {
      expect(
        plan([
          r().copyWith(notifyMode: () => NotifyMode.silent),
          r().copyWith(status: ReminderStatus.done),
          r().copyWith(deletedAt: () => now),
          r(assignedTo: 'someone-else'),
        ]),
        isEmpty,
      );
    });

    test('capped at 60 and sorted by time (iOS limit)', () {
      final many = [
        for (var i = 0; i < 30; i++)
          Reminder(
            id: 'r$i',
            circleId: 'c',
            createdBy: 'me',
            title: 't$i',
            startAt: at(2026, 11, 9, 9, i),
            timezone: ist,
          ),
      ];
      final p = plan(many);
      expect(p, hasLength(60));
      for (var i = 1; i < p.length; i++) {
        expect(p[i].fireAt.isBefore(p[i - 1].fireAt), isFalse);
      }
    });

    test('ids are stable and distinct per occurrence/attempt', () {
      final a = plan([r(rrule: 'FREQ=DAILY')]);
      final b = plan([r(rrule: 'FREQ=DAILY')]);
      expect(a.map((x) => x.id), b.map((x) => x.id));
      expect(a.map((x) => x.id).toSet(), hasLength(a.length));
    });

    test('bills show the amount in rupees', () {
      final bill = r().copyWith(amount: () => 1840);
      expect(plan([bill]).first.body, contains('₹1,840 due'));
    });

    test('all-day reminders alert at 9 AM', () {
      final p = plan([
        r(start: at(2026, 11, 9), allDay: true, followUp: FollowUp.off),
      ]);
      expect(toWall(p.single.fireAt, ist).hour, 9);
    });
  });
}
