import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/today_sections.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:flutter_test/flutter_test.dart';

const ist = 'Asia/Kolkata';
DateTime at(int d, int h, [int m = 0]) =>
    fromWall(DateTime.utc(2026, 11, d, h, m), ist);

Reminder r(
  String id,
  DateTime? start, {
  bool allDay = false,
  ReminderCategory cat = ReminderCategory.personal,
  ReminderStatus status = ReminderStatus.active,
  DateTime? lastDone,
  String? rrule,
}) => Reminder(
  id: id,
  circleId: 'c',
  createdBy: 'me',
  title: id,
  startAt: start,
  allDay: allDay,
  category: cat,
  status: status,
  lastDoneAt: lastDone,
  rrule: rrule,
  timezone: ist,
);

void main() {
  setUpAll(ensureTimeZones);
  final now = at(9, 10); // 9 Nov, 10:00 IST

  Map<TodaySection, List<String>> ids(
    List<Reminder> rs, {
    ReminderCategory? f,
  }) => buildToday(
    rs,
    now: now,
    zone: ist,
    filter: f,
  ).map((k, v) => MapEntry(k, v.map((e) => e.reminder.id).toList()));

  test('places reminders in the right sections, sorted by time', () {
    expect(
      ids([
        r('later2', at(9, 20)),
        r('overdue', at(9, 9)),
        r('now', at(9, 10, 30)),
        r('later1', at(9, 15)),
        r('anytime', at(9, 0), allDay: true),
        r('someday', null),
        r('tomorrow', at(10, 9)),
        r('nextMonth', at(30, 9)),
        r('yesterdayAllDay', at(8, 0), allDay: true),
      ]),
      {
        TodaySection.overdue: ['yesterdayAllDay', 'overdue'],
        TodaySection.now: ['now'],
        TodaySection.later: ['later1', 'later2'],
        TodaySection.anytime: ['anytime', 'someday'],
        TodaySection.upcoming: ['tomorrow'],
      },
    );
  });

  test('done today: one-time done, and recurring done (still upcoming)', () {
    expect(
      ids([
        r('pill', at(10, 8), rrule: 'FREQ=DAILY', lastDone: at(9, 8)),
        r('bill', at(9, 8), status: ReminderStatus.done, lastDone: at(9, 8)),
        r('oldDone', at(1, 8), status: ReminderStatus.done, lastDone: at(1, 8)),
      ]),
      {
        TodaySection.upcoming: ['pill'],
        TodaySection.done: ['pill', 'bill'],
      },
    );
  });

  test('category filter', () {
    expect(
      ids([
        r('pill', at(9, 12), cat: ReminderCategory.health),
        r('rent', at(9, 12), cat: ReminderCategory.bills),
      ], f: ReminderCategory.health),
      {
        TodaySection.later: ['pill'],
      },
    );
  });

  test('a snoozed reminder sits at its snooze time', () {
    final s = r('s', at(9, 9)).copyWith(snoozedUntil: () => at(9, 14));
    expect(ids([s]), {
      TodaySection.later: ['s'],
    });
  });
}
