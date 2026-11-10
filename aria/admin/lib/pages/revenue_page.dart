import 'package:aria_admin/core/format.dart';
import 'package:aria_admin/pages/subscriptions_page.dart';
import 'package:aria_admin/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RevenuePage extends ConsumerWidget {
  const RevenuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PageFrame(
    title: 'Revenue',
    subtitle:
        'Gross amounts reported by the stores / Razorpay. RevenueCat remains the source of truth for net revenue '
        '(after store fees and GST). Payments are non-refundable.',
    children: [
      const SectionTitle('By month'),
      AsyncBody(
        value: ref.watch(reportProvider('revenue_monthly')),
        builder: (rows) {
          final byMonth = <String, num>{};
          for (final r in rows) {
            final m = '${r['month']}';
            byMonth[m] =
                (byMonth[m] ?? 0) + (num.tryParse('${r['gross_inr']}') ?? 0);
          }
          final months = byMonth.keys.toList()..sort();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (months.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Bars(
                      values: [for (final m in months) byMonth[m]!],
                      labels: [
                        for (final m in months) '$m: ${rupees(byMonth[m])}',
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              RowsTable(
                rows: rows,
                empty: 'No payments yet.',
                cols: [
                  Col('Month', (r) => '${r['month']}'),
                  Col('Plan', (r) => '${r['plan_code'] ?? '—'}'),
                  Col('Via', (r) => '${r['provider']}'),
                  Col('Payments', (r) => count(r['payments']), numeric: true),
                  Col('Gross', (r) => rupees(r['gross_inr']), numeric: true),
                ],
              ),
            ],
          );
        },
      ),
      const SectionTitle('Renewal rate'),
      AsyncBody(
        value: ref.watch(reportProvider('renewal_rate_monthly')),
        builder: (rows) => RowsTable(
          rows: rows,
          empty: 'No renewals or endings yet.',
          cols: [
            Col('Month', (r) => '${r['month']}'),
            Col('Renewed', (r) => count(r['renewed']), numeric: true),
            Col('Ended', (r) => count(r['ended']), numeric: true),
            Col(
              'Renewal %',
              (r) => r['renewal_rate_pct'] == null
                  ? '—'
                  : '${r['renewal_rate_pct']}%',
              numeric: true,
            ),
          ],
        ),
      ),
      const SectionTitle('Trial conversion'),
      AsyncBody(
        value: ref.watch(reportProvider('trial_conversion')),
        builder: (rows) => RowsTable(
          rows: rows,
          empty: 'No trials yet.',
          cols: [
            Col('Month', (r) => '${r['month']}'),
            Col('Trials', (r) => count(r['trials']), numeric: true),
            Col(
              'Paid within 30 days',
              (r) => count(r['converted']),
              numeric: true,
            ),
          ],
        ),
      ),
      const SectionTitle('Live subscriptions'),
      AsyncBody(
        value: ref.watch(reportProvider('subscriptions_overview')),
        builder: (rows) => RowsTable(
          rows: rows,
          cols: [
            Col('Plan', (r) => '${r['plan']}'),
            Col('Via', (r) => '${r['provider']}'),
            Col('Status', (r) => '${r['status']}'),
            Col('Circles', (r) => count(r['circles']), numeric: true),
          ],
        ),
      ),
    ],
  );
}
