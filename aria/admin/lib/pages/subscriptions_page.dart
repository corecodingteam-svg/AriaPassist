import 'package:aria_admin/core/format.dart';
import 'package:aria_admin/core/providers.dart';
import 'package:aria_admin/data/admin_api.dart';
import 'package:aria_admin/widgets/common.dart';
import 'package:aria_admin/widgets/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ignore: specify_nonobvious_property_types -- family type is verbose
final reportProvider = FutureProvider.family<List<Rec>, String>(
  (ref, name) => ref.watch(adminApiProvider).report(name, limit: 500),
);

/// Grant (or extend) months on a Circle. Returns true when granted.
Future<bool> showGrantDialog(
  BuildContext context,
  WidgetRef ref, {
  required String circleId,
  required String circleType,
}) async {
  final plans = circleType == 'personal'
      ? const ['personal']
      : const ['family', 'team'];
  var plan = plans.first;
  var days = 30;
  final picked = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Grant plan time'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Free time on a plan. It never auto-renews and extends any time already granted.',
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: [
                for (final p in plans) ButtonSegment(value: p, label: Text(p)),
              ],
              selected: {plan},
              onSelectionChanged: (v) => set(() => plan = v.first),
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 days')),
                ButtonSegment(value: 30, label: Text('30 days')),
                ButtonSegment(value: 90, label: Text('90 days')),
                ButtonSegment(value: 365, label: Text('1 year')),
              ],
              selected: {days},
              onSelectionChanged: (v) => set(() => days = v.first),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Next'),
          ),
        ],
      ),
    ),
  );
  if (picked != true || !context.mounted) return false;
  final reason = await askReason(
    context,
    title: 'Grant $days days of $plan?',
    action: 'Grant',
  );
  if (reason == null || !context.mounted) return false;
  final ok = await runAction(
    context,
    () => ref.read(adminApiProvider).grantPlan(circleId, plan, days, reason),
    done: 'Granted $days days of $plan',
  );
  if (ok) {
    ref
      ..invalidate(reportProvider('expiring'))
      ..invalidate(reportProvider('circle_tenure'));
  }
  return ok;
}

class SubscriptionsPage extends ConsumerWidget {
  const SubscriptionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canAct = ref.watch(adminRoleProvider).value.canAct;
    void owner(Rec r) => context.go('/users/${r['owner_id']}');
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const Material(
            child: TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Ending soon'),
                Tab(text: 'Lapsed (win-back)'),
                Tab(text: 'All paid Circles'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                PageFrame(
                  title: 'Ending in the next 30 days',
                  subtitle: 'Plans that won’t renew by themselves get reminders at 7, 3 and 1 day(s) and on the day.',
                  children: [
                    AsyncBody(
                      value: ref.watch(reportProvider('expiring')),
                      builder: (rows) => RowsTable(
                        rows: rows,
                        onTap: owner,
                        empty: 'Nothing ending in the next 30 days.',
                        cols: [
                          Col('Circle', (r) => '${r['circle_name']}'),
                          Col('Plan', (r) => '${r['current_plan']}'),
                          Col('Paid until', (r) => date(r['paid_until'])),
                          Col(
                            'Days left',
                            (r) => '${r['days_left']}',
                            numeric: true,
                          ),
                          Col(
                            'Renews',
                            (r) => r['auto_renews'] == true ? 'auto' : 'no',
                          ),
                          Col('Via', (r) => '${r['provider'] ?? '—'}'),
                          Col(
                            'Total paid',
                            (r) => rupees(r['total_paid_inr']),
                            numeric: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                PageFrame(
                  title: 'Lapsed in the last 60 days',
                  subtitle: 'Ended and not renewed. They get win-back reminders 3 and 7 days after.',
                  children: [
                    AsyncBody(
                      value: ref.watch(reportProvider('lapsed')),
                      builder: (rows) => RowsTable(
                        rows: rows,
                        onTap: owner,
                        empty: 'No lapsed plans.',
                        cols: [
                          Col('Circle', (r) => '${r['circle_name']}'),
                          Col('Plan', (r) => '${r['lapsed_plan']}'),
                          Col(
                            'Ended',
                            (r) =>
                                '${date(r['ended_at'])} (${relative(r['ended_at'])})',
                          ),
                          Col(
                            'Total paid',
                            (r) => rupees(r['total_paid_inr']),
                            numeric: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                PageFrame(
                  title: 'Tenure',
                  subtitle: canAct
                      ? 'Tap a row to open the owner (grant time from there).'
                      : 'Tap a row to open the owner.',
                  children: [
                    AsyncBody(
                      value: ref.watch(reportProvider('circle_tenure')),
                      builder: (rows) => RowsTable(
                        rows: [
                          for (final r in rows)
                            if (r['current_plan'] != 'free' ||
                                r['payments'] != 0)
                              r,
                        ],
                        onTap: owner,
                        empty: 'No paid Circles yet.',
                        cols: [
                          Col('Circle', (r) => '${r['circle_name']}'),
                          Col('Type', (r) => '${r['type']}'),
                          Col('Plan', (r) => '${r['current_plan']}'),
                          Col('First paid', (r) => date(r['first_paid_at'])),
                          Col('Paid until', (r) => date(r['paid_until'])),
                          Col(
                            'Payments',
                            (r) => count(r['payments']),
                            numeric: true,
                          ),
                          Col(
                            'Renewals',
                            (r) => count(r['renewals']),
                            numeric: true,
                          ),
                          Col(
                            'Total paid',
                            (r) => rupees(r['total_paid_inr']),
                            numeric: true,
                          ),
                          Col(
                            'Members',
                            (r) => count(r['members']),
                            numeric: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
