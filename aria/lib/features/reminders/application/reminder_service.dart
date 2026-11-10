import 'dart:async';

import 'package:aria/features/calendar/calendar.dart';
import 'package:aria/features/reminders/application/notification_gateway.dart';
import 'package:aria/features/reminders/data/reminder_repository.dart';
import 'package:aria/features/reminders/domain/alert_plan.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/reminder_logic.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/voice/domain/phrases.dart';
import 'package:aria/features/voice/domain/voice_settings.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Use-cases over reminders + keeping OS notifications in step with data.
///
/// Used by the UI (via Riverpod) **and** by the notification-action
/// background isolate, so it depends only on the repository and gateway.
/// What the planner needs about a routine (keeps this layer independent of
/// the routines feature).
typedef RoutineInfo = ({
  String id,
  String name,
  String emoji,
  int? atMinute,
  Set<int> days,
  List<String> steps,
});

class ReminderService {
  ReminderService({
    required this.repo,
    required this.gateway,
    required this.userId,
    this.defaultMode = NotifyMode.text,
    DateTime Function()? clock,
    VoiceSettings Function()? voiceSettings,
    String Function()? zone,
    bool Function()? briefingText,
    this._routines,
    this._billing,
    this._calendar,
  }) : _now = clock ?? DateTime.now,
       _voice = voiceSettings,
       _zone = zone ?? (() => 'Asia/Kolkata'),
       _briefingText = briefingText ?? (() => true);

  final ReminderRepository repo;
  final NotificationGateway gateway;
  final String userId;

  /// Used only when no [VoiceSettings] are supplied (background isolate
  /// without prefs, tests).
  final NotifyMode defaultMode;
  final DateTime Function() _now;
  final VoiceSettings Function()? _voice;

  /// Settings › Daily summary as text: when off, briefing notifications say
  /// "tap to see" instead of the full summary (the spoken version is full).
  final bool Function() _briefingText;
  final Future<List<RoutineInfo>> Function()? _routines;

  /// Plans I own that renew/end soon (3-day heads-up).
  final List<BillingNotice> Function()? _billing;

  /// Device calendar events for a local day (empty when sync is off).
  final Future<List<CalendarEvent>> Function(DateTime dayWall)? _calendar;
  final String Function() _zone;

  VoiceSettings get voiceSettings =>
      _voice?.call() ?? VoiceSettings(defaultMode: defaultMode);
  String get zone => _zone();

  DateTime now() => _now().toUtc();

  // ------------------------------------------------------------ use-cases

  Future<void> save(Reminder r) => repo.save(r);

  Future<Transition?> complete(String reminderId) async {
    final r = await repo.get(reminderId);
    if (r == null || !r.isActive) return null;
    final t = ReminderLogic.complete(r, userId, now());
    await repo.apply(t);
    await gateway.dismissFor(r.id);
    return t;
  }

  Future<Transition?> snooze(String reminderId, DateTime until) async {
    final r = await repo.get(reminderId);
    if (r == null || r.deletedAt != null) return null;
    final t = ReminderLogic.snooze(r, userId, until, now());
    await repo.apply(t);
    await gateway.dismissFor(r.id);
    return t;
  }

  Future<void> undo(Transition t, Reminder before) => repo.undo(t, before);

  Future<void> delete(Reminder r) async {
    await repo.delete(r);
    await gateway.dismissFor(r.id);
  }

  Future<void> rescheduleMissed(MissedItem m, DateTime at) async {
    await repo.save(ReminderLogic.reschedule(m.reminder, at));
    await repo.resolveMissed(m.event);
  }

  Future<void> dismissMissed(MissedItem m) => repo.resolveMissed(m.event);

