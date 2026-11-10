import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/reminder_logic.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

enum AlertKind { reminder, morningBriefing, nightWrapUp, routine, billing }

/// One OS notification to schedule.
@immutable
class PlannedAlert {
  const PlannedAlert({
    required this.id,
    required this.reminderId,
    required this.occurrence,
    required this.attempt,
    required this.totalAttempts,
    required this.fireAt,
    required this.title,
    required this.body,
    required this.category,
    required this.priority,
    required this.mode,
    this.kind = AlertKind.reminder,
    this.quiet = false,
    this.spoken,
  });

  /// Stable OS notification id (same inputs → same id across runs).
  final int id;

  /// Reminder id, or 'briefing:morning' / 'briefing:night'.
  final String reminderId;
  final DateTime occurrence;

  /// 0 = the reminder itself, 1..n = follow-up nudges.
  final int attempt;
  final int totalAttempts;
  final DateTime fireAt;
  final String title;
  final String body;
  final ReminderCategory category;
  final Priority priority;
  final NotifyMode mode;
  final AlertKind kind;

  /// Inside quiet hours: delivered silently (no sound, no voice).
  final bool quiet;

  /// What Aria says aloud when this fires (voice / both modes).
  final String? spoken;

  bool get speaks =>
      !quiet &&
      spoken != null &&
      (mode == NotifyMode.voice || mode == NotifyMode.both);

  /// Notification payload: enough to act on it without the UI.
  String get payload =>
      '{"r":"$reminderId","o":"${occurrence.toUtc().toIso8601String()}"}';

  @override
  bool operator ==(Object other) =>
      other is PlannedAlert &&
      other.id == id &&
      other.fireAt == fireAt &&
      other.body == body &&
      other.title == title &&
      other.spoken == spoken &&
      other.quiet == quiet;
  @override
  int get hashCode => Object.hash(id, fireAt, title, body, spoken, quiet);
}

