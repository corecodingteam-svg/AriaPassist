import 'dart:async';

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/core/widgets/prompts.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/circles/domain/circle.dart';
import 'package:aria/features/help/presentation/help_screens.dart';
import 'package:aria/features/subscription/application/billing_actions.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// Key benefits shown on each plan card (4–5 lines, spec 8.2).
List<String> benefitsFor(Plan p) => switch (p.code) {
  'free' => [
    tr('Unlimited basic reminders'),
    tr('2 voices · 3 themes'),
    tr('Morning briefing'),
    tr('2 lists'),
  ],
  'personal' => [
    tr('All voices & personalities'),
    tr('All themes + custom colour'),
    tr('Routines & weekly report'),
    tr('Unlimited lists & notes'),
  ],
  'family' => [
    tr('Everything in Personal, for up to {0}', [p.maxSeats]),
    tr('Shared Circle & lists'),
    tr('Remind Mum & Dad from your phone'),
    tr('Simple Mode lock for elders & kids'),
  ],
  'team' => [
    tr('Everything in Family, up to {0}', [p.maxSeats]),
    tr('Activity log'),
    tr('Work categories'),
    tr('Priority support'),
  ],
  _ => const [],
};

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  BillingPeriod _period = BillingPeriod.month;

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(plansProvider);
    final ent = ref.watch(entitlementProvider);
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    // Smallest saving across paid plans, so the claim holds for every one.
    final savings = plans.map((x) => x.yearlySavingPercent).where((s) => s > 0);
    final saving = savings.isEmpty
        ? 0
        : savings.reduce((a, b) => a < b ? a : b);
    final wide = MediaQuery.sizeOf(context).width >= 600;

    final cards = [
      for (final plan in plans)
        _PlanCard(
          plan: plan,
          period: _period,
          current: ent.plan.code == plan.code,
          mine: ent.plan,
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(tr('Subscription & plans'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AriaTokens.s4,
          AriaTokens.s2,
          AriaTokens.s4,
          80,
        ),
        children: [
          const _CurrentPlan(),
          const SizedBox(height: AriaTokens.s4),
          Text(tr('Choose what fits you'), style: text.headlineSmall),
          const SizedBox(height: AriaTokens.s3),
          SegmentedButton<BillingPeriod>(
            key: const Key('period'),
            segments: [
              ButtonSegment(
                value: BillingPeriod.month,
                label: Text(tr('Monthly')),
              ),
              ButtonSegment(
                value: BillingPeriod.year,
                label: Text(
                  saving > 0
                      ? tr('Yearly · save {0}%', [saving])
                      : tr('Yearly'),
                ),
              ),
            ],
            selected: {_period},
            onSelectionChanged: (s) => setState(() => _period = s.first),
          ),
          if (_period == BillingPeriod.year)
            Padding(
              padding: const EdgeInsets.only(top: AriaTokens.s2),
              child: Text(
                tr('About 2 months free'),
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted),
              ),
            ),
          const SizedBox(height: AriaTokens.s3),
          if (wide)
            ...cards
          else
            // Horizontal swipe on phones; cards size to their content so
            // large text never clips.
            LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth * 0.86;
                return SingleChildScrollView(
                  key: const Key('plan-pager'),
                  scrollDirection: Axis.horizontal,
                  controller: ScrollController(
                    initialScrollOffset:
                        _initialPage(plans, ent.plan) * (w + AriaTokens.s2),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final c in cards)
                          Padding(
                            padding: const EdgeInsets.only(
                              right: AriaTokens.s2,
                            ),
                            child: SizedBox(width: w, child: c),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: AriaTokens.s3),
          _Comparison(plans: plans),
          const SizedBox(height: AriaTokens.s3),
          Text(
            tr('Cancel anytime · Secure payment · UPI, cards, Play/App Store'),
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted),
          ),
          const SizedBox(height: AriaTokens.s1),
          Text(
            tr(
              'Payments are non-refundable. Purchases through Google Play or the App Store follow their refund policies.',
            ),
            key: const Key('no-refunds'),
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 12),
          ),
          const SizedBox(height: AriaTokens.s4),
          Text(tr('Questions'), style: text.titleMedium),
          ..._faq.map(
            (q) => ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(q.$1),
              childrenPadding: const EdgeInsets.only(bottom: AriaTokens.s3),
              children: [
                Align(alignment: Alignment.centerLeft, child: Text(q.$2)),
              ],
            ),
          ),
          const SizedBox(height: AriaTokens.s3),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AriaTokens.s1,
            children: [
              TextButton(
                key: const Key('restore'),
                onPressed: () => BillingActions(context, ref).restore(),
                child: Text(tr('Restore purchases')),
              ),
              TextButton(
                key: const Key('promo'),
                onPressed: _promo,
                child: Text(tr('Have a code?')),
              ),
              TextButton(
                onPressed: () => launchUrl(Uri.parse(kTermsUrl)),
                child: Text(tr('Terms')),
              ),
              TextButton(
                onPressed: () => launchUrl(Uri.parse(kPrivacyPolicyUrl)),
                child: Text(tr('Privacy')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _initialPage(List<Plan> plans, Plan mine) {
    // Show the next step up (Family for most people).
    final popular = plans.indexWhere((p) => p.mostPopular);
    final current = plans.indexWhere((p) => p.code == mine.code);
    if (mine.isFree) return popular < 0 ? 0 : popular;
    return current < 0 ? 0 : current;
  }

  Future<void> _promo() async {
    final code = await promptText(
      context,
      title: tr('Promo or student code'),
      hint: tr('e.g. STUDENT30'),
      action: tr('Apply'),
    );
    if (code == null || code.isEmpty || !mounted) return;
    final me = ref.read(currentUserIdProvider);
    final circles = ref.read(myCirclesProvider).value ?? const <Circle>[];
    final active = ref.read(activeCircleProvider);
    // A code applies to the active Circle if I own it, else my personal one.
    final circle = active != null && active.ownerId == me
        ? active
        : circles.where((c) => c.isPersonal && c.ownerId == me).firstOrNull;
    if (circle == null) return;
    await BillingActions(context, ref).redeem(code, circle);
  }
}

List<(String, String)> get _faq => [
  (
    tr('Can I cancel anytime?'),
    tr(
      'Yes. Cancel in Play Store or App Store subscriptions. You keep premium until the end of the period you paid for; payments are non-refundable.',
    ),
  ),
  (
    tr('What happens when my plan ends?'),
    tr(
      'Nothing is deleted. Your reminders, lists and notes stay. Premium extras like extra voices switch back to the free ones.',
    ),
  ),
  (
    tr('Who pays on a Family plan?'),
    tr(
      'Only the Circle’s owner. Everyone in the Circle gets premium — up to 5 people for one price.',
    ),
  ),
  (
    tr('How does the free trial work?'),
    tr(
      'Try any paid plan free for 7 days, once per Circle. No payment needed to start; it simply ends if you don’t subscribe.',
    ),
  ),
];

/// Plan, status, renewal, seats, manage — for the Circle granting my plan.
class _CurrentPlan extends ConsumerWidget {
  const _CurrentPlan();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ent = ref.watch(entitlementProvider);
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    if (!ent.isPremium || ent.circleId == null) {
      return AriaCard(
        child: Row(
          children: [
            const Text('🙂', style: TextStyle(fontSize: 28)),
            const SizedBox(width: AriaTokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('You’re on Free'),
                    key: const Key('current-plan'),
                    style: text.titleMedium,
                  ),
                  Text(
                    tr('Reminders are free forever.'),
                    style: TextStyle(color: p.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final circle = (ref.watch(myCirclesProvider).value ?? const <Circle>[])
        .where((c) => c.id == ent.circleId)
        .firstOrNull;
    final b = ref.watch(circleBillingProvider(ent.circleId!)).value;
    final owner = circle?.myRole == CircleRole.owner;
    final date = b?.endsAt == null
        ? null
        : MaterialLocalizations.of(context)
              .formatMediumDate(b!.endsAt!.toLocal());
    final status = switch (b) {
      null => null,
      final b when b.trialing => tr('Free trial · ends {0}', [date]),
      final b when b.status == 'past_due' => tr(
        'Payment problem — update your payment method',
      ),
      final b when b.ending => tr('Ends {0} · won’t renew', [date]),
      _ when date != null => tr('Renews {0}', [date]),
      _ => null,
    };
    return AriaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AriaTokens.s3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                label: Text(
                  '⭐ ${ent.plan.name}',
                  key: const Key('current-plan'),
                ),
              ),
              if (b != null && b.maxSeats > 1)
                Text(
                  tr('{0} of {1} people', [b.seatsUsed, b.maxSeats]),
                  style: TextStyle(color: p.muted),
                ),
            ],
          ),
          if (status != null)
            Text(
              status,
              key: const Key('plan-status'),
              style: TextStyle(
                color: b?.status == 'past_due' ? p.danger : null,
              ),
            ),
          if (!owner && circle != null)
            Padding(
              padding: const EdgeInsets.only(top: AriaTokens.s1),
              child: Text(
                tr('Included with {0} — the owner manages billing.', [
                  circle.name,
                ]),
                style: TextStyle(color: p.muted),
              ),
            ),
          if (owner && b != null) ...[
            const SizedBox(height: AriaTokens.s2),
            Wrap(
              spacing: AriaTokens.s2,
              children: [
                OutlinedButton(
                  onPressed: () => BillingActions(context, ref).manage(b),
                  child: Text(
                    b.provider == 'manual'
                        ? tr('About this plan')
                        : tr('Manage or cancel'),
                  ),
                ),
                TextButton(
                  key: const Key('billing-history'),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (_) => _History(circleId: ent.circleId!),
                  ),
                  child: Text(tr('Billing history')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _History extends ConsumerWidget {
  const _History({required this.circleId});
  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider);
    final rows =
        ref.watch(billingHistoryProvider(circleId)).value ??
        const <BillingRecord>[];
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(
        AriaTokens.s4,
        0,
        AriaTokens.s4,
        AriaTokens.s5,
      ),
      children: [
        Text(
          tr('Billing history'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AriaTokens.s4),
            child: Text(tr('Nothing yet')),
          ),
        for (final r in rows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              r.describe(planNamed(plans, r.planCode ?? 'free').name),
            ),
            subtitle: Text(
              MaterialLocalizations.of(context)
                  .formatMediumDate(r.at.toLocal()),
            ),
            trailing: r.amountInr == null || r.amountInr == 0
                ? null
                : Text(rupeesWhole(r.amountInr!)),
          ),
      ],
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({
    required this.plan,
    required this.period,
    required this.current,
    required this.mine,
  });
  final Plan plan;
  final BillingPeriod period;
  final bool current;
  final Plan mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final price = plan.price(period);
    final perPerson = plan.perPersonMonthly(period);
    final trial = ref.watch(trialAvailableProvider(plan.code)).value ?? false;
    final included = !current && plan.sort < mine.sort;

    final Widget cta;
    if (plan.isFree) {
      cta = OutlinedButton(
        onPressed: null,
        child: Text(current ? tr('Current plan') : tr('Free forever')),
      );
    } else if (current || included) {
      cta = OutlinedButton(
        onPressed: null,
        child: Text(current ? tr('Current plan') : tr('Included in your plan')),
      );
    } else if (trial) {
      cta = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            key: Key('trial-${plan.code}'),
            onPressed: () => BillingActions(context, ref).startTrial(plan),
            child: Text(tr('Start {0}-day free trial', [plan.trialDays])),
          ),
          TextButton(
            key: Key('buy-${plan.code}'),
            onPressed: () =>
                BillingActions(context, ref).subscribe(plan, period),
            child: Text(tr('Subscribe now')),
          ),
        ],
      );
    } else {
      cta = FilledButton(
        key: Key('buy-${plan.code}'),
        onPressed: () => BillingActions(context, ref).subscribe(plan, period),
        child: Text(tr('Get {0}', [plan.name])),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AriaTokens.s3),
      child: Card(
        key: Key('plan-${plan.code}'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AriaTokens.radiusLg),
          side: BorderSide(
            color: plan.mostPopular || current ? p.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AriaTokens.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Wraps at large text sizes instead of overflowing.
              Wrap(
                spacing: AriaTokens.s2,
                runSpacing: AriaTokens.s1,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(plan.name, style: text.titleLarge),
                  if (current)
                    _Badge(tr('Current plan'), p.primary)
                  else if (plan.mostPopular)
                    _Badge(tr('⭐ Most popular'), p.secondary),
                ],
              ),
              const SizedBox(height: AriaTokens.s2),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: price == 0 ? '₹0' : rupeesWhole(price),
                      style: text.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (price > 0)
                      TextSpan(
                        text: period == BillingPeriod.month
                            ? tr(' /month')
                            : tr(' /year'),
                      ),
                  ],
                ),
              ),
              if (perPerson != null)
                Text(
                  tr('just {0}/person/month', [rupeesWhole(perPerson)]),
                  style: TextStyle(color: p.primary),
                ),
              if (plan.maxSeats > 1)
                Text(
                  tr('Up to {0} people', [plan.maxSeats]),
                  style: TextStyle(color: p.muted),
                ),
              const SizedBox(height: AriaTokens.s3),
              for (final b in benefitsFor(plan))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_rounded, size: 18, color: p.primary),
                      const SizedBox(width: AriaTokens.s2),
                      Expanded(child: Text(b)),
                    ],
                  ),
                ),
              const Spacer(),
              const SizedBox(height: AriaTokens.s3),
              cta,
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
    ),
  );
}