  /// Night wrap-up: today's unfinished one-time reminders (overdue or
  /// missed) move to the same time tomorrow. Recurring ones carry on.
  Future<int> movePendingToTomorrow() async {
    final t = now();
    final w = toWall(t, zone);
    final todayStart = fromWall(DateTime.utc(w.year, w.month, w.day), zone);
    var moved = 0;
    for (final r in await repo.activeMine()) {
      final due = r.dueAt;
      if (r.isRecurring ||
          due == null ||
          due.isAfter(t) ||
          due.isBefore(todayStart)) {
        continue;
      }
      await repo.save(
        ReminderLogic.reschedule(r, due.add(const Duration(days: 1))),
      );
      moved++;
    }
    final missed = await repo.missed();
    for (final m in missed) {
      final occ = m.event.occurrenceAt;
      if (m.reminder.isRecurring || occ == null || occ.isBefore(todayStart)) {
        continue;
      }
      await rescheduleMissed(m, occ.add(const Duration(days: 1)));
      moved++;
    }
    return moved;
  }

  /// A notification action (foreground or background isolate).
  Future<void> handleAction(String? actionId, AlertRef? ref) async {
    if (ref == null) return;
    if (actionId == AlertAction.moveTomorrow) {
      await movePendingToTomorrow();
      await refresh();
      return;
    }
    // Bring state up to date first: the tapped alert may belong to an
    // occurrence that is now current only after older ones are marked missed.
    await refresh();
    final r = await repo.get(ref.reminderId);
    if (r == null || !r.isActive) return;

    switch (actionId) {
      case AlertAction.done:
        // Ignore stale taps for an occurrence that's already been handled.
        if (r.isRecurring &&
            r.startAt != null &&
            ref.occurrence.isBefore(r.startAt!)) {
          return;
        }
        await complete(r.id);
      case AlertAction.snooze15:
        await snooze(r.id, now().add(const Duration(minutes: 15)));
      case AlertAction.snooze60:
        await snooze(r.id, now().add(const Duration(hours: 1)));
    }
    await refresh();
  }

  // ------------------------------------------------------------ refresh

  Future<void>? _running;
  bool _again = false;

