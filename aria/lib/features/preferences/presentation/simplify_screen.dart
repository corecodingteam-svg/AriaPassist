// The local toggle() helper takes positional args to keep the long list
// of settings readable.
// ignore_for_file: avoid_positional_boolean_parameters

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/prompts.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/preferences/domain/app_prefs.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String fmtMinute(BuildContext context, int m) =>
    TimeOfDay(hour: m ~/ 60, minute: m % 60).format(context);

Future<int?> pickMinute(BuildContext context, int initial) async {
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
  );
  return t == null ? null : t.hour * 60 + t.minute;
}

/// Settings › Simplify the app (spec 6.4).
class SimplifyScreen extends ConsumerWidget {
  const SimplifyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(appPrefsProvider);
    final ctl = ref.read(appPrefsProvider.notifier);
    final text = Theme.of(context).textTheme;
    final muted = context.palette.muted;
    final locked = ref.watch(simpleLockedProvider);

    Widget header(String t, [String? sub]) => Padding(
      padding: const EdgeInsets.only(top: AriaTokens.s5, bottom: AriaTokens.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t, style: text.titleMedium),
          if (sub != null)
            Text(sub, style: text.bodySmall?.copyWith(color: muted)),
        ],
      ),
    );

    SwitchListTile toggle(
      String title,
      String sub,
      bool value,
      void Function(bool) on, {
      Key? key,
    }) => SwitchListTile(
      key: key,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(sub),
      value: value,
      onChanged: on,
    );

    return Scaffold(
      appBar: AppBar(title: Text(tr('Simplify the app'))),
      body: ListView(
        padding: const EdgeInsets.all(AriaTokens.s4),
        children: [
          toggle(
            tr('Simple Mode'),
            locked
                ? tr(
                    'Turned on by your Circle. Ask them for the PIN to turn it off.',
                  )
                : tr(
                    'Bigger text and buttons, only Today and the mic — ideal for elderly users',
                  ),
            ref.watch(simpleModeProvider),
            (v) async {
              if (!v && locked) {
                final pin = await promptText(
                  context,
                  title: tr('Enter the PIN'),
                  hint: tr('4 digits'),
                  action: tr('Unlock'),
                  pin: true,
                );
                final lock = ref.read(mySimpleLockProvider).value;
                if (pin == null || lock == null) return;
                if (!ref
                    .read(simpleUnlockedProvider.notifier)
                    .unlock(lock, pin)) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(tr('That PIN isn’t right'))),
                    );
                  }
                  return;
                }
              }
              ctl.update((x) => x.copyWith(simpleMode: v));
            },
            key: const Key('simple-mode'),
          ),
          header(
            tr('Default times'),
            tr('Used when you say “in the morning” or tap a time chip'),
          ),
          for (final (label, value, set)
              in <(String, int, AppPrefs Function(AppPrefs, int))>[
                (
                  tr('Morning'),
                  p.dayParts.morning,
                  (x, m) =>
                      x.copyWith(dayParts: x.dayParts.copyWith(morning: m)),
                ),
                (
                  tr('Afternoon'),
                  p.dayParts.afternoon,
                  (x, m) =>
                      x.copyWith(dayParts: x.dayParts.copyWith(afternoon: m)),
                ),
                (
                  tr('Evening'),
                  p.dayParts.evening,
                  (x, m) =>
                      x.copyWith(dayParts: x.dayParts.copyWith(evening: m)),
                ),
                (
                  tr('Night'),
                  p.dayParts.night,
                  (x, m) => x.copyWith(dayParts: x.dayParts.copyWith(night: m)),
                ),
              ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              trailing: Text(
                fmtMinute(context, value),
                style: text.titleMedium,
              ),
              onTap: () async {
                final m = await pickMinute(context, value);
                if (m != null) ctl.update((x) => set(x, m));
              },
            ),
          header(tr('Defaults for new reminders')),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Snooze for')),
            trailing: DropdownButton<int>(
              value: p.defaultSnoozeMin,
              onChanged: (v) =>
                  ctl.update((x) => x.copyWith(defaultSnoozeMin: v)),
              items: [
                for (final m in [5, 10, 15, 30, 60])
                  DropdownMenuItem(
                    value: m,
                    child: Text(m == 60 ? tr('1 hour') : tr('{0} min', [m])),
                  ),
              ],
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Category')),
            trailing: DropdownButton<ReminderCategory>(
              value: p.defaultCategory,
              onChanged: (v) =>
                  ctl.update((x) => x.copyWith(defaultCategory: v)),
              items: [
                for (final c in ReminderCategory.values)
                  DropdownMenuItem(
                    value: c,
                    child: Text('${c.emoji} ${c.label}'),
                  ),
              ],
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Priority')),
            trailing: DropdownButton<Priority>(
              value: p.defaultPriority,
              onChanged: (v) =>
                  ctl.update((x) => x.copyWith(defaultPriority: v)),
              items: [
                for (final pr in Priority.values)
                  DropdownMenuItem(value: pr, child: Text(pr.label)),
              ],
            ),
          ),
          header(tr('Quick actions on Today'), tr('Pick up to 4')),
          Wrap(
            spacing: AriaTokens.s2,
            runSpacing: AriaTokens.s2,
            children: [
              for (final q in QuickAction.values)
                FilterChip(
                  label: Text('${q.emoji} ${q.label}'),
                  selected: p.quickActions.contains(q),
                  onSelected: (on) => ctl.update((x) {
                    final list = [...x.quickActions];
                    if (on) {
                      if (list.length >= 4) list.removeAt(0);
                      list.add(q);
                    } else {
                      list.remove(q);
                    }
                    return x.copyWith(quickActions: list);
                  }),
                ),
            ],
          ),
          header(tr('Swipe gestures')),
          toggle(
            tr('Swipe on reminders'),
            tr('Act on a reminder by swiping it'),
            p.swipeEnabled,
            (v) => ctl.update((x) => x.copyWith(swipeEnabled: v)),
          ),
          if (p.swipeEnabled) ...[
            for (final (label, value, right) in [
              (tr('Swipe right'), p.swipeRight, true),
              (tr('Swipe left'), p.swipeLeft, false),
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(label),
                trailing: DropdownButton<SwipeAction>(
                  key: Key('swipe-${right ? 'right' : 'left'}'),
                  value: value,
                  onChanged: (v) => ctl.update(
                    (x) => right
                        ? x.copyWith(swipeRight: v)
                        : x.copyWith(swipeLeft: v),
                  ),
                  items: [
                    for (final a in SwipeAction.values)
                      DropdownMenuItem(value: a, child: Text(a.label)),
                  ],
                ),
              ),
          ],
          header(tr('Comfort')),
          toggle(
            tr('One-handed mode'),
            tr('Moves Today’s buttons to the bottom of the screen'),
            p.oneHanded,
            (v) => ctl.update((x) => x.copyWith(oneHanded: v)),
          ),
          toggle(
            tr('Confirm before delete'),
            tr('Undo is always available for 5 seconds'),
            p.confirmDelete,
            (v) => ctl.update((x) => x.copyWith(confirmDelete: v)),
          ),
          toggle(
            tr('Haptics'),
            tr('Gentle vibration when you tap or swipe'),
            p.haptics,
            (v) => ctl.update((x) => x.copyWith(haptics: v)),
          ),
          toggle(
            tr('Sounds'),
            tr('Little sounds for confirmations'),
            p.sounds,
            (v) => ctl.update((x) => x.copyWith(sounds: v)),
          ),
          toggle(
            tr('Smart suggestions'),
            tr(
              'Ideas like “set a monthly recharge reminder?” (never automatic)',
            ),
            p.smartSuggestions,
            (v) => ctl.update((x) => x.copyWith(smartSuggestions: v)),
          ),
          toggle(
            tr('Interactive tips'),
            tr('Short hints the first time you use something'),
            p.interactiveTips,
            (v) => ctl.update(
              (x) =>
                  x.copyWith(interactiveTips: v, dismissedTips: v ? {} : null),
            ),
          ),
          toggle(
            tr('Streaks & celebrations'),
            tr('Weekly report card, streaks and a little confetti'),
            p.celebrations,
            (v) => ctl.update((x) => x.copyWith(celebrations: v)),
          ),
          header(tr('Date & time')),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Time format')),
            trailing: SegmentedButton<TimeFormat>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: TimeFormat.system,
                  label: Text(tr('Auto')),
                ),
                const ButtonSegment(value: TimeFormat.h12, label: Text('12 h')),
                const ButtonSegment(value: TimeFormat.h24, label: Text('24 h')),
              ],
              selected: {p.timeFormat},
              onSelectionChanged: (v) =>
                  ctl.update((x) => x.copyWith(timeFormat: v.first)),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Date format')),
            trailing: DropdownButton<DateStyle>(
              value: p.dateStyle,
              onChanged: (v) => ctl.update((x) => x.copyWith(dateStyle: v)),
              items: [
                for (final d in DateStyle.values)
                  DropdownMenuItem(value: d, child: Text(d.example)),
              ],
            ),
          ),
          toggle(
            tr('Week starts on Monday'),
            tr('Off = Sunday'),
            p.weekStartsMonday,
            (v) => ctl.update((x) => x.copyWith(weekStartsMonday: v)),
          ),
          const SizedBox(height: AriaTokens.s5),
          OutlinedButton.icon(
            key: const Key('reset-defaults'),
            onPressed: () {
              ctl.update((x) => x.resetToDefaults());
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(tr('Back to simple defaults'))),
              );
            },
            icon: const Icon(Icons.restart_alt_rounded),
            label: Text(tr('Reset to simple defaults')),
          ),
        ],
      ),
    );
  }
}
