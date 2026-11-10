import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/reminder_logic.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/foundation.dart';

enum TodaySection {
  overdue('Overdue'),
  now('Now'),
  later('Later today'),
  anytime('Anytime'),
  place('📍 Location-based'),
  upcoming('Coming up'),
  done('Done today');

  TodaySection(this._label);
  final String _label;
  String get label => tr(_label);
}

@immutable
class TodayEntry {
  const TodayEntry(this.reminder, this.fireAt);
  final Reminder reminder;

  /// When it alerts (null for "someday" reminders with no time).
  final DateTime? fireAt;
}

/// "Now" = due within the next hour (or in the last minute).
const kNowWindow = Duration(hours: 1);
const kUpcomingDays = 7;

/// Groups reminders into the Today timeline sections, each sorted by time.
/// Empty sections are omitted.
Map<TodaySection, List<TodayEntry>> buildToday(
  Iterable<Reminder> reminders, {
  required DateTime now,
  required String zone,
  ReminderCategory? filter,
}) {
  final today = _day(toWall(now, zone));
  final out = <TodaySection, List<TodayEntry>>{};
  void add(TodaySection s, TodayEntry e) => (out[s] ??= []).add(e);

  for (final r in reminders) {
    if (r.deletedAt != null) continue;
    if (filter != null && r.category != filter) continue;

    final doneAt = r.lastDoneAt;
    if (doneAt != null &&
        _day(toWall(doneAt, zone)) == today &&
        (r.status == ReminderStatus.done || r.isRecurring)) {
      add(TodaySection.done, TodayEntry(r, doneAt));
      if (r.status == ReminderStatus.done) continue;
    }
    if (!r.isActive) continue;

    final due = r.dueAt;
    if (due == null && r.location != null) {
      add(TodaySection.place, TodayEntry(r, null));
      continue;
    }
    if (due == null) {
      add(TodaySection.anytime, TodayEntry(r, null));
      continue;
    }
    final fire = ReminderLogic.fireTimeFor(r, due);
    final dueDay = _day(toWall(due, zone));

    if (r.allDay && r.snoozedUntil == null) {
      if (dueDay == today) {
        add(TodaySection.anytime, TodayEntry(r, fire));
      } else if (dueDay.isBefore(today)) {
        add(TodaySection.overdue, TodayEntry(r, fire));
      } else if (dueDay.difference(today).inDays <= kUpcomingDays) {
        add(TodaySection.upcoming, TodayEntry(r, fire));
      }
      continue;
    }

    final section = switch (fire) {
      _ when fire.isBefore(now.subtract(const Duration(minutes: 1))) =>
        TodaySection.overdue,
      _ when fire.isBefore(now.add(kNowWindow)) => TodaySection.now,
      _ when _day(toWall(fire, zone)) == today => TodaySection.later,
      _
          when _day(toWall(fire, zone)).difference(today).inDays <=
              kUpcomingDays =>
        TodaySection.upcoming,
      _ => null,
    };
    if (section != null) add(section, TodayEntry(r, fire));
  }

  for (final list in out.values) {
    list.sort((a, b) {
      if (a.fireAt == null) return 1;
      if (b.fireAt == null) return -1;
      return a.fireAt!.compareTo(b.fireAt!);
    });
  }
  return {
    for (final s in TodaySection.values)
      if (out[s]?.isNotEmpty ?? false) s: out[s]!,
  };
}

DateTime _day(DateTime wall) => DateTime.utc(wall.year, wall.month, wall.day);
