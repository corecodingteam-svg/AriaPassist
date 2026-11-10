import 'dart:async';

import 'package:aria/core/config/env.dart';
import 'package:aria/core/telemetry/telemetry.dart';
import 'package:aria/core/theme/presets.dart';
import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/data/providers.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/circles/domain/circle.dart';
import 'package:aria/features/reminders/domain/alert_plan.dart';
import 'package:aria/features/subscription/data/billing_api.dart';
import 'package:aria/features/subscription/data/store_billing.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:aria/features/voice/application/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final billingApiProvider = Provider<BillingApi?>((ref) {
  try {
    return SupabaseBillingApi(
      ref.watch(supabaseClientProvider),
      ref.watch(sharedPreferencesProvider),
    );
  } on Object {
    return null; // tests without Supabase
  }
});

final storeBillingProvider = Provider<StoreBilling>((ref) {
  final store = Env.revenueCatAndroidKey.isEmpty && Env.revenueCatIosKey.isEmpty
      ? const UnavailableStoreBilling()
      : RevenueCatStoreBilling(
          androidKey: Env.revenueCatAndroidKey,
          iosKey: Env.revenueCatIosKey,
        );
  // RevenueCat app user id = Supabase user id (the webhook checks it owns
  // the Circle being paid for).
  ref.listen(currentUserIdProvider, (_, uid) {
    if (uid != null) {
      unawaited(
        store
            .identify(uid)
            .catchError((Object e) => debugPrint('identify: $e')),
      );
    }
  }, fireImmediately: true);
  return store;
});

/// Plan catalogue: cached/bundled immediately, refreshed from the server.
final plansProvider = NotifierProvider<PlansNotifier, List<Plan>>(
  PlansNotifier.new,
);

class PlansNotifier extends Notifier<List<Plan>> {
  @override
  List<Plan> build() {
    final api = ref.watch(billingApiProvider);
    if (api != null) {
      unawaited(
        api.plans().then((p) {
          if (p.isNotEmpty) state = p;
        }, onError: (Object e) => debugPrint('plans fetch failed: $e')),
      );
    }
    return cachedPlans(ref.watch(sharedPreferencesProvider));
  }
}

Plan planNamed(List<Plan> plans, String code) =>
    plans.where((p) => p.code == code).firstOrNull ??
    PlanCatalog.fallback.firstWhere(
      (p) => p.code == code,
      orElse: () => PlanCatalog.fallback.first,
    );

/// Best plan across my Circles (a Family plan covers every member).
final entitlementProvider = Provider<Entitlement>((ref) {
  final plans = ref.watch(plansProvider);
  final circles = ref.watch(myCirclesProvider).value ?? const <Circle>[];
  final free = planNamed(plans, 'free');
  var best = Entitlement(free);
  for (final c in circles) {
    final p = plans.where((p) => p.id != null && p.id == c.planId).firstOrNull;
    if (p != null && p.sort > best.plan.sort) {
      best = Entitlement(p, circleId: c.id);
    }
  }
  return best;
});

/// True once we can trust a "free" answer: Circles loaded and every
/// Circle's plan id is known (so a slow start never strips premium).
final entitlementSettledProvider = Provider<bool>((ref) {
  final circles = ref.watch(myCirclesProvider).value;
  if (circles == null || circles.isEmpty) return false;
  final ids = ref
      .watch(plansProvider)
      .map((p) => p.id)
      .whereType<String>()
      .toSet();
  return circles.every((c) => c.planId == null || ids.contains(c.planId));
});

// ignore: specify_nonobvious_property_types -- family type is verbose
final circleBillingProvider = FutureProvider.family<CircleBilling?, String>((
  ref,
  circleId,
) async {
  // Re-fetch when the Circle's plan changes (webhook → sync).
  ref.watch(
    myCirclesProvider.select(
      (v) => v.value?.where((c) => c.id == circleId).firstOrNull?.planId,
    ),
  );
  final b = await ref.watch(billingApiProvider)?.circleBilling(circleId);
  if (b != null) ref.read(billingNoticesProvider.notifier).put(circleId, b);
  return b;
});

// ignore: specify_nonobvious_property_types -- family type is verbose
final billingHistoryProvider =
    FutureProvider.family<List<BillingRecord>, String>((ref, circleId) async {
      ref.watch(circleBillingProvider(circleId));
      return await ref.watch(billingApiProvider)?.history(circleId) ?? const [];
    });

/// Owner's "renews/ends in 3 days" heads-ups for the reminder planner.
final billingNoticesProvider =
    NotifierProvider<BillingNotices, Map<String, CircleBilling>>(
      BillingNotices.new,
    );

class BillingNotices extends Notifier<Map<String, CircleBilling>> {
  @override
  Map<String, CircleBilling> build() {
    ref.watch(currentUserIdProvider);
    return const {};
  }

  void put(String circleId, CircleBilling b) => state = {...state, circleId: b};

