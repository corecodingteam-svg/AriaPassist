import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/core/widgets/state_views.dart';
import 'package:aria/features/lists/organize_providers.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/alert_plan.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/presentation/formatting.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Bills this month: paid vs upcoming with totals (spec 5.6).
class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(billsSummaryProvider);
    final zone = ref.watch(deviceTimeZoneProvider);
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final text = Theme.of(context).textTheme;
    final p = context.palette;

    Widget row(Reminder r, {required bool paid}) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        paid ? Icons.check_circle_rounded : Icons.schedule_rounded,
        color: paid ? p.success : p.warning,
      ),
      title: Text(r.title),
      subtitle: Text(
        paid
            ? tr('Paid {0}', [
                formatWhen(context, r.lastDoneAt!, zone, now: now),
              ])
            : tr('Due {0}', [
                formatWhen(context, r.dueAt!, zone, now: now, allDay: r.allDay),
              ]),
      ),
      trailing: Text(
        r.amount == null ? '—' : formatRupees(r.amount!),
        style: text.titleMedium,
      ),
      onTap: () => context.push('/reminder/${r.id}'),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Bills · {0}', [DateFormat('MMMM').format(now.toLocal())]),
        ),
      ),
      body: b.paid.isEmpty && b.upcoming.isEmpty
          ? EmptyState(
              emoji: '💰',
              title: tr('No bills this month'),
              message: tr(
                'Say “pay electricity bill ₹1840 on the 5th of every month”.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(AriaTokens.s4),
              children: [
                AriaCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('To pay'),
                              style: TextStyle(color: p.muted),
                            ),
                            Text(
                              formatRupees(b.upcomingTotal),
                              style: text.headlineSmall,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('Paid'), style: TextStyle(color: p.muted)),
                            Text(
                              formatRupees(b.paidTotal),
                              style: text.headlineSmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (b.upcoming.isNotEmpty) ...[
                  const SizedBox(height: AriaTokens.s4),
                  Text(tr('Upcoming'), style: text.titleMedium),
                  for (final r in b.upcoming) row(r, paid: false),
                ],
                if (b.paid.isNotEmpty) ...[
                  const SizedBox(height: AriaTokens.s4),
                  Text(tr('Paid'), style: text.titleMedium),
                  for (final r in b.paid) row(r, paid: true),
                ],
              ],
            ),
    );
  }
}
