import 'dart:async';

import 'package:aria/core/config/env.dart';
import 'package:aria/core/telemetry/telemetry.dart';
import 'package:aria/data/providers.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/circles/domain/circle.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/subscription/data/store_billing.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Upgrade / trial / restore / promo flows, shared by the Subscription
/// screen and the paywall. Every server change is followed by a sync so
/// the new plan (circles.plan_id) lands locally.
class BillingActions {
  BillingActions(this.context, this.ref);
  final BuildContext context;
  final WidgetRef ref;

  void _say(String text) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _sync() async {
    await ref.read(syncEngineProvider)?.syncNow();
  }

  /// The Circle a plan applies to: Personal → my personal Circle; Family /
  /// Team → the active shared Circle I own, any shared Circle I own, or a
  /// new one ("My family").
  Future<Circle?> targetFor(Plan plan, {bool create = false}) async {
    final me = ref.read(currentUserIdProvider);
    final existing = targetCircleFor(
      plan,
      circles: ref.read(myCirclesProvider).value ?? const <Circle>[],
      me: me,
      active: ref.read(activeCircleProvider),
    );
    if (existing != null || !create || !plan.isShared) return existing;
    final type = plan.code == 'team' ? CircleType.team : CircleType.family;
    final id = await ref
        .read(circleApiProvider)
        .createCircle(
          type == CircleType.team ? 'My team' : tr('My family'),
          type,
        );
    await _sync();
    ref
        .read(appPrefsProvider.notifier)
        .update((p) => p.copyWith(activeCircleId: () => id));
    return (ref.read(myCirclesProvider).value ?? const <Circle>[])
            .where((c) => c.id == id)
            .firstOrNull ??
        Circle(
          id: id,
          name: tr('My family'),
          type: type,
          ownerId: me ?? '',
          myRole: CircleRole.owner,
        );
  }

  Future<bool> startTrial(Plan plan) async {
    try {
      final target = await targetFor(plan, create: true);
      if (target == null) return false;
      final ends = await ref
          .read(billingApiProvider)!
          .startTrial(target.id, plan.code);
      ref.read(telemetryProvider).event(TelemetryEvent.trialStarted, {
        'plan': plan.code,
      });
      await _sync();
      ref.invalidate(circleBillingProvider(target.id));
      if (context.mounted) {
        _say(
          tr('🎉 {0} unlocked free until {1}', [
            plan.name,
            MaterialLocalizations.of(context).formatMediumDate(ends.toLocal()),
          ]),
        );
      }
      return true;
    } on Object catch (e) {
      _say(billingErrorMessage(e));
      return false;
    }
  }

  Future<bool> subscribe(Plan plan, BillingPeriod period) async {
    final store = ref.read(storeBillingProvider);
    if (!store.available && !Env.enableRazorpay) {
      _say(
        tr(
          'Purchases aren’t set up in this build yet. Try the free trial or a promo code.',
        ),
      );
      return false;
    }
    try {
      final target = await targetFor(plan, create: true);
      if (target == null) return false;
      if (store.available) {
        ref.read(telemetryProvider).event(TelemetryEvent.purchaseStarted, {
          'plan': plan.code,
          'period': period.name,
        });
        final outcome = await store.purchase(plan, period, circleId: target.id);
        switch (outcome) {
          case PurchaseOutcome.cancelled:
            return false;
          case PurchaseOutcome.pending:
            _say(
              tr(
                'Payment pending. Your plan starts as soon as it goes through.',
              ),
            );
            return false;
          case PurchaseOutcome.purchased:
            ref.read(telemetryProvider).event(
              TelemetryEvent.purchaseCompleted,
              {'plan': plan.code},
            );
            _say(tr('Thank you! {0} is being activated…', [plan.name]));
            unawaited(_awaitPlan(target.id, plan));
            return true;
        }
      }
      final url = await ref
          .read(billingApiProvider)!
          .razorpayCheckout(target.id, plan.code, period);
      await launchUrl(url, mode: LaunchMode.externalApplication);
      return true;
    } on Object catch (e) {
      _say(billingErrorMessage(e));
      return false;
    }
  }

  /// Webhooks usually land within seconds; pull a few times.
  Future<void> _awaitPlan(String circleId, Plan plan) async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration(seconds: 2 + i * 2));
      await _sync();
      final c = (ref.read(myCirclesProvider).value ?? const <Circle>[])
          .where((c) => c.id == circleId)
          .firstOrNull;
      if (c?.planId != null && c!.planId == plan.id) {
        ref.invalidate(circleBillingProvider(circleId));
        return;
      }
    }
  }

  Future<void> restore() async {
    final store = ref.read(storeBillingProvider);
    if (!store.available) {
      await _sync();
      _say(tr('Your plan is up to date.'));
      return;
    }
    try {
      await store.restore();
      await _sync();
      _say(tr('Purchases restored.'));
    } on Object catch (e) {
      _say(billingErrorMessage(e));
    }
  }

  Future<void> redeem(String code, Circle circle) async {
    try {
      final ends = await ref
          .read(billingApiProvider)!
          .redeemPromo(circle.id, code);
      ref.read(telemetryProvider).event(TelemetryEvent.promoRedeemed);
      await _sync();
      ref.invalidate(circleBillingProvider(circle.id));
      if (context.mounted) {
        _say(
          tr('Code applied — premium until {0}', [
            MaterialLocalizations.of(context).formatMediumDate(ends.toLocal()),
          ]),
        );
      }
    } on Object catch (e) {
      _say(billingErrorMessage(e));
    }
  }

  /// Cancel / change payment: the store's subscription page.
  Future<void> manage(CircleBilling b) async {
    if (b.provider == 'manual') {
      _say(
        b.trialing
            ? tr('Your trial ends on its own — nothing to cancel.')
            : tr('This plan ends on its own.'),
      );
      return;
    }
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final url = await ref.read(storeBillingProvider).managementUrl();
    final fallback = ios
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions';
    await launchUrl(
      Uri.parse(url ?? fallback),
      mode: LaunchMode.externalApplication,
    );
  }
}