/// ✓ / ✗ / limits table (expandable).
class _Comparison extends StatelessWidget {
  const _Comparison({required this.plans});
  final List<Plan> plans;

  @override
  Widget build(BuildContext context) {
    String cell(Plan p, Feature f) => switch (f) {
      Feature.unlimitedLists => p.maxLists == null ? '✓' : '${p.maxLists}',
      Feature.premiumVoices => p.has(f) ? '✓' : '2',
      Feature.allThemes => p.has(f) ? '✓' : '3',
      _ => p.has(f) ? '✓' : '✗',
    };
    return ExpansionTile(
      key: const Key('compare'),
      tilePadding: EdgeInsets.zero,
      title: Text(tr('Compare plans')),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: AriaTokens.s4,
            columns: [
              const DataColumn(label: Text('')),
              for (final p in plans) DataColumn(label: Text(p.name)),
            ],
            rows: [
              DataRow(
                cells: [
                  DataCell(Text(tr('People'))),
                  for (final p in plans) DataCell(Text('${p.maxSeats}')),
                ],
              ),
              for (final f in Feature.values)
                DataRow(
                  cells: [
                    DataCell(Text('${f.emoji} ${f.title}')),
                    for (final p in plans) DataCell(Text(cell(p, f))),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Contextual paywall: the feature you tapped + the plan that unlocks it.
/// Always dismissible; never blocks free reminders.
class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({required this.feature, super.key});
  final Feature feature;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider);
    final ent = ref.watch(entitlementProvider);
    final plan = PlanCatalog.cheapestWith(plans, feature);
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final trial = ref.watch(trialAvailableProvider(plan.code)).value ?? false;

    // Unlocked meanwhile (trial started, purchase synced) → get out of the way.
    if (ent.can(feature)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && context.canPop()) context.pop();
      });
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: tr('Close'),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/today'),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AriaTokens.s5),
        children: [
          Text(
            feature.emoji,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 64),
          ),
          Text(
            feature.title,
            key: const Key('paywall-title'),
            textAlign: TextAlign.center,
            style: text.headlineSmall,
          ),
          const SizedBox(height: AriaTokens.s2),
          Text(
            feature.blurb,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted),
          ),
          const SizedBox(height: AriaTokens.s5),
          AriaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('Included in {0}', [plan.name]),
                  style: text.titleMedium,
                ),
                Text(
                  tr('{0}/month{1}', [
                    rupeesWhole(plan.priceMonth),
                    plan.perPersonMonthly(BillingPeriod.month) == null
                        ? ''
                        : tr(' · just {0}/person', [
                            rupeesWhole(
                              plan.perPersonMonthly(BillingPeriod.month)!,
                            ),
                          ]),
                  ]),
                  style: TextStyle(color: p.muted),
                ),
                const SizedBox(height: AriaTokens.s2),
                for (final b in benefitsFor(plan)) Text('✓  $b'),
                const SizedBox(height: AriaTokens.s3),
                if (trial)
                  FilledButton(
                    key: const Key('paywall-trial'),
                    onPressed: () =>
                        BillingActions(context, ref).startTrial(plan),
                    child: Text(
                      tr('Try {0} free for {1} days', [
                        plan.name,
                        plan.trialDays,
                      ]),
                    ),
                  )
                else
                  FilledButton(
                    key: const Key('paywall-buy'),
                    onPressed: () => BillingActions(
                      context,
                      ref,
                    ).subscribe(plan, BillingPeriod.month),
                    child: Text(tr('Get {0}', [plan.name])),
                  ),
              ],
            ),
          ),
          TextButton(
            key: const Key('see-plans'),
            onPressed: () => context.pushReplacement('/subscription'),
            child: Text(tr('See all plans')),
          ),
          TextButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/today'),
            child: Text(tr('Not now')),
          ),
        ],
      ),
    );
  }
}
