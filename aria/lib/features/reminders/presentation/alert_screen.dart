import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/state_views.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/presentation/formatting.dart';
import 'package:aria/features/reminders/presentation/reminder_actions.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Full-screen alert (urgent reminders / tapping a notification).
class AlertScreen extends ConsumerWidget {
  const AlertScreen({required this.reminderId, super.key});
  final String reminderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(reminderByIdProvider(reminderId)).value;
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    if (r == null) return const Scaffold(body: LoadingState());
    final zone = ref.watch(deviceTimeZoneProvider);
    final actions = ReminderActions(context, ref);
    void close() => context.canPop() ? context.pop() : context.go('/today');

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: t.primaryGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AriaTokens.s5),
            child: Column(
              children: [
                const Spacer(),
                ExcludeSemantics(
                  child: Text(
                    r.category.emoji,
                    style: const TextStyle(fontSize: 72),
                  ),
                ),
                const SizedBox(height: AriaTokens.s4),
                Text(
                  r.title,
                  textAlign: TextAlign.center,
                  style: text.headlineMedium?.copyWith(
                    color: t.palette.onPrimary,
                  ),
                ),
                if (r.dueAt != null)
                  Text(
                    formatTime(context, r.dueAt!, zone),
                    style: text.titleLarge?.copyWith(
                      color: t.palette.onPrimary,
                    ),
                  ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: t.palette.surface,
                      foregroundColor: t.palette.text,
                      minimumSize: const Size.fromHeight(64),
                    ),
                    onPressed: () async {
                      await actions.complete(r);
                      close();
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: Text(tr('Done')),
                  ),
                ),
                const SizedBox(height: AriaTokens.s3),
                Row(
                  children: [
                    for (final (label, d) in [
                      (tr('15 min'), const Duration(minutes: 15)),
                      (tr('1 hour'), const Duration(hours: 1)),
                    ]) ...[
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: t.palette.onPrimary,
                            side: BorderSide(color: t.palette.onPrimary),
                          ),
                          onPressed: () async {
                            final now = ref.read(clockProvider)().toUtc();
                            await actions.snoozeTo(r, now.add(d));
                            close();
                          },
                          child: Text(tr('Snooze {0}', [label])),
                        ),
                      ),
                      if (label == '15 min')
                        const SizedBox(width: AriaTokens.s3),
                    ],
                  ],
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: t.palette.onPrimary,
                  ),
                  onPressed: () => context.go('/reminder/${r.id}'),
                  child: Text(tr('Open details')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
