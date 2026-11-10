import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/core/widgets/state_views.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/lists/organize_providers.dart';
import 'package:aria/features/people/domain/person.dart';
import 'package:aria/features/people/presentation/people_screens.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/describe.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/reminders/presentation/formatting.dart';
import 'package:aria/features/reminders/presentation/reminder_actions.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ReminderDetailScreen extends ConsumerWidget {
  const ReminderDetailScreen({required this.reminderId, super.key});
  final String reminderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reminderByIdProvider(reminderId));
    return async.when(
      loading: () => const Scaffold(body: LoadingState()),
      error: (e, _) => Scaffold(body: ErrorState(message: '$e')),
      data: (r) {
        if (r == null || r.deletedAt != null) {
          return Scaffold(
            appBar: AppBar(),
            body: EmptyState(
              emoji: '🗑️',
              title: tr('This reminder is gone'),
              message: tr('It may have been deleted on another device.'),
            ),
          );
        }
        return _Detail(r: r);
      },
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.r});
  final Reminder r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zone = ref.watch(deviceTimeZoneProvider);
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final actions = ReminderActions(context, ref);
    final rule = r.rule;
    final me = ref.watch(currentUserIdProvider);
    final names = ref.watch(memberNamesProvider).value ?? const {};
    String who(String id) => id == me ? 'You' : names[id] ?? tr('Someone');

    final rows = <(IconData, String, String)>[
      if (r.dueAt != null)
        (
          Icons.schedule_rounded,
          r.snoozedUntil != null ? tr('Snoozed until') : tr('When'),
          formatWhen(
            context,
            r.dueAt!,
            zone,
            now: now,
            allDay: r.allDay && r.snoozedUntil == null,
          ),
        ),
      if (r.location != null)
        (Icons.place_outlined, tr('Where'), r.location!.describe()),
      if (rule != null && r.startAt != null)
        (
          Icons.repeat_rounded,
          tr('Repeats'),
          describeRule(rule, toWall(r.startAt!, r.timezone ?? zone)),
        ),
      (
        Icons.label_outline_rounded,
        tr('Category'),
        '${r.category.emoji} ${r.category.label}',
      ),
      (Icons.flag_outlined, tr('Priority'), r.priority.label),
      if (r.createdBy != me)
        (Icons.person_outline_rounded, tr('From'), who(r.createdBy)),
      if (r.assignedTo != null && r.assignedTo != me)
        (Icons.person_outline_rounded, tr('For'), who(r.assignedTo!)),
      if (r.visibility == 'shared')
        (Icons.group_outlined, tr('Shared'), tr('With your Circle')),
      if (r.amount != null)
        (Icons.currency_rupee_rounded, tr('Amount'), rupees.format(r.amount)),
      (
        Icons.notifications_active_outlined,
        'Follow-up',
        r.followUp.enabled
            ? tr('Every {0} min, up to {1}×', [
                r.followUp.everyMin,
                r.followUp.maxAttempts,
              ])
            : tr('Off'),
      ),
      if (r.lastDoneAt != null)
        (
          Icons.check_circle_outline_rounded,
          tr('Last done'),
          formatWhen(context, r.lastDoneAt!, zone, now: now),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: tr('Edit'),
            onPressed: () => context.push('/reminder/${r.id}/edit'),
            icon: const Icon(Icons.edit_rounded),
          ),
          IconButton(
            tooltip: tr('Delete'),
            onPressed: () async {
              await actions.delete(r);
              if (context.mounted) context.pop();
            },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AriaTokens.s4),
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Text(
                  r.category.emoji,
                  style: const TextStyle(fontSize: 40),
                ),
              ),
              const SizedBox(width: AriaTokens.s3),
              Expanded(child: Text(r.title, style: text.headlineSmall)),
            ],
          ),
          if (r.status != ReminderStatus.active)
            Padding(
              padding: const EdgeInsets.only(top: AriaTokens.s2),
              child: Chip(
                label: Text(switch (r.status) {
                  ReminderStatus.done => tr('✓ Done'),
                  ReminderStatus.missed => tr('Missed'),
                  _ => tr('Archived'),
                }),
              ),
            ),
          const SizedBox(height: AriaTokens.s4),
          AriaCard(
            padding: const EdgeInsets.symmetric(vertical: AriaTokens.s2),
            child: Column(
              children: [
                for (final (icon, label, value) in rows)
                  ListTile(
                    leading: Icon(icon, color: p.primary),
                    title: Text(label, style: TextStyle(color: p.muted)),
                    subtitle: Text(value, style: text.titleMedium),
                  ),
              ],
            ),
          ),
          if (r.personId != null)
            Builder(
              builder: (context) {
                final person =
                    (ref.watch(peopleProvider).value ?? const <Person>[])
                        .where((p) => p.id == r.personId)
                        .firstOrNull;
                if (person == null) return const SizedBox.shrink();
                final occasion = r.contact?['occasion'] as String?;
                return Padding(
                  padding: const EdgeInsets.only(top: AriaTokens.s3),
                  child: ContactActions(
                    person: person,
                    wish: occasion == null
                        ? null
                        : person.wish(birthday: occasion == 'birthday'),
                  ),
                );
              },
            ),
          if (r.notes != null) ...[
            const SizedBox(height: AriaTokens.s3),
            AriaCard(child: Text(r.notes!, style: text.bodyLarge)),
          ],
          const SizedBox(height: AriaTokens.s5),
          if (r.isActive) ...[
            FilledButton.icon(
              onPressed: () async {
                await actions.complete(r);
                if (context.mounted && !r.isRecurring) context.pop();
              },
              icon: const Icon(Icons.check_rounded),
              label: Text(tr('Mark done')),
            ),
            const SizedBox(height: AriaTokens.s2),
            OutlinedButton.icon(
              onPressed: () => actions.pickSnooze(r),
              icon: const Icon(Icons.snooze_rounded),
              label: Text(tr('Snooze')),
            ),
          ] else
            OutlinedButton.icon(
              onPressed: () => context.push('/reminder/${r.id}/edit'),
              icon: const Icon(Icons.replay_rounded),
              label: Text(tr('Remind me again')),
            ),
        ],
      ),
    );
  }
}