  List<BillingNotice> notices() {
    final circles = ref.read(myCirclesProvider).value ?? const <Circle>[];
    final plans = ref.read(plansProvider);
    return [
      for (final c in circles)
        if (c.myRole == CircleRole.owner)
          if (state[c.id] case final b?
              when b.endsAt != null && b.planCode != 'free')
            (
              circleId: c.id,
              planName: planNamed(plans, b.planCode).name,
              endsAt: b.endsAt!,
              ending: b.ending,
            ),
    ];
  }
}

/// Graceful downgrade: when premium ends, data stays, but premium-only
/// choices fall back to free defaults (voice, theme, custom accent).
final downgradeGuardProvider = Provider<void>((ref) {
  void enforce() {
    if (!ref.read(entitlementSettledProvider)) return;
    final plan = ref.read(entitlementProvider).plan;
    final voice = ref.read(voiceSettingsProvider);
    if (!plan.voiceAllowed(voice.voiceId)) {
      ref
          .read(voiceSettingsProvider.notifier)
          .update((v) => v.copyWith(voiceId: 'aria'));
    }
    final theme = ref.read(themeControllerProvider);
    if (!plan.themeAllowed(theme.presetId)) {
      ref
          .read(themeControllerProvider.notifier)
          .setPreset(ThemePresets.neon.id);
    }
    if (!plan.has(Feature.customAccent) &&
        ref.read(themeControllerProvider).customAccent != null) {
      ref
          .read(themeControllerProvider.notifier)
          .update((t) => t.copyWith(customAccent: () => null));
    }
  }

  ref
    ..listen(entitlementProvider, (_, _) => enforce())
    ..listen(entitlementSettledProvider, (_, _) => enforce());
});

/// Opens the contextual paywall unless the feature is already unlocked.
/// Returns true when the caller may proceed.
bool requireFeature(BuildContext context, WidgetRef ref, Feature f) {
  if (ref.read(entitlementProvider).can(f)) return true;
  ref.read(telemetryProvider).event(TelemetryEvent.paywallShown, {
    'feature': f.name,
  });
  unawaited(context.push('/paywall?feature=${f.name}'));
  return false;
}

/// Keeps billing state fresh for paid Circles I own (feeds the 3-day
/// renewal/expiry heads-up). Watched app-wide.
final ownerBillingWatchProvider = Provider<void>((ref) {
  final me = ref.watch(currentUserIdProvider);
  final circles = ref.watch(myCirclesProvider).value ?? const <Circle>[];
  final granting = ref.watch(entitlementProvider).circleId;
  for (final c in circles) {
    // Owned Circles (paid or lapsed → renewal banner) and the one that
    // gives me premium (members get an info banner before it ends).
    if (c.ownerId == me || c.id == granting) {
      ref.watch(circleBillingProvider(c.id));
    }
  }
});

/// Whether the Circle a plan would apply to can still start a free trial
/// (a Circle that doesn't exist yet always can).
// ignore: specify_nonobvious_property_types -- family type is verbose
final trialAvailableProvider = FutureProvider.family<bool, String>((
  ref,
  planCode,
) async {
  final plan = planNamed(ref.watch(plansProvider), planCode);
  if (plan.trialDays <= 0) return false;
  final target = targetCircleFor(
    plan,
    circles: ref.watch(myCirclesProvider).value ?? const <Circle>[],
    me: ref.watch(currentUserIdProvider),
    active: ref.watch(activeCircleProvider),
  );
  if (target == null) return true;
  final b = await ref.watch(circleBillingProvider(target.id).future);
  return b == null || (!b.trialUsed && b.planCode == 'free');
});

/// Personal → my personal Circle; Family/Team → the active shared Circle I
/// own, else any shared Circle I own (null = one will be created).
Circle? targetCircleFor(
  Plan plan, {
  required List<Circle> circles,
  required String? me,
  required Circle? active,
}) {
  final owned = circles.where((c) => c.ownerId == me).toList();
  if (!plan.isShared) return owned.where((c) => c.isPersonal).firstOrNull;
  if (active != null && !active.isPersonal && active.ownerId == me) {
    return active;
  }
  return owned.where((c) => !c.isPersonal).firstOrNull;
}

/// A Circle's own plan (seats, assigning and locks follow the Circle).
Plan planOfCircle(List<Plan> plans, Circle? c) =>
    plans.where((p) => p.id != null && p.id == c?.planId).firstOrNull ??
    planNamed(plans, 'free');

/// Like [requireFeature], but for what a specific Circle's plan allows.
bool requireCircleFeature(
  BuildContext context,
  WidgetRef ref,
  Circle circle,
  Feature f,
) {
  if (planOfCircle(ref.read(plansProvider), circle).has(f)) return true;
  ref.read(telemetryProvider).event(TelemetryEvent.paywallShown, {
    'feature': f.name,
  });
  unawaited(context.push('/paywall?feature=${f.name}'));
  return false;
}
