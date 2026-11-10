import 'dart:async';

import 'package:aria/core/telemetry/telemetry.dart';
import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/recurrence.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SuggestionKind { makeRecurring, moveTime, addFollowUp }

/// A one-tap improvement Aria noticed in the user's own history.
@immutable
class Suggestion {
  const Suggestion({
    required this.id,
    required this.kind,
    required this.message,
    required this.action,
    required this.apply,
  });

  /// Stable id, so a dismissed suggestion never comes back.
  final String id;
  final SuggestionKind kind;
  final String message;
  final String action;

  /// The change to save when accepted.
  final Reminder Function() apply;
}

String _key(String title) => title
    .toLowerCase()
    .replaceAll(RegExp(r'\b(the|my|a|an|to|for|bill|reminder)\b'), ' ')
    .replaceAll(RegExp('[^a-z0-9ऀ-ॿ ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Pure, on-device. [history] = all my reminders (any status);
/// [events] = their done/missed/snoozed events.
List<Suggestion> computeSuggestions({
  required List<Reminder> history,
  required List<ReminderEvent> events,
  required DateTime now,
  required String zone,
}) {
  final out = <Suggestion>[];
  final active = history.where((r) => r.isActive).toList();

  // 1. Same one-off reminder 3+ times, same day of month / weekday → repeat.
  final groups = <String, List<Reminder>>{};
  for (final r in history) {
    if (r.deletedAt != null || r.isRecurring || r.startAt == null) continue;
    (groups[_key(r.title)] ??= []).add(r);
  }
  for (final g in groups.values) {
    if (g.length < 3) continue;
    g.sort((a, b) => a.startAt!.compareTo(b.startAt!));
    final walls = g.map((r) => toWall(r.startAt!, r.timezone ?? zone)).toList();
    final latest = g.last;
    if (!latest.isActive) continue; // suggest on the upcoming one
    final days = walls.map((w) => w.day).toSet();
    final weekdays = walls.map((w) => w.weekday).toSet();
    final months = walls.map((w) => w.year * 12 + w.month).toSet();
    RecurrenceRule? rule;
    String? label;
    if (days.length == 1 && months.length >= 3) {
      rule = RecurrenceRule.tryParse('FREQ=MONTHLY');
      label = tr('every month on the {0}{1}', [
        walls.last.day,
        _ordinal(walls.last.day),
      ]);
    } else if (weekdays.length == 1 && g.length >= 3) {
      rule = RecurrenceRule.tryParse('FREQ=WEEKLY');
      label = tr('every week');
    }
    if (rule == null) continue;
    final r = rule;
    out.add(
      Suggestion(
        id: 'recur:${_key(latest.title)}',
        kind: SuggestionKind.makeRecurring,
        message: tr('You’ve set “{0}” {1} times. Repeat it {2}?', [
          latest.title,
          g.length,
          label,
        ]),
        action: tr('Make it repeat'),
        apply: () => latest.copyWith(rrule: r.toString),
      ),
    );
  }

  // 2. A repeating reminder usually done 45+ min late → move it.
  final cutoff = now.subtract(const Duration(days: 21));
  for (final r in active.where(
    (r) => r.isRecurring && r.startAt != null && !r.allDay,
  )) {
    final dones = events
        .where(
          (e) =>
              e.reminderId == r.id &&
              e.type == ReminderEventType.done &&
              e.occurrenceAt != null &&
              e.at.isAfter(cutoff),
        )
        .toList();
    if (dones.length < 4) continue;
    final lates =
        dones.map((e) => e.at.difference(e.occurrenceAt!).inMinutes).toList()
          ..sort();
    final median = lates[lates.length ~/ 2];
    if (median < 45 || median > 6 * 60) continue;
    final z = r.timezone ?? zone;
    final start = toWall(r.startAt!, z);
    final moved = start.add(Duration(minutes: (median / 15).round() * 15));
    final hh = moved.hour % 12 == 0 ? 12 : moved.hour % 12;
    final mm = moved.minute.toString().padLeft(2, '0');
    final ampm = moved.hour < 12 ? 'AM' : 'PM';
    out.add(
      Suggestion(
        id: 'time:${r.id}:${moved.hour}${moved.minute}',
        kind: SuggestionKind.moveTime,
        message: tr(
          'You usually do “{0}” about {1} after I remind you. Move it to {2}:{3} {4}?',
          [r.title, _dur(median), hh, mm, ampm],
        ),
        action: tr('Move to {0}:{1} {2}', [hh, mm, ampm]),
        apply: () => r.copyWith(startAt: () => fromWall(moved, z)),
      ),
    );
  }

  // 3. Missed 3+ times in 2 weeks with follow-ups off → turn them on.
  final twoWeeks = now.subtract(const Duration(days: 14));
  for (final r in active.where((r) => !r.followUp.enabled)) {
    final missed = events
        .where(
          (e) =>
              e.reminderId == r.id &&
              e.type == ReminderEventType.missed &&
              e.at.isAfter(twoWeeks),
        )
        .length;
    if (missed < 3) continue;
    out.add(
      Suggestion(
        id: 'follow:${r.id}',
        kind: SuggestionKind.addFollowUp,
        message: tr(
          '“{0}” was missed {1} times recently. Want me to nudge you again if you miss it?',
          [r.title, missed],
        ),
        action: tr('Turn on follow-ups'),
        apply: () => r.copyWith(followUp: const FollowUp()),
      ),
    );
  }
  return out;
}

String _ordinal(int d) {
  if (d >= 11 && d <= 13) return 'th';
  return switch (d % 10) {
    1 => 'st',
    2 => 'nd',
    3 => 'rd',
    _ => 'th',
  };
}

String _dur(int min) => min < 90
    ? tr('{0} minutes', [min])
    : tr('{0} hours', [(min / 60).toStringAsFixed(min % 60 == 0 ? 0 : 1)]);

/// Top suggestion not yet dismissed (premium + setting on).
final suggestionsProvider = FutureProvider<List<Suggestion>>((ref) async {
  final prefs = ref.watch(appPrefsProvider);
  if (!prefs.smartSuggestions) return const [];
  if (!ref.watch(entitlementProvider).can(Feature.smartSuggestions)) {
    return const [];
  }
  final repo = ref.watch(reminderRepositoryProvider);
  if (repo == null) return const [];
  ref.watch(myRemindersProvider); // refresh as reminders change
  final (history, events) = await (repo.allMine(), repo.events()).wait;
  final all = computeSuggestions(
    history: history,
    events: events,
    now: ref.read(clockProvider)(),
    zone: ref.read(deviceTimeZoneProvider),
  );
  return [
    for (final s in all)
      if (!prefs.dismissedTips.contains('sugg:${s.id}')) s,
  ];
});

/// Today card: one suggestion at a time, accept or "not now".
class SuggestionCard extends ConsumerWidget {
  const SuggestionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(suggestionsProvider).value?.firstOrNull;
    if (s == null) return const SizedBox.shrink();
    void dismiss() => ref
        .read(appPrefsProvider.notifier)
        .update(
          (p) =>
              p.copyWith(dismissedTips: {...p.dismissedTips, 'sugg:${s.id}'}),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: AriaTokens.s3),
      child: AriaCard(
        key: const Key('suggestion'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ExcludeSemantics(
                  child: Text('💡', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: AriaTokens.s2),
                Expanded(child: Text(s.message)),
              ],
            ),
            const SizedBox(height: AriaTokens.s2),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AriaTokens.s2,
              children: [
                TextButton(onPressed: dismiss, child: Text(tr('Not now'))),
                FilledButton.tonal(
                  key: const Key('accept-suggestion'),
                  onPressed: () async {
                    await ref.read(reminderServiceProvider)?.save(s.apply());
                    ref.read(telemetryProvider).event(
                      TelemetryEvent.suggestionAccepted,
                      {'kind': s.kind.name},
                    );
                    dismiss();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(tr('Done — updated.'))),
                      );
                    }
                  },
                  child: Text(s.action),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
