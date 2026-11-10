import 'dart:async';

import 'package:aria/core/telemetry/telemetry.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/preferences/domain/app_prefs.dart';
import 'package:aria/features/progress/domain/stats.dart';
import 'package:aria/features/progress/presentation/celebration.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/today_sections.dart';
import 'package:aria/features/reminders/presentation/formatting.dart';
import 'package:aria/features/reminders/presentation/snooze_sheet.dart';
import 'package:aria/features/voice/application/voice_engine.dart';
import 'package:aria/features/voice/application/voice_providers.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// UI-side wrappers: perform the action, give haptic + warm feedback, and
/// always offer Undo for 5 seconds (section 6.4).
class ReminderActions {
  ReminderActions(this.context, this.ref);
  final BuildContext context;
  final WidgetRef ref;

  void _undoable(String message, Future<void> Function() undo) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: tr('Undo'),
            onPressed: () => unawaited(undo()),
          ),
        ),
      );
  }

  Future<void> complete(Reminder r) async {
    final service = ref.read(reminderServiceProvider);
    if (service == null) return;
    unawaited(ref.read(hapticsProvider).medium());
    final t = await service.complete(r.id);
    if (t == null) return;
    ref.read(telemetryProvider).event(TelemetryEvent.reminderDone);
    if (!context.mounted) return;
    final next =
        t.reminder.isActive && r.isRecurring && t.reminder.startAt != null
        ? tr(' Next: {0}', [
            formatWhen(
              context,
              t.reminder.startAt!,
              ref.read(deviceTimeZoneProvider),
              now: service.now(),
            ),
          ])
        : '';
    final celebration = await _celebration(r);
    if (!context.mounted) return;
    _undoable(
      celebration ?? tr('Nice! That’s done 🎉{0}', [next]),
      () => service.undo(t, r),
    );
    if (celebration != null) {
      showConfetti(context);
      final voice = ref.read(voiceSettingsProvider);
      if (voice.spokenConfirmations) {
        unawaited(
          ref
              .read(speakerProvider)
              .speak(
                celebration.replaceAll(RegExp('[🎉🔥🏆]'), ''),
                VoiceProfile.of(voice),
              ),
        );
      }
    }
  }

  /// A milestone worth celebrating after completing [r], or null.
  Future<String?> _celebration(Reminder r) async {
    if (!ref.read(appPrefsProvider).celebrations) return null;
    final repo = ref.read(reminderRepositoryProvider);
    if (repo == null) return null;
    if (r.isRecurring) {
      final streak = streakFor(r.id, await repo.events());
      if (kStreakMilestones.contains(streak)) {
        return tr('🔥 Day {0} of {1}! Keep it going.', [streak, r.title]);
      }
    }
    final zone = ref.read(deviceTimeZoneProvider);
    final now = ref.read(clockProvider)().toUtc();
    final left = buildToday(await repo.activeMine(), now: now, zone: zone)
        .entries
        .where(
          (e) => e.key != TodaySection.upcoming && e.key != TodaySection.done,
        )
        .fold<int>(0, (n, e) => n + e.value.length);
    return left == 0 ? '🎉 All done for today. Well done!' : null;
  }

  Future<void> snoozeTo(Reminder r, DateTime until) async {
    final service = ref.read(reminderServiceProvider);
    if (service == null) return;
    unawaited(ref.read(hapticsProvider).selection());
    final t = await service.snooze(r.id, until);
    if (t == null) return;
    ref.read(telemetryProvider).event(TelemetryEvent.reminderSnoozed);
    if (!context.mounted) return;
    final zone = ref.read(deviceTimeZoneProvider);
    _undoable(
      tr('No worries, I’ll remind you {0}', [
        formatWhen(
          context,
          until,
          zone,
          now: service.now(),
        ).replaceFirst('Today, ', 'at '),
      ]),
      () => service.undo(t, r),
    );
  }

  /// Swipe snooze: Settings › Simplify › Default snooze.
  Future<void> quickSnooze(Reminder r) {
    final service = ref.read(reminderServiceProvider);
    final now = service?.now() ?? DateTime.now().toUtc();
    final mins = ref.read(appPrefsProvider).defaultSnoozeMin;
    return snoozeTo(r, now.add(Duration(minutes: mins)));
  }

  /// Runs the configured swipe action.
  Future<void> swipe(Reminder r, SwipeAction action) => switch (action) {
    SwipeAction.done => complete(r),
    SwipeAction.snooze => quickSnooze(r),
    SwipeAction.delete => delete(r),
    SwipeAction.none => Future<void>.value(),
  };

  Future<void> pickSnooze(Reminder r) async {
    final until = await showSnoozeSheet(context, ref);
    if (until != null) await snoozeTo(r, until);
  }

  /// Deletes (asking first if Settings › Confirm before delete is on).
  /// Undo is always offered for 5 seconds.
  Future<void> delete(Reminder r) async {
    if (ref.read(appPrefsProvider).confirmDelete) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr('Delete this reminder?')),
          content: Text(r.title),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr('Keep')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(tr('Delete')),
            ),
          ],
        ),
      );
      if (!(ok ?? false) || !context.mounted) return;
    }
    final service = ref.read(reminderServiceProvider);
    // Captured now: Undo can be tapped after this screen has closed, when
    // `ref` is no longer usable.
    final repo = ref.read(reminderRepositoryProvider);
    if (service == null || repo == null) return;
    await service.delete(r);
    if (!context.mounted) return;
    _undoable(tr('Reminder deleted'), () => repo.restore(r));
  }
}
