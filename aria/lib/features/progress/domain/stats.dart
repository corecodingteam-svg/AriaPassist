import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:flutter/foundation.dart';

/// "On time" = done within this long of the due time.
const kOnTimeWindow = Duration(minutes: 30);

/// Streak milestones that earn a celebration.
const kStreakMilestones = {3, 7, 14, 21, 30, 50, 100, 365};

/// Consecutive completed occurrences of a recurring reminder, newest first,
/// stopping at the first miss. Uses deterministic done/missed events.
int streakFor(String reminderId, Iterable<ReminderEvent> events) {
  final mine =
      events
          .where(
            (e) =>
                e.reminderId == reminderId &&
                e.occurrenceAt != null &&
                (e.type == ReminderEventType.done ||
                    e.type == ReminderEventType.missed),
          )
          .toList()
        ..sort((a, b) => b.occurrenceAt!.compareTo(a.occurrenceAt!));
  var n = 0;
  final seen = <DateTime>{};
  for (final e in mine) {
    if (!seen.add(e.occurrenceAt!)) continue;
    if (e.type == ReminderEventType.missed) break;
    n++;
  }
  return n;
}

@immutable
class WeeklyReport {
  const WeeklyReport({
    required this.done,
    required this.onTime,
    required this.missed,
    required this.billsPaid,
    required this.billsOnTime,
    required this.longestStreak,
    required this.longestStreakTitle,
    required this.perDay,
  });

  /// Weekly report card (spec 5.9).
  factory WeeklyReport.build({
    required Iterable<ReminderEvent> events,
    required Iterable<Reminder> reminders,
    required DateTime now,
    required String zone,
  }) {
    final w = toWall(now, zone);
    final start = fromWall(DateTime.utc(w.year, w.month, w.day - 6), zone);
    final byId = {for (final r in reminders) r.id: r};
    final week = events.where(
      (e) => !e.at.isBefore(start) && !e.at.isAfter(now),
    );
    var done = 0;
    var onTime = 0;
    var missed = 0;
    var billsPaid = 0;
    var billsOnTime = 0;
    final perDay = List<int>.filled(7, 0);
    for (final e in week) {
      final r = byId[e.reminderId];
      if (e.type == ReminderEventType.done) {
        done++;
        final ok =
            e.occurrenceAt == null ||
            !e.at.isAfter(e.occurrenceAt!.add(kOnTimeWindow));
        if (ok) onTime++;
        if (r?.category == ReminderCategory.bills) {
          billsPaid++;
          if (ok) billsOnTime++;
        }
        final ew = toWall(e.at, zone);
        final idx =
            6 -
            DateTime.utc(
              w.year,
              w.month,
              w.day,
            ).difference(DateTime.utc(ew.year, ew.month, ew.day)).inDays;
        if (idx >= 0 && idx < 7) perDay[idx]++;
      } else if (e.type == ReminderEventType.missed) {
        missed++;
      }
    }
    var best = 0;
    String? bestTitle;
    for (final r in reminders.where((r) => r.isRecurring)) {
      final s = streakFor(r.id, events);
      if (s > best) {
        best = s;
        bestTitle = r.title;
      }
    }
    return WeeklyReport(
      done: done,
      onTime: onTime,
      missed: missed,
      billsPaid: billsPaid,
      billsOnTime: billsOnTime,
      longestStreak: best,
      longestStreakTitle: bestTitle,
      perDay: perDay,
    );
  }

  final int done;
  final int onTime;
  final int missed;
  final int billsPaid;
  final int billsOnTime;
  final int longestStreak;
  final String? longestStreakTitle;

  /// Done count per day, oldest → today (7 entries).
  final List<int> perDay;

  /// % of due things done on time (null when nothing was due).
  int? get onTimePercent {
    final total = done + missed;
    return total == 0 ? null : (onTime * 100 / total).round();
  }
}
