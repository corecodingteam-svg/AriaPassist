import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/reminders/application/notification_gateway.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/voice/application/voice_providers.dart';
import 'package:aria/features/voice/domain/voice_settings.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Map<NotifyMode, (String, String)> get kModeLabels => {
  NotifyMode.voice: ('🔊', tr('Voice')),
  NotifyMode.text: ('💬', tr('Text only')),
  NotifyMode.both: ('🔊💬', tr('Both')),
  NotifyMode.vibrate: ('📳', tr('Vibrate')),
  NotifyMode.silent: ('🔕', tr('Silent')),
};

String _fmtMinute(BuildContext context, int m) =>
    TimeOfDay(hour: m ~/ 60, minute: m % 60).format(context);

Future<int?> _pickMinute(BuildContext context, int initial) async {
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
  );
  return t == null ? null : t.hour * 60 + t.minute;
}

/// Settings › Reminder style (6.2) incl. quiet hours (6.6).
class ReminderStyleScreen extends ConsumerWidget {
  const ReminderStyleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(voiceSettingsProvider);
    final ctl = ref.read(voiceSettingsProvider.notifier);
    final text = Theme.of(context).textTheme;
    final muted = context.palette.muted;
    final q = s.quietHours;
    final prefs = ref.watch(appPrefsProvider);
    final pctl = ref.read(appPrefsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(tr('Reminder style'))),
      body: ListView(
        padding: const EdgeInsets.all(AriaTokens.s4),
        children: [
          Text(tr('Default reminder mode'), style: text.titleMedium),
          Text(
            tr('How reminders reach you unless a category says otherwise'),
            style: text.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: AriaTokens.s3),
          Wrap(
            spacing: AriaTokens.s2,
            runSpacing: AriaTokens.s2,
            children: [
              for (final MapEntry(key: mode, value: (emoji, label))
                  in kModeLabels.entries)
                ChoiceChip(
                  label: Text('$emoji $label'),
                  selected: s.defaultMode == mode,
                  onSelected: (_) =>
                      ctl.update((x) => x.copyWith(defaultMode: mode)),
                ),
            ],
          ),
          const SizedBox(height: AriaTokens.s5),
          Text(tr('Per category'), style: text.titleMedium),
          Text(
            tr('e.g. voice for medicines, text for bills'),
            style: text.bodySmall?.copyWith(color: muted),
          ),
          for (final c in ReminderCategory.values)
            Builder(
              builder: (context) {
                // Large text: dropdown goes under the name, not beside it.
                final large =
                    MediaQuery.textScalerOf(context).scale(14) > 14 * 1.3;
                final dd = DropdownButton<NotifyMode?>(
                  key: Key('mode-${c.name}'),
                  value: s.categoryModes[c],
                  onChanged: (m) => ctl.update((x) {
                    final map = {...x.categoryModes};
                    if (m == null) {
                      map.remove(c);
                    } else {
                      map[c] = m;
                    }
                    return x.copyWith(categoryModes: map);
                  }),
                  items: [
                    DropdownMenuItem(child: Text(tr('Default'))),
                    for (final MapEntry(key: mode, value: (emoji, label))
                        in kModeLabels.entries)
                      DropdownMenuItem(
                        value: mode,
                        child: Text('$emoji $label'),
                      ),
                  ],
                );
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ExcludeSemantics(
                    child: Text(c.emoji, style: const TextStyle(fontSize: 22)),
                  ),
                  title: Text(c.label),
                  subtitle: large ? dd : null,
                  trailing: large ? null : dd,
                );
              },
            ),
          const SizedBox(height: AriaTokens.s4),
          Text(tr('Follow-up nudges'), style: text.titleMedium),
          Text(
            tr('If you don’t mark a reminder done, Aria reminds you again'),
            style: text.bodySmall?.copyWith(color: muted),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Follow up on new reminders')),
            value: prefs.followUpEnabled,
            onChanged: (v) =>
                pctl.update((x) => x.copyWith(followUpEnabled: v)),
          ),
          if (prefs.followUpEnabled)
            Row(
              children: [
                Text(tr('Every')),
                const SizedBox(width: AriaTokens.s2),
                DropdownButton<int>(
                  value: prefs.followUpEveryMin,
                  onChanged: (v) =>
                      pctl.update((x) => x.copyWith(followUpEveryMin: v)),
                  items: [
                    for (final m in [5, 10, 15, 30])
                      DropdownMenuItem(
                        value: m,
                        child: Text(tr('{0} min', [m])),
                      ),
                  ],
                ),
                const SizedBox(width: AriaTokens.s4),
                Text(tr('up to')),
                const SizedBox(width: AriaTokens.s2),
                DropdownButton<int>(
                  value: prefs.followUpMax,
                  onChanged: (v) =>
                      pctl.update((x) => x.copyWith(followUpMax: v)),
                  items: [
                    for (final n in [1, 2, 3, 4, 5])
                      DropdownMenuItem(value: n, child: Text('$n×')),
                  ],
                ),
              ],
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Full-screen alert for urgent reminders')),
            subtitle: Text(tr('Takes over the screen so you can’t miss it')),
            value: prefs.fullScreenUrgent,
            onChanged: (v) =>
                pctl.update((x) => x.copyWith(fullScreenUrgent: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Daily summary as text')),
            subtitle: Text(tr('Show the full briefing in the notification')),
            value: prefs.dailySummaryText,
            onChanged: (v) =>
                pctl.update((x) => x.copyWith(dailySummaryText: v)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Notification sound & vibration')),
            subtitle: Text(
              tr(
                'Each category has its own channel — fine-tune it in your phone’s settings',
              ),
            ),
            trailing: const Icon(Icons.open_in_new_rounded),
            onTap: () async {
              final gw = ref.read(notificationGatewayProvider);
              if (gw is LocalNotificationGateway) {
                await gw.openNotificationSettings();
              }
            },
          ),
          const SizedBox(height: AriaTokens.s4),
          Text(tr('Quiet hours'), style: text.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Silence reminders at night')),
            subtitle: Text(
              q.enabled
                  ? tr('{0} – {1} · shown silently', [
                      _fmtMinute(context, q.start),
                      _fmtMinute(context, q.end),
                    ])
                  : tr('Off'),
            ),
            value: q.enabled,
            onChanged: (v) => ctl.update(
              (x) => x.copyWith(quietHours: x.quietHours.copyWith(enabled: v)),
            ),
          ),
          if (q.enabled) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final m = await _pickMinute(context, q.start);
                      if (m != null) {
                        ctl.update(
                          (x) => x.copyWith(
                            quietHours: x.quietHours.copyWith(start: m),
                          ),
                        );
                      }
                    },
                    child: Text(tr('From {0}', [_fmtMinute(context, q.start)])),
                  ),
                ),
                const SizedBox(width: AriaTokens.s3),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final m = await _pickMinute(context, q.end);
                      if (m != null) {
                        ctl.update(
                          (x) => x.copyWith(
                            quietHours: x.quietHours.copyWith(end: m),
                          ),
                        );
                      }
                    },
                    child: Text(tr('Until {0}', [_fmtMinute(context, q.end)])),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Let urgent reminders through')),
              value: q.allowUrgent,
              onChanged: (v) => ctl.update(
                (x) => x.copyWith(
                  quietHours: x.quietHours.copyWith(allowUrgent: v),
                ),
              ),
            ),
          ],
          const SizedBox(height: AriaTokens.s4),
          Text(tr('Automatic switch to text'), style: text.titleMedium),
          Text(
            tr(
              'When voice would be awkward, Aria sends a text notification instead',
            ),
            style: text.bodySmall?.copyWith(color: muted),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.volume_off_rounded),
            title: Text(tr('Phone on silent or vibrate')),
            subtitle: Text(tr('Always on')),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bedtime_outlined),
            title: Text(tr('During quiet hours')),
            subtitle: Text(tr('Follows the quiet hours above')),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.event_busy_outlined),
            title: Text(tr('In a meeting (calendar busy)')),
            subtitle: Text(tr('Coming later')),
            value: false,
            onChanged: null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.directions_car_outlined),
            title: Text(tr('While driving')),
            subtitle: Text(tr('Needs motion access — coming later')),
            value: false,
            onChanged: null,
          ),
        ],
      ),
    );
  }
}