  /// Marks missed occurrences, then makes pending OS notifications match
  /// the data. Calls during a run coalesce into one follow-up run.
  Future<void> refresh() {
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      await _refreshOnce();
    } while (_again);
  }

  /// Set when the signed-in session ends; in-flight refreshes stop quietly.
  bool closed = false;

  Future<void> _refreshOnce() async {
    if (closed) return;
    final t = now();
    var active = await repo.activeMine();
    var changed = false;
    for (final r in active) {
      final caught = ReminderLogic.catchUpRemoteDone(r);
      if (caught != null) {
        await repo.save(caught);
        changed = true;
        continue;
      }
      final rec = ReminderLogic.reconcileMissed(r, userId, t);
      if (rec.events.isNotEmpty || rec.reminder.startAt != r.startAt) {
        await repo.apply(rec);
        changed = true;
      }
    }
    if (changed) active = await repo.activeMine();
    if (closed) return;
    try {
      final plan = await buildPlan(active, t);
      if (closed) return; // signed out meanwhile — don't schedule
      await gateway.apply(plan);
    } on Object catch (e) {
      if (!closed) debugPrint('notification scheduling failed: $e');
    }
  }

  /// Reminders + briefings, with voice lines, quiet hours and per-category
  /// delivery applied. Pure apart from reading settings.
  Future<List<PlannedAlert>> buildPlan(
    List<Reminder> active,
    DateTime t,
  ) async {
    final s = voiceSettings;
    final z = zone;
    final phrases = Phrases(s);
    String time(DateTime instant) {
      final w = toWall(instant, z);
      return phrases.lang == VoiceLanguage.en
          ? DateFormat.jm().format(w)
          : DateFormat('h:mm').format(w);
    }

    bool quiet(DateTime instant) {
      final w = toWall(instant, z);
      return s.quietHours.contains(w.hour * 60 + w.minute);
    }

    final reminders = planAlerts(
      active,
      userId: userId,
      now: t,
      defaultMode: s.defaultMode,
      modeFor: s.modeFor,
      isQuiet: quiet,
      urgentBypassesQuiet: s.quietHours.allowUrgent,
      spoken: (r, fire, k, total) => k == 0
          ? phrases.due(
              r.title,
              time(fire),
              seed: '${r.id}${fire.millisecondsSinceEpoch}',
              extra: r.amount == null ? null : '${formatRupees(r.amount!)} due',
            )
          : phrases.followUp(r.title, last: k == total - 1, seed: r.id),
    );

    String dayLine(DayAgenda a, String dayWord) => phrases.daySummary(
      dayWord: dayWord,
      items: [
        for (final e in a.entries)
          e.allDay ? e.title : tr('{0} at {1}', [e.title, time(e.at)]),
      ],
      bills: a.bills,
      birthdays: a.birthdays,
    );

    // Calendar lines for today's and tomorrow's morning briefings.
    final todayWall = toWall(t, z);
    final eventsByDay = <int, List<CalendarEvent>>{};
    if (_calendar != null) {
      for (var d = 0; d < 2; d++) {
        final day = DateTime.utc(
          todayWall.year,
          todayWall.month,
          todayWall.day + d,
        );
        try {
          eventsByDay[day.day] = await _calendar(day);
        } on Object {
          // calendar unavailable — briefing without it
        }
      }
    }

    final briefings =
        planBriefings(
              reminders: active,
              userId: userId,
              now: t,
              zone: z,
              morning: s.briefings.morningEnabled,
              morningAt: s.briefings.morningAt,
              night: s.briefings.nightEnabled,
              nightAt: s.briefings.nightAt,
              mode: s.defaultMode == NotifyMode.silent
                  ? NotifyMode.text
                  : s.defaultMode,
              morningText: (agenda, at) {
                final cal = eventsLine(
                  eventsByDay[toWall(at, z).day] ?? const [],
                  time,
                );
                return '${phrases.greeting('morning')} ${dayLine(agenda, 'today')}'
                    '${cal == null ? '' : ' $cal'}';
              },
              nightText: (at) {
                final today = agendaFor(
                  active,
                  userId: userId,
                  day: at,
                  zone: z,
                );
                final pending = today.entries
                    .where((e) => !e.at.isAfter(at))
                    .length;
                final doneToday = active
                    .where(
                      (r) =>
                          r.lastDoneAt != null &&
                          toWall(r.lastDoneAt!, z).day == toWall(at, z).day,
                    )
                    .length;
                final tomorrow = agendaFor(
                  active,
                  userId: userId,
                  day: at.add(const Duration(days: 1)),
                  zone: z,
                );
                return phrases.wrapUp(
                  done: doneToday,
                  pending: pending,
                  tomorrow: dayLine(tomorrow, 'tomorrow'),
                );
              },
            )
            .where(
              (b) => !quiet(b.fireAt) || b.kind == AlertKind.morningBriefing,
            )
            .toList();

    final briefingsShown = _briefingText()
        ? briefings
        : [
            for (final b in briefings)
              PlannedAlert(
                id: b.id,
                reminderId: b.reminderId,
                occurrence: b.occurrence,
                attempt: b.attempt,
                totalAttempts: b.totalAttempts,
                fireAt: b.fireAt,
                title: b.title,
                body: b.kind == AlertKind.morningBriefing
                    ? "Tap to see today's plan"
                    : 'Tap to review your day',
                category: b.category,
                priority: b.priority,
                mode: b.mode,
                kind: b.kind,
                quiet: b.quiet,
                spoken: b.spoken,
              ),
          ];
    final routineAlerts = planRoutineAlerts(
      await _routines?.call() ?? const [],
      now: t,
      zone: z,
      mode: s.defaultMode == NotifyMode.silent
          ? NotifyMode.text
          : s.defaultMode,
    ).where((a) => !quiet(a.fireAt)).toList();
    final billingAlerts = planBillingAlerts(
      _billing?.call() ?? const [],
      now: t,
      zone: z,
    );
    return [...reminders, ...briefingsShown, ...routineAlerts, ...billingAlerts]
      ..sort((a, b) => a.fireAt.compareTo(b.fireAt));
  }
}
