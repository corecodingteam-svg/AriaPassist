import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/features/lists/organize_providers.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Weekly report card (spec 5.9): on-time %, bills on time, longest streak,
/// and a 7-day bar of things done. Hidden when celebrations are off.
class WeeklyReportCard extends ConsumerWidget {
  const WeeklyReportCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(appPrefsProvider.select((p) => p.celebrations))) {
      return const SizedBox.shrink();
    }
    if (!ref.watch(entitlementProvider).can(Feature.weeklyReport)) {
      return AriaCard(
        key: const Key('weekly-report-locked'),
        onTap: () => requireFeature(context, ref, Feature.weeklyReport),
        child: Row(
          children: [
            const Text('📊', style: TextStyle(fontSize: 28)),
            const SizedBox(width: AriaTokens.s3),
            Expanded(
              child: Text(
                tr(
                  'Your weekly report — on-time %, streaks and bills — comes with Personal. Tap to see plans.',
                ),
              ),
            ),
            const Icon(Icons.lock_outline_rounded),
          ],
        ),
      );
    }
    final r = ref.watch(weeklyReportProvider);
    if (r == null) return const SizedBox.shrink();
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final maxDay = r.perDay.fold<int>(1, (m, v) => v > m ? v : m);
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final today = DateTime.now().weekday;

    Widget stat(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: text.headlineSmall?.copyWith(
              color: p.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted),
          ),
        ],
      ),
    );

    return AriaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('This week'), style: text.titleMedium),
          const SizedBox(height: AriaTokens.s3),
          Row(
            children: [
              stat(
                r.onTimePercent == null ? '—' : '${r.onTimePercent}%',
                tr('on time'),
              ),
              stat('${r.done}', 'done'),
              stat(
                r.billsPaid == 0 ? '—' : '${r.billsOnTime}/${r.billsPaid}',
                tr('bills on time'),
              ),
            ],
          ),
          if (r.longestStreak > 1) ...[
            const SizedBox(height: AriaTokens.s3),
            Text(
              tr('🔥 {0}-day streak: {1}', [
                r.longestStreak,
                r.longestStreakTitle,
              ]),
              key: const Key('streak-line'),
            ),
          ],
          const SizedBox(height: AriaTokens.s3),
          Semantics(
            label: tr('Done per day this week: {0}', [r.perDay.join(', ')]),
            excludeSemantics: true,
            child: SizedBox(
              height: 64,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Column(
                        children: [
                          // Bars take whatever height the labels leave, so
                          // large text never overflows.
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor:
                                    0.08 + 0.92 * r.perDay[i] / maxDay,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: i == 6
                                        ? p.primary
                                        : p.primary.withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            days[(today - 7 + i) % 7],
                            style: TextStyle(color: p.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
