import 'package:aria/features/reminders/domain/recurrence.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:uuid/uuid.dart';

/// Result of a state transition: the new reminder + events to log.
typedef Transition = ({Reminder reminder, List<ReminderEvent> events});

/// All-day ("anytime") reminders alert at this local time.
const kAllDayAlertHour = 9;

const _uuid = Uuid();
const _ns = '6f1c3a52-5f0e-4d0b-9b8c-2a7a1f3e9d10'; // Aria event namespace

/// Deterministic id: two devices marking the same occurrence missed produce
/// the same row instead of a duplicate.
String eventId(String reminderId, DateTime? occurrence, ReminderEventType t) =>
    _uuid.v5(
      _ns,
      '$reminderId|${occurrence?.toUtc().toIso8601String()}|${t.name}',
    );

/// Pure reminder state machine. No I/O; every method takes `now`.
abstract final class ReminderLogic {
  /// Instant at which [occurrence] should alert (all-day → 9 AM local).
  static DateTime fireTimeFor(Reminder r, DateTime occurrence) {
    if (!r.allDay) return occurrence;
    final w = toWall(occurrence, r.timezone);
    return fromWall(
      DateTime.utc(w.year, w.month, w.day, kAllDayAlertHour),
      r.timezone,
    );
  }

  /// When a pending occurrence turns from "overdue" into "missed".
  static DateTime missedAt(Reminder r, DateTime due) {
    if (r.allDay && r.snoozedUntil == null) {
      final w = toWall(due, r.timezone);
      return fromWall(DateTime.utc(w.year, w.month, w.day + 1), r.timezone);
    }
    return fireTimeFor(r, due).add(r.followUp.missedAfter);
  }

  /// Snap a new/edited recurring reminder's start onto its first real
  /// occurrence (e.g. "weekdays" chosen on a Saturday → Monday).
  static Reminder normalize(Reminder r) {
    final rule = r.rule;
    final start = r.startAt;
    if (rule == null || start == null) return r;
    final wall = toWall(start, r.timezone);
    final first = rule.nextAfter(
      wall,
      wall.subtract(const Duration(seconds: 1)),
    );
    if (first == null) return r;
    return r.copyWith(startAt: () => fromWall(first, r.timezone));
  }

  /// Next occurrences (UTC) strictly after the current anchor.
  static List<DateTime> upcomingAfterAnchor(Reminder r, int limit) {
    final rule = r.rule;
    final start = r.startAt;
    if (rule == null || start == null) return const [];
    final anchor = toWall(start, r.timezone);
    return rule
        .occurrencesFrom(anchor, anchor.add(const Duration(seconds: 1)), limit)
        .map((w) => fromWall(w, r.timezone))
        .toList();
  }

  /// Moves a recurring series past its current occurrence.
  /// Returns null `startAt` + `status: done` when the series has ended.
  static Reminder _advance(Reminder r, {required ReminderStatus whenEnded}) {
    final rule = r.rule!;
    final anchor = toWall(r.startAt!, r.timezone);
    final next = rule.nextAfter(anchor, anchor);
    final nextRule = rule.afterConsumingOne();
    if (next == null || nextRule == null) {
      return r.copyWith(status: whenEnded, snoozedUntil: () => null);
    }
    return r.copyWith(
      startAt: () => fromWall(next, r.timezone),
      rrule: nextRule.toString,
      snoozedUntil: () => null,
    );
  }

  /// Keep-in-touch: next nudge = (now + interval) at the usual time of day.
  static Reminder _restartFrom(Reminder r, DateTime now) {
    final rule = r.rule!;
    final days = switch (rule.freq) {
      Freq.daily => rule.interval,
      Freq.weekly => 7 * rule.interval,
      Freq.monthly => 30 * rule.interval,
      Freq.yearly => 365 * rule.interval,
    };
    final time = toWall(r.startAt!, r.timezone);
    final today = toWall(now, r.timezone);
    final next = DateTime.utc(
      today.year,
      today.month,
      today.day + days,
      time.hour,
      time.minute,
    );
    return r.copyWith(
      startAt: () => fromWall(next, r.timezone),
      snoozedUntil: () => null,
    );
  }

  static Transition complete(Reminder r, String userId, DateTime now) {
    final occurrence = r.startAt;
    final event = ReminderEvent(
      id: eventId(r.id, occurrence, ReminderEventType.done),
      reminderId: r.id,
      userId: userId,
      type: ReminderEventType.done,
      at: now,
      occurrenceAt: occurrence,
    );
    final updated = r.keepInTouch && r.isRecurring && occurrence != null
        ? _restartFrom(r, now)
        : r.isRecurring && occurrence != null
        ? _advance(r, whenEnded: ReminderStatus.done)
        : r.copyWith(status: ReminderStatus.done, snoozedUntil: () => null);
    return (reminder: updated.copyWith(lastDoneAt: () => now), events: [event]);
  }

