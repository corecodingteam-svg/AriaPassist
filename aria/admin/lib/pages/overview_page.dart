import 'package:aria_admin/core/format.dart';
import 'package:aria_admin/core/neon_theme.dart';
import 'package:aria_admin/core/providers.dart';
import 'package:aria_admin/data/admin_api.dart';
import 'package:aria_admin/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final overviewProvider = FutureProvider<Rec>(
  (ref) => ref.watch(adminApiProvider).overview(),
);
final activityProvider = FutureProvider<List<Rec>>(
  (ref) => ref.watch(adminApiProvider).report('activity_daily', limit: 30),
);

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(overviewProvider);
    final act = ref.watch(activityProvider);
    final warn = Theme.of(context).colorScheme.error;
    return PageFrame(
      title: 'Overview',
      subtitle: 'Live from the database. Revenue is gross (before store fees and GST).',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => ref
            ..invalidate(overviewProvider)
            ..invalidate(activityProvider),
          icon: const Icon(Icons.refresh),
        ),
      ],
      children: [
        AsyncBody(
          value: o,
          builder: (v) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              KpiCard(
                tile: Neon.tiles[0],
                label: 'Users',
                value: count(v['users']),
                hint: '+${count(v['signups_7d'])} this week',
              ),
              KpiCard(
                tile: Neon.tiles[1],
                label: 'Active (7 days)',
                value: count(v['active_7d']),
                hint: '${count(v['active_30d'])} in 30 days',
              ),
              KpiCard(
                tile: Neon.tiles[2],
                label: 'Paying Circles',
                value: count(v['paid_circles']),
                hint:
                    '${count(v['trials'])} on trial · ${count(v['granted'])} granted',
              ),
              KpiCard(
                tile: Neon.tiles[3],
                label: 'MRR (gross)',
                value: rupees(v['mrr_inr']),
                hint: 'monthly equivalent of paid plans',
              ),
              KpiCard(
                tile: Neon.tiles[4],
                label: 'Revenue this month',
                value: rupees(v['revenue_this_month_inr']),
              ),
              KpiCard(
                label: 'Ending in 7 days',
                value: count(v['expiring_7d']),
                hint: 'won’t renew by themselves + all',
              ),
              KpiCard(
                label: 'Lapsed (30 days)',
                value: count(v['lapsed_30d']),
                hint: 'win-back list',
              ),
              KpiCard(
                label: 'Payment problems',
                value: count(v['past_due']),
                tone: (num.tryParse('${v['past_due']}') ?? 0) > 0 ? warn : null,
              ),
              KpiCard(label: 'Suspended', value: count(v['suspended'])),
              KpiCard(
                label: 'Pending deletions',
                value: count(v['pending_deletions']),
              ),
              KpiCard(
                label: 'Reminders (7 days)',
                value: count(v['reminders_7d']),
              ),
            ],
          ),
        ),
        const SectionTitle('Last 30 days'),
        AsyncBody(
          value: act,
          builder: (rows) {
            final days = rows.reversed.toList();
            String lbl(Rec r) => date(r['day']);
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final (title, key) in [
                  ('Active users', 'active_users'),
                  ('Sign-ups', 'signups'),
                  ('Reminders created', 'reminders_created'),
                  ('Missed reminders', 'reminders_missed'),
                ])
                  SizedBox(
                    width: 420,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 12),
                            Bars(
                              values: [
                                for (final r in days)
                                  num.tryParse('${r[key]}') ?? 0,
                              ],
                              labels: [for (final r in days) lbl(r)],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