/// FNV-1a → positive 31-bit int (Android/iOS notification id).
int alertId(String reminderId, DateTime occurrence, int attempt) {
  var h = 0x811c9dc5;
  for (final c
      in '$reminderId|${occurrence.millisecondsSinceEpoch}|$attempt'
          .codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h & 0x7FFFFFFF;
}

/// Urgent reminders always nudge, even if the user turned follow-ups off.
FollowUp effectiveFollowUp(Reminder r) {
  if (r.priority == Priority.low) return FollowUp.off;
  if (r.priority == Priority.urgent && !r.followUp.enabled) {
    return const FollowUp(everyMin: 5);
  }
  return r.followUp;
}

/// Builds the spoken line for an alert (see `Phrases`).
typedef SpokenBuilder = String? Function(
  Reminder r,
  DateTime fireAt,
  int attempt,
  int total,
);

/// Whether a moment falls in quiet hours (wall-clock in the device zone).
typedef QuietCheck = bool Function(DateTime instant);

/// Builds the full set of notifications that should be pending right now.
///
/// * Recurring reminders get several future occurrences, so they keep
///   firing even if the app isn't opened for days.
/// * Quiet hours make alerts silent unless urgent (and urgent is allowed).
/// * Sorted by time and capped at [maxTotal] (iOS allows 64 pending; we
///   keep headroom for briefings). The window is refreshed on every app
///   open / resume / change, so it rolls forward.
List<PlannedAlert> planAlerts(
  Iterable<Reminder> reminders, {
  required String userId,
  required DateTime now,
  required NotifyMode defaultMode,
  NotifyMode Function(Reminder r)? modeFor,
  QuietCheck? isQuiet,
  bool urgentBypassesQuiet = true,
  SpokenBuilder? spoken,
  int maxTotal = 60,
  int occurrencesPerReminder = 4,
  Duration horizon = const Duration(days: 14),
}) {
  final out = <PlannedAlert>[];
  final end = now.add(horizon);
  for (final r in reminders) {
    if (!r.isActive || r.owner != userId || r.dueAt == null) continue;
    final mode = modeFor?.call(r) ?? r.notifyMode ?? defaultMode;
    if (mode == NotifyMode.silent) continue;

    final occurrences = <DateTime>[
      r.dueAt!,
      ...ReminderLogic.upcomingAfterAnchor(r, occurrencesPerReminder - 1),
    ];
    final follow = effectiveFollowUp(r);
    final attempts = follow.enabled ? follow.maxAttempts + 1 : 1;

    for (final occ in occurrences) {
      final base = r.snoozedUntil != null && occ == r.snoozedUntil
          ? occ
          : ReminderLogic.fireTimeFor(r, occ);
      if (base.isAfter(end)) break;
      for (var k = 0; k < attempts; k++) {
        final fire = base.add(Duration(minutes: follow.everyMin * k));
        if (!fire.isAfter(now)) continue;
        final quiet =
            (isQuiet?.call(fire) ?? false) &&
            !(urgentBypassesQuiet && r.priority == Priority.urgent);
        out.add(
          PlannedAlert(
            id: alertId(r.id, occ, k),
            reminderId: r.id,
            occurrence: occ,
            attempt: k,
            totalAttempts: attempts,
            fireAt: fire,
            title: '${r.category.emoji} ${r.title}',
            body: alertBody(r, k, attempts),
            category: r.category,
            priority: r.priority,
            mode: mode,
            quiet: quiet,
            spoken: mode == NotifyMode.voice || mode == NotifyMode.both
                ? spoken?.call(r, fire, k, attempts)
                : null,
          ),
        );
      }
    }
  }
  out.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return out.length > maxTotal ? out.sublist(0, maxTotal) : out;
}

final _rupees = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

String formatRupees(double amount) => _rupees.format(amount);

/// Warm, short microcopy (section 9).
String alertBody(Reminder r, int attempt, int total) {
  final parts = <String>[
    if (attempt == 0)
      switch (r.priority) {
        Priority.urgent => 'Urgent — please do this now',
        _ => 'Time for this now',
      }
    else if (attempt == total - 1)
      'Last nudge — tap Done when finished'
    else
      'Just checking in — still pending',
    if (r.amount != null) '${_rupees.format(r.amount)} due',
  ];
  return parts.join(' · ');
}

// ----------------------------------------------------------- briefings

/// One day's agenda for briefings and "what's on today".
@immutable
class DayAgenda {
  const DayAgenda({
    required this.entries,
    required this.bills,
    required this.birthdays,
  });

  /// (title, instant, allDay), sorted by time.
  final List<({String title, DateTime at, bool allDay})> entries;
  final int bills;
  final int birthdays;
}

/// Everything due on the local calendar day containing [day] (any instant
/// within it), including later occurrences of recurring reminders.
DayAgenda agendaFor(
  Iterable<Reminder> reminders, {
  required String userId,
  required DateTime day,
  required String zone,
}) {
  final w = toWall(day, zone);
  final start = fromWall(DateTime.utc(w.year, w.month, w.day), zone);
  final end = fromWall(DateTime.utc(w.year, w.month, w.day + 1), zone);
  final entries = <({String title, DateTime at, bool allDay})>[];
  var bills = 0;
  var birthdays = 0;
  for (final r in reminders) {
    if (!r.isActive || r.owner != userId || r.dueAt == null) continue;
    final occ = [r.dueAt!, ...ReminderLogic.upcomingAfterAnchor(r, 8)];
    for (final o in occ) {
      if (o.isBefore(start) || !o.isBefore(end)) continue;
      entries.add((
        title: r.title,
        at: o,
        allDay: r.allDay && o != r.snoozedUntil,
      ));
      if (r.category == ReminderCategory.bills) bills++;
      if (r.title.toLowerCase().contains('birthday')) birthdays++;
    }
  }
  entries.sort((a, b) => a.at.compareTo(b.at));
  return DayAgenda(entries: entries, bills: bills, birthdays: birthdays);
}

/// Next occurrence of a daily minute-of-day (wall clock) after [now].
DateTime nextDaily(DateTime now, int minuteOfDay, String zone) {
  final w = toWall(now, zone);
  var at = fromWall(
    DateTime.utc(w.year, w.month, w.day, minuteOfDay ~/ 60, minuteOfDay % 60),
    zone,
  );
  if (!at.isAfter(now)) {
    at = fromWall(
      DateTime.utc(
        w.year,
        w.month,
        w.day + 1,
        minuteOfDay ~/ 60,
        minuteOfDay % 60,
      ),
      zone,
    );
  }
  return at;
}

const kBriefingMorningId = 'briefing:morning';
const kBriefingNightId = 'briefing:night';

/// Morning briefing / night wrap-up as planned alerts. Text is computed
/// from current data and refreshed whenever the plan is (every change,
/// resume and minute), so it's accurate whenever the app has run recently.
List<PlannedAlert> planBriefings({
  required Iterable<Reminder> reminders,
  required String userId,
  required DateTime now,
  required String zone,
  required bool morning,
  required int morningAt,
  required bool night,
  required int nightAt,
  required NotifyMode mode,
  required String Function(DayAgenda agenda, DateTime when) morningText,
  required String Function(DateTime when) nightText,
}) {
  final out = <PlannedAlert>[];
  if (mode == NotifyMode.silent) return out;
  if (morning) {
    final at = nextDaily(now, morningAt, zone);
    final agenda = agendaFor(reminders, userId: userId, day: at, zone: zone);
    final text = morningText(agenda, at);
    out.add(
      PlannedAlert(
        id: alertId(kBriefingMorningId, at, 0),
        reminderId: kBriefingMorningId,
        occurrence: at,
        attempt: 0,
        totalAttempts: 1,
        fireAt: at,
        title: '☀️ Good morning',
        body: text,
        category: ReminderCategory.personal,
        priority: Priority.normal,
        mode: mode,
        kind: AlertKind.morningBriefing,
        spoken: text,
      ),
    );
  }
  if (night) {
    final at = nextDaily(now, nightAt, zone);
    final text = nightText(at);
    out.add(
      PlannedAlert(
        id: alertId(kBriefingNightId, at, 0),
        reminderId: kBriefingNightId,
        occurrence: at,
        attempt: 0,
        totalAttempts: 1,
        fireAt: at,
        title: '🌙 Night wrap-up',
        body: text,
        category: ReminderCategory.personal,
        priority: Priority.normal,
        mode: mode,
        kind: AlertKind.nightWrapUp,
        spoken: text,
      ),
    );
  }
  return out;
}

/// Time-triggered routines ("☀️ Morning mode · 4 steps"): next occurrences
/// on allowed weekdays within a week. Tapping opens the step-by-step runner.
List<PlannedAlert> planRoutineAlerts(
  Iterable<
    ({
      String id,
      String name,
      String emoji,
      int? atMinute,
      Set<int> days,
      List<String> steps,
    })
  >
  routines, {
  required DateTime now,
  required String zone,
  required NotifyMode mode,
  int perRoutine = 2,
}) {
  final out = <PlannedAlert>[];
  if (mode == NotifyMode.silent) return out;
  final today = toWall(now, zone);
  for (final r in routines) {
    if (r.atMinute == null || r.days.isEmpty) continue;
    var found = 0;
    for (var d = 0; d < 8 && found < perRoutine; d++) {
      final day = DateTime.utc(today.year, today.month, today.day + d);
      if (!r.days.contains(day.weekday)) continue;
      final at = fromWall(
        DateTime.utc(
          day.year,
          day.month,
          day.day,
          r.atMinute! ~/ 60,
          r.atMinute! % 60,
        ),
        zone,
      );
      if (!at.isAfter(now)) continue;
      found++;
      final first = r.steps.isEmpty ? '' : ' First: ${r.steps.first}.';
      out.add(
        PlannedAlert(
          id: alertId('routine:${r.id}', at, 0),
          reminderId: 'routine:${r.id}',
          occurrence: at,
          attempt: 0,
          totalAttempts: 1,
          fireAt: at,
          title: '${r.emoji} ${r.name}',
          body:
              '${r.steps.length} step${r.steps.length == 1 ? '' : 's'} · tap to start',
          category: ReminderCategory.personal,
          priority: Priority.normal,
          mode: mode,
          kind: AlertKind.routine,
          spoken: 'Time for ${r.name}.$first',
        ),
      );
    }
  }
  return out;
}

/// A Circle plan that renews or ends soon (owner only).
typedef BillingNotice = ({
  String circleId,
  String planName,
  DateTime endsAt,

  /// Won't renew by itself (trial, promo/granted, auto-renew off).
  bool ending,
});

/// Renewal heads-ups on the owner's phone, at 10 AM local:
/// * ending plans: 7, 3 and 1 day before, and when it ends;
/// * auto-renewing plans: one courtesy note 3 days before.
/// (After it ends, the server's WhatsApp/email and the in-app banner take
/// over — this phone may no longer know about the plan.)
List<PlannedAlert> planBillingAlerts(
  List<BillingNotice> notices, {
  required DateTime now,
  required String zone,
}) {
  final out = <PlannedAlert>[];
  for (final n in notices) {
    final steps = n.ending ? const [7, 3, 1, 0] : const [3];
    for (final days in steps) {
      final DateTime at;
      if (days == 0) {
        at = n.endsAt;
      } else {
        final w = toWall(n.endsAt.subtract(Duration(days: days)), zone);
        at = fromWall(DateTime.utc(w.year, w.month, w.day, 10), zone);
      }
      if (!at.isAfter(now)) continue;
      if (days > 0 && !n.endsAt.isAfter(now)) continue;
      final id = 'billing:${n.circleId}';
      final (title, body) = !n.ending
          ? (
              tr('Your {0} plan renews in 3 days', [n.planName]),
              tr('Nothing to do — tap to review or change your plan.'),
            )
          : switch (days) {
              7 => (
                tr('Your {0} plan ends in 7 days', [n.planName]),
                tr(
                  'Renew to keep premium. Your reminders stay safe either way.',
                ),
              ),
              3 => (
                tr('3 days left on your {0} plan', [n.planName]),
                tr('Renew now to keep premium features.'),
              ),
              1 => (
                tr('Your {0} plan ends tomorrow', [n.planName]),
                tr('Tap to renew.'),
              ),
              _ => (
                tr('Your {0} plan has ended', [n.planName]),
                tr('Your reminders are safe. Renew to get premium back.'),
              ),
            };
      out.add(
        PlannedAlert(
          id: alertId(id, n.endsAt, days),
          reminderId: id,
          occurrence: n.endsAt,
          attempt: 0,
          totalAttempts: 1,
          fireAt: at,
          title: title,
          body: body,
          category: ReminderCategory.bills,
          priority: Priority.normal,
          mode: NotifyMode.text,
          kind: AlertKind.billing,
        ),
      );
    }
  }
  return out;
}