  /// Done somewhere the series couldn't be advanced (a WhatsApp "done"
  /// reply sets last_done_at on the server). Advances a recurring reminder
  /// whose current occurrence is already marked done; null if nothing to do.
  static Reminder? catchUpRemoteDone(Reminder r) {
    final done = r.lastDoneAt;
    final due = r.dueAt;
    if (!r.isActive ||
        !r.isRecurring ||
        done == null ||
        due == null ||
        done.isBefore(due)) {
      return null;
    }
    return r.keepInTouch
        ? _restartFrom(r, done)
        : _advance(r, whenEnded: ReminderStatus.done);
  }

  static Transition snooze(
    Reminder r,
    String userId,
    DateTime until,
    DateTime now,
  ) => (
    reminder: r.copyWith(
      snoozedUntil: () => until,
      // Snoozing a missed one-time reminder brings it back.
      status: ReminderStatus.active,
    ),
    events: [
      ReminderEvent(
        id: _uuid.v4(),
        reminderId: r.id,
        userId: userId,
        type: ReminderEventType.snoozed,
        at: now,
        occurrenceAt: r.startAt,
      ),
    ],
  );

  /// Marks every occurrence whose follow-up window has passed as missed.
  /// Safe to call repeatedly (idempotent ids, no change when nothing's due).
  static Transition reconcileMissed(Reminder r, String userId, DateTime now) {
    var cur = r;
    final events = <ReminderEvent>[];
    for (var i = 0; i < 400; i++) {
      final due = cur.dueAt;
      if (!cur.isActive || due == null) break;
      if (!now.isAfter(missedAt(cur, due))) break;

      final occurrence = cur.startAt;
      events.add(
        ReminderEvent(
          id: eventId(cur.id, occurrence, ReminderEventType.missed),
          reminderId: cur.id,
          userId: userId,
          type: ReminderEventType.missed,
          at: now,
          occurrenceAt: occurrence,
        ),
      );
      cur = cur.isRecurring
          ? _advance(cur, whenEnded: ReminderStatus.missed)
          : cur.copyWith(
              status: ReminderStatus.missed,
              snoozedUntil: () => null,
            );
    }
    // Absent for months: skip straight to the next future occurrence
    // instead of logging hundreds of misses.
    if (cur.isActive &&
        cur.isRecurring &&
        cur.dueAt != null &&
        now.isAfter(missedAt(cur, cur.dueAt!))) {
      final rule = cur.rule!;
      final anchor = toWall(cur.startAt!, cur.timezone);
      final next = rule.nextAfter(anchor, toWall(now, cur.timezone));
      cur = next == null
          ? cur.copyWith(status: ReminderStatus.missed)
          : cur.copyWith(startAt: () => fromWall(next, cur.timezone));
    }
    return (reminder: cur, events: events);
  }

  /// "Reschedule" from the Missed list.
  static Reminder reschedule(Reminder r, DateTime at) => r.isRecurring
      ? r.copyWith(snoozedUntil: () => at, status: ReminderStatus.active)
      : r.copyWith(
          startAt: () => at,
          snoozedUntil: () => null,
          status: ReminderStatus.active,
        );
}

/// Smart snooze options (5.3). Times are wall-clock in the given zone.
enum SnoozeOption {
  min10('10 min'),
  min15('15 min'),
  min30('30 min'),
  hour1('1 hour'),
  afterLunch('After lunch'),
  evening('This evening'),
  tomorrow('Tomorrow morning');

  SnoozeOption(this.label);
  final String label;

  /// Null when the option doesn't make sense right now (e.g. "after
  /// lunch" at 4 PM).
  DateTime? resolve(DateTime now, String? zone) {
    final w = toWall(now, zone);
    DateTime at(int dayOffset, int hour) =>
        fromWall(DateTime.utc(w.year, w.month, w.day + dayOffset, hour), zone);
    return switch (this) {
      min10 => now.add(const Duration(minutes: 10)),
      min15 => now.add(const Duration(minutes: 15)),
      min30 => now.add(const Duration(minutes: 30)),
      hour1 => now.add(const Duration(hours: 1)),
      afterLunch => w.hour < 14 ? at(0, 14) : null,
      evening => w.hour < 18 ? at(0, 18) : null,
      tomorrow => at(1, 9),
    };
  }
}

/// Presets used by the repeat chips in the editor.
enum RepeatPreset {
  never('Never', null),
  daily('Daily', RecurrenceRule.daily),
  weekdays('Weekdays', RecurrenceRule.weekdays),
  weekly('Weekly', RecurrenceRule.weekly),
  monthly('Monthly', RecurrenceRule.monthly),
  yearly('Yearly', RecurrenceRule.yearly);

  RepeatPreset(this.label, this.rule);
  final String label;
  final RecurrenceRule? rule;

  static RepeatPreset? match(String? rrule) {
    final r = RecurrenceRule.tryParse(rrule);
    if (r == null) return rrule == null ? never : null;
    for (final p in values) {
      if (p.rule == r) return p;
    }
    return null; // custom
  }
}
