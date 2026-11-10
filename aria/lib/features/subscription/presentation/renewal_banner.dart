import 'dart:async';

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/circles/domain/circle.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/subscription/application/billing_actions.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

enum RenewalKind { ending, ended, paymentIssue, memberInfo }

@immutable
class RenewalBannerInfo {
  const RenewalBannerInfo({
    required this.kind,
    required this.circleId,
    required this.planName,
    required this.at,
    required this.key,
    this.daysLeft = 0,
    this.circleName,
  });
  final RenewalKind kind;
  final String circleId;
  final String planName;
  final DateTime at;
  final int daysLeft;
  final String? circleName;

  /// Dismissal key; changes at each step so the banner comes back.
  final String key;
}

/// The most urgent renewal message for this user, or null. Pure.
RenewalBannerInfo? renewalBannerFor({
  required List<Circle> circles,
  required Map<String, CircleBilling> billing,
  required String? me,
  required String? grantingCircleId,
  required List<Plan> plans,
  required DateTime now,
  required Set<String> dismissed,
}) {
  final found = <RenewalBannerInfo>[];
  String name(String code) => planNamed(plans, code).name;
  String day(DateTime d) => '${d.year}${d.month}${d.day}';
  for (final c in circles) {
    final b = billing[c.id];
    if (b == null) continue;
    final owner = c.ownerId == me;
    final ends = b.endsAt;
    if (owner && b.planCode != 'free' && ends != null) {
      if (b.paymentIssue) {
        found.add(
          RenewalBannerInfo(
            kind: RenewalKind.paymentIssue,
            circleId: c.id,
            planName: name(b.planCode),
            at: ends,
            key: 'renew:${c.id}:${day(ends)}:pay',
          ),
        );
        continue;
      }
      final left = ends.difference(now);
      if (b.ending && !left.isNegative && left <= const Duration(days: 7)) {
        final days = (left.inHours / 24).ceil();
        final bucket = days <= 1
            ? 1
            : days <= 3
            ? 3
            : 7;
        found.add(
          RenewalBannerInfo(
            kind: RenewalKind.ending,
            circleId: c.id,
            planName: name(b.planCode),
            at: ends,
            daysLeft: days,
            key: 'renew:${c.id}:${day(ends)}:$bucket',
          ),
        );
      }
    } else if (owner &&
        b.planCode == 'free' &&
        b.lapsedPlanCode != null &&
        b.lapsedAt != null &&
        now.difference(b.lapsedAt!) <= const Duration(days: 14)) {
      found.add(
        RenewalBannerInfo(
          kind: RenewalKind.ended,
          circleId: c.id,
          planName: name(b.lapsedPlanCode!),
          at: b.lapsedAt!,
          key: 'renew:${c.id}:${day(b.lapsedAt!)}:ended',
        ),
      );
    } else if (!owner && c.id == grantingCircleId && ends != null && b.ending) {
      final left = ends.difference(now);
      if (!left.isNegative && left <= const Duration(days: 3)) {
        found.add(
          RenewalBannerInfo(
            kind: RenewalKind.memberInfo,
            circleId: c.id,
            planName: name(b.planCode),
            at: ends,
            daysLeft: (left.inHours / 24).ceil(),
            circleName: c.name,
            key: 'renew:${c.id}:${day(ends)}:member',
          ),
        );
      }
    }
  }
  final open = found.where((f) => !dismissed.contains(f.key)).toList()
    ..sort(
      (a, b) => a.kind.index == b.kind.index
          ? a.at.compareTo(b.at)
          : _rank(a.kind).compareTo(_rank(b.kind)),
    );
  return open.firstOrNull;
}

int _rank(RenewalKind k) => switch (k) {
  RenewalKind.paymentIssue => 0,
  RenewalKind.ending => 1,
  RenewalKind.ended => 2,
  RenewalKind.memberInfo => 3,
};

final renewalBannerProvider = Provider<RenewalBannerInfo?>((ref) {
  final circles = ref.watch(myCirclesProvider).value ?? const <Circle>[];
  final billing = <String, CircleBilling>{
    for (final c in circles)
      c.id: ?ref.watch(circleBillingProvider(c.id)).value,
  };
  return renewalBannerFor(
    circles: circles,
    billing: billing,
    me: ref.watch(currentUserIdProvider),
    grantingCircleId: ref.watch(entitlementProvider).circleId,
    plans: ref.watch(plansProvider),
    now: ref.watch(nowProvider).value ?? ref.read(clockProvider)(),
    dismissed: ref.watch(appPrefsProvider.select((p) => p.dismissedTips)),
  );
});

/// On Today and Me. Owners get Renew; members an info note.
class RenewalBanner extends ConsumerWidget {
  const RenewalBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(renewalBannerProvider);
    if (info == null) return const SizedBox.shrink();
    final p = context.palette;
    final date = DateFormat('d MMM').format(info.at.toLocal());
    final text = switch (info.kind) {
      RenewalKind.paymentIssue => tr(
        'We couldn’t renew your {0} plan. Update your payment method to keep it.',
        [info.planName],
      ),
      RenewalKind.ending when info.daysLeft <= 0 => tr(
        'Your {0} plan ends today.',
        [info.planName],
      ),
      RenewalKind.ending when info.daysLeft == 1 => tr(
        'Your {0} plan ends tomorrow.',
        [info.planName],
      ),
      RenewalKind.ending => tr('Your {0} plan ends in {1} days ({2}).', [
        info.planName,
        info.daysLeft,
        date,
      ]),
      RenewalKind.ended => tr(
        'Your {0} plan ended on {1}. Your reminders are safe.',
        [info.planName, date],
      ),
      RenewalKind.memberInfo => tr(
        'The {0} plan for {1} ends in {2} days. The owner can renew it.',
        [info.planName, info.circleName ?? '', info.daysLeft],
      ),
    };
    void dismiss() => ref
        .read(appPrefsProvider.notifier)
        .update(
          (x) => x.copyWith(dismissedTips: {...x.dismissedTips, info.key}),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: AriaTokens.s3),
      child: AriaCard(
        key: const Key('renewal-banner'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  info.kind == RenewalKind.paymentIssue
                      ? Icons.credit_card_off_rounded
                      : Icons.workspace_premium_rounded,
                  color: info.kind == RenewalKind.paymentIssue
                      ? p.danger
                      : p.primary,
                ),
                const SizedBox(width: AriaTokens.s2),
                Expanded(child: Text(text)),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AriaTokens.s2,
              children: [
                TextButton(onPressed: dismiss, child: Text(tr('Not now'))),
                if (info.kind == RenewalKind.paymentIssue)
                  FilledButton.tonal(
                    key: const Key('renewal-fix-payment'),
                    onPressed: () async {
                      final b = await ref.read(
                        circleBillingProvider(info.circleId).future,
                      );
                      if (b != null && context.mounted) {
                        unawaited(BillingActions(context, ref).manage(b));
                      }
                    },
                    child: Text(tr('Update payment')),
                  )
                else if (info.kind != RenewalKind.memberInfo)
                  FilledButton.tonal(
                    key: const Key('renewal-renew'),
                    onPressed: () => context.push('/subscription'),
                    child: Text(tr('Renew')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
