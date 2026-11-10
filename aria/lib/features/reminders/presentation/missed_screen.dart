import 'dart:async';

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/state_views.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/data/reminder_repository.dart';
import 'package:aria/features/reminders/presentation/formatting.dart';
import 'package:aria/features/reminders/presentation/snooze_sheet.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Missed reminders with one-tap reschedule.
class MissedScreen extends ConsumerWidget {
  const MissedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missed = ref.watch(missedProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Missed reminders'))),
      body: missed.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(message: '$e'),
        data: (items) => items.isEmpty
            ? EmptyState(
                emoji: '🎉',
                title: tr('Nothing missed'),
                message: tr('You’re all caught up.'),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(AriaTokens.s4),
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AriaTokens.s2),
                itemBuilder: (_, i) => _MissedTile(item: items[i]),
              ),
      ),
    );
  }
}

class _MissedTile extends ConsumerWidget {
  const _MissedTile({required this.item});
  final MissedItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = item.reminder;
    final zone = ref.watch(deviceTimeZoneProvider);
    final service = ref.read(reminderServiceProvider);
    final now = service?.now() ?? DateTime.now();
    final when = item.event.occurrenceAt;
    final text = Theme.of(context).textTheme;

    return Dismissible(
      key: ValueKey(item.event.id),
      onDismissed: (_) => unawaited(service?.dismissMissed(item)),
      background: Container(
        color: context.palette.muted.withValues(alpha: 0.2),
      ),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AriaTokens.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => context.push('/reminder/${r.id}'),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        r.category.emoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                    const SizedBox(width: AriaTokens.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.title, style: text.titleMedium),
                          if (when != null)
                            Text(
                              tr('Missed · {0}', [
                                formatWhen(
                                  context,
                                  when,
                                  zone,
                                  now: now,
                                  allDay: r.allDay,
                                ),
                              ]),
                              style: text.bodySmall?.copyWith(
                                color: context.palette.danger,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AriaTokens.s2),
              Wrap(
                spacing: AriaTokens.s2,
                children: [
                  FilledButton.tonal(
                    onPressed: () => service?.rescheduleMissed(
                      item,
                      now.add(const Duration(hours: 1)),
                    ),
                    child: Text(tr('Remind in 1 h')),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final at = await showSnoozeSheet(context, ref);
                      if (at != null) await service?.rescheduleMissed(item, at);
                    },
                    child: Text(tr('Pick time')),
                  ),
                  TextButton(
                    onPressed: () => service?.dismissMissed(item),
                    child: Text(tr('Dismiss')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