/// Settings › Routines & briefings (6.5) — briefing part.
class BriefingsSettingsScreen extends ConsumerWidget {
  const BriefingsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(voiceSettingsProvider).briefings;
    final ctl = ref.read(voiceSettingsProvider.notifier);
    void set(Briefings Function(Briefings) f) =>
        ctl.update((x) => x.copyWith(briefings: f(x.briefings)));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Routines & briefings'))),
      body: ListView(
        padding: const EdgeInsets.all(AriaTokens.s4),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('☀️ Morning briefing')),
            subtitle: Text(
              tr('Today’s plan, bills and birthdays at {0}', [
                _fmtMinute(context, b.morningAt),
              ]),
            ),
            value: b.morningEnabled,
            onChanged: (v) => set((x) => x.copyWith(morningEnabled: v)),
          ),
          if (b.morningEnabled)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  final m = await _pickMinute(context, b.morningAt);
                  if (m != null) set((x) => x.copyWith(morningAt: m));
                },
                child: Text(tr('Change time')),
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('🌙 Night wrap-up')),
            subtitle: Text(
              tr('Done vs pending, move the rest to tomorrow at {0}', [
                _fmtMinute(context, b.nightAt),
              ]),
            ),
            value: b.nightEnabled,
            onChanged: (v) => set((x) => x.copyWith(nightEnabled: v)),
          ),
          if (b.nightEnabled)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  final m = await _pickMinute(context, b.nightAt);
                  if (m != null) set((x) => x.copyWith(nightAt: m));
                },
                child: Text(tr('Change time')),
              ),
            ),
          const SizedBox(height: AriaTokens.s4),
          Text(
            tr(
              'Briefings use your default reminder mode (voice, text or both).',
            ),
            style: TextStyle(color: context.palette.muted),
          ),
        ],
      ),
    );
  }
}
