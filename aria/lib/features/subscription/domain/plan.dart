import 'package:aria/l10n/tr.dart';
import 'package:flutter/foundation.dart';

/// Premium capabilities, keyed like `plans.features_json`.
enum Feature {
  premiumVoices(
    'voices',
    '🎙️',
    'All voices',
    'Every voice and accent, including Hindi and Hinglish',
  ),
  allThemes('themes', '🎨', 'All themes', 'Every colour theme'),
  customAccent(
    'custom_accent',
    '🖌️',
    'Custom colour',
    'Pick your own accent colour',
  ),
  routines('routines', '🌅', 'Routines', 'Guided morning and bedtime routines'),
  weeklyReport(
    'weekly_report',
    '📊',
    'Weekly report',
    'On-time %, streaks and bills paid on time',
  ),
  locationReminders(
    'location_reminders',
    '📍',
    'Location reminders',
    '“Remind me to buy milk when I leave work”',
  ),
  whatsapp(
    'whatsapp',
    '💬',
    'WhatsApp reminders',
    'Reminders on WhatsApp too — reply DONE to tick them off',
  ),
  smartSuggestions(
    'smart_suggestions',
    '💡',
    'Smart suggestions',
    'Aria spots patterns and offers one-tap fixes',
  ),
  unlimitedLists('max_lists', '📝', 'Unlimited lists', 'Free includes 2 lists'),
  sharedCircle(
    'shared_circle',
    '👪',
    'Family Circle',
    'Share lists and reminders with up to 5 people',
  ),
  dependents(
    'dependents',
    '💜',
    'Dependents & Simple Mode lock',
    'Look after parents or kids with a simple, locked app',
  ),
  assignReminders(
    'assign_reminders',
    '📤',
    'Assign reminders',
    'Remind Dad to take his tablet — from your phone',
  ),
  auditLog(
    'audit_log',
    '🗒️',
    'Activity log',
    'See who added, removed or assigned what',
  );

  Feature(this.key, this.emoji, this._title, this._blurb);
  final String key;
  final String emoji;
  final String _title;
  String get title => tr(_title);
  final String _blurb;
  String get blurb => tr(_blurb);

  static Feature? parse(String? s) =>
      values.where((f) => f.name == s).firstOrNull;
}

enum BillingPeriod { month, year }

@immutable
class Plan {
  const Plan({
    required this.code,
    required this.name,
    required this.maxSeats,
    required this.priceMonth,
    required this.priceYear,
    required this.trialDays,
    required this.sort,
    required this.features,
    this.id,
  });

  factory Plan.fromJson(Map<String, dynamic> j) => Plan(
    id: j['id'] as String?,
    code: j['code'] as String,
    name: j['name'] as String,
    maxSeats: (j['max_seats'] as num).toInt(),
    priceMonth: (j['price_month_inr'] as num).toInt(),
    priceYear: (j['price_year_inr'] as num).toInt(),
    trialDays: (j['trial_days'] as num?)?.toInt() ?? 0,
    sort: (j['sort'] as num?)?.toInt() ?? 0,
    features: Map<String, dynamic>.from(j['features_json'] as Map? ?? const {}),
  );

  final String? id;
  final String code;
  final String name;
  final int maxSeats;
  final int priceMonth;
  final int priceYear;
  final int trialDays;
  final int sort;
  final Map<String, dynamic> features;

  bool get isFree => code == 'free';
  bool get isShared => code == 'family' || code == 'team';
  bool get mostPopular => features['most_popular'] == true;

  int price(BillingPeriod p) =>
      p == BillingPeriod.month ? priceMonth : priceYear;

  /// "just ₹40/person/month" on shared plans.
  int? perPersonMonthly(BillingPeriod p) {
    if (maxSeats <= 1) return null;
    final monthly = p == BillingPeriod.month ? priceMonth : priceYear / 12;
    return (monthly / maxSeats).round();
  }

  /// Yearly saving vs 12 × monthly, in whole percent.
  int get yearlySavingPercent =>
      priceMonth == 0 ? 0 : (100 - priceYear * 100 / (priceMonth * 12)).round();

  int? get maxLists => switch (features['max_lists']) {
    final num n => n.toInt(),
    _ => null,
  };

  bool has(Feature f) => switch (f) {
    Feature.premiumVoices => features['voices'] == 'all',
    Feature.allThemes => features['themes'] == 'all',
    Feature.unlimitedLists => maxLists == null,
    _ => features[f.key] == true,
  };

  bool voiceAllowed(String id) {
    final v = features['voices'];
    return v == 'all' || (v is List && v.contains(id));
  }

  bool themeAllowed(String id) {
    final t = features['themes'];
    return t == 'all' || (t is List && t.contains(id));
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'max_seats': maxSeats,
    'price_month_inr': priceMonth,
    'price_year_inr': priceYear,
    'trial_days': trialDays,
    'sort': sort,
    'features_json': features,
  };
}

/// What the server last said, bundled so a first offline launch works.
/// Source of truth: `public.plans` (prices are edited there, not here).
abstract final class PlanCatalog {
  static const _common = {'morning_briefing': true};
  static final fallback = <Plan>[
    Plan(
      code: 'free',
      name: tr('Free'),
      maxSeats: 1,
      priceMonth: 0,
      priceYear: 0,
      trialDays: 0,
      sort: 0,
      features: const {
        ..._common,
        'voices': ['aria', 'device'],
        'max_lists': 2,
        'themes': ['neon', 'lavender', 'ocean', 'mint'],
      },
    ),
    Plan(
      code: 'personal',
      name: tr('Personal'),
      maxSeats: 1,
      priceMonth: 99,
      priceYear: 999,
      trialDays: 7,
      sort: 1,
      features: const {
        ..._common,
        'voices': 'all',
        'max_lists': null,
        'themes': 'all',
        'routines': true,
        'weekly_report': true,
        'custom_accent': true,
        'smart_suggestions': true,
        'location_reminders': true,
        'widgets': true,
      },
    ),
    Plan(
      code: 'family',
      name: tr('Family'),
      maxSeats: 5,
      priceMonth: 199,
      priceYear: 1999,
      trialDays: 7,
      sort: 2,
      features: const {
        ..._common,
        'voices': 'all',
        'max_lists': null,
        'themes': 'all',
        'routines': true,
        'weekly_report': true,
        'custom_accent': true,
        'smart_suggestions': true,
        'location_reminders': true,
        'widgets': true,
        'shared_circle': true,
        'dependents': true,
        'simple_mode_lock': true,
        'assign_reminders': true,
        'whatsapp': true,
        'most_popular': true,
      },
    ),
    Plan(
      code: 'team',
      name: tr('Team'),
      maxSeats: 15,
      priceMonth: 499,
      priceYear: 4999,
      trialDays: 7,
      sort: 3,
      features: const {
        ..._common,
        'voices': 'all',
        'max_lists': null,
        'themes': 'all',
        'routines': true,
        'weekly_report': true,
        'custom_accent': true,
        'smart_suggestions': true,
        'location_reminders': true,
        'widgets': true,
        'shared_circle': true,
        'dependents': true,
        'simple_mode_lock': true,
        'assign_reminders': true,
        'whatsapp': true,
        'audit_log': true,
        'admin_dashboard': true,
        'priority_support': true,
      },
    ),
  ];

  /// Cheapest plan that unlocks [f] (what a paywall recommends).
  static Plan cheapestWith(List<Plan> plans, Feature f) =>
      (plans.where((p) => p.has(f)).toList()
            ..sort((a, b) => a.sort.compareTo(b.sort)))
          .firstOrNull ??
      plans.last;
}

/// The plan that applies to me: the best plan among the Circles I'm an
/// active member of (a Family plan covers every member).
@immutable
class Entitlement {
  const Entitlement(this.plan, {this.circleId});
  final Plan plan;

  /// The Circle whose plan grants this (null = free).
  final String? circleId;

  bool can(Feature f) => plan.has(f);
  bool get isPremium => !plan.isFree;
}

/// Server state of one Circle's subscription (`circle_billing()`).
@immutable
class CircleBilling {
  const CircleBilling({
    required this.planCode,
    required this.seatsUsed,
    required this.maxSeats,
    this.status,
    this.provider,
    this.period,
    this.currentPeriodEnd,
    this.trialEnd,
    this.cancelAtPeriodEnd = false,
    this.trialUsed = false,
    this.autoRenews = false,
    this.lapsedPlanCode,
    this.lapsedAt,
  });

  factory CircleBilling.fromJson(Map<String, dynamic> j) => CircleBilling(
    planCode: j['plan_code'] as String,
    status: j['status'] as String?,
    provider: j['provider'] as String?,
    period: j['period'] as String?,
    currentPeriodEnd: DateTime.tryParse(
      j['current_period_end'] as String? ?? '',
    ),
    trialEnd: DateTime.tryParse(j['trial_end'] as String? ?? ''),
    cancelAtPeriodEnd: j['cancel_at_period_end'] as bool? ?? false,
    trialUsed: j['trial_used'] as bool? ?? false,
    autoRenews: j['auto_renews'] as bool? ?? false,
    lapsedPlanCode: j['lapsed_plan_code'] as String?,
    lapsedAt: DateTime.tryParse(j['lapsed_at'] as String? ?? ''),
    seatsUsed: (j['seats_used'] as num?)?.toInt() ?? 1,
    maxSeats: (j['max_seats'] as num?)?.toInt() ?? 1,
  );

  final String planCode;
  final String? status; // trialing | active | past_due | canceled
  final String? provider; // revenuecat | razorpay | manual
  final String? period;
  final DateTime? currentPeriodEnd;
  final DateTime? trialEnd;
  final bool cancelAtPeriodEnd;
  final bool trialUsed;

  /// Store/Razorpay subscription that will renew by itself (no nagging).
  final bool autoRenews;

  /// The paid plan that ended in the last 30 days (now on Free), if any.
  final String? lapsedPlanCode;
  final DateTime? lapsedAt;
  final int seatsUsed;
  final int maxSeats;

  bool get trialing => status == 'trialing';

  /// When access ends or renews.
  DateTime? get endsAt => currentPeriodEnd ?? trialEnd;

  /// Ends rather than renews (trial, cancelled, promo).
  /// Ends rather than renews: trials, promo/granted months, auto-renew off.
  bool get ending => !autoRenews;

  /// Store couldn't take the renewal payment (grace period).
  bool get paymentIssue => status == 'past_due';
}

/// A past charge / change for the billing history list.
@immutable
class BillingRecord {
  const BillingRecord({
    required this.type,
    required this.at,
    this.planCode,
    this.amountInr,
  });

  factory BillingRecord.fromJson(Map<String, dynamic> j) => BillingRecord(
    type: j['type'] as String,
    at: DateTime.parse(j['occurred_at'] as String),
    planCode: j['plan_code'] as String?,
    amountInr: (j['amount_inr'] as num?)?.toDouble(),
  );

  final String type;
  final DateTime at;
  final String? planCode;
  final double? amountInr;

  String describe(String planName) => switch (type) {
    'purchase' => tr('Subscribed to {0}', [planName]),
    'renewal' => tr('{0} renewed', [planName]),
    'trial_started' => tr('{0} free trial started', [planName]),
    'canceled' => tr('Auto-renew turned off'),
    'uncanceled' => tr('Auto-renew turned back on'),
    'expired' => tr('{0} ended', [planName]),
    'billing_issue' => tr('Payment problem — check your payment method'),
    'promo' => tr('{0} from a promo code', [planName]),
    'grant' => tr('{0} added by Aria support', [planName]),
    'refunded' => tr('{0} refunded by the store — ended', [planName]),
    'product_change' => tr('Changed to {0}', [planName]),
    _ => type,
  };
}

/// Friendly text for billing RPC failures.
String billingErrorMessage(Object e) {
  final s = e.toString();
  if (s.contains('trial_used') || s.contains('trial already used')) {
    return tr('This Circle has already had its free trial.');
  }
  if (s.contains('wrong_circle') || s.contains('does not fit')) {
    return tr('That plan is for a different kind of Circle.');
  }
  if (s.contains('invalid_code') || s.contains('not valid')) {
    return tr('That code isn’t valid.');
  }
  if (s.contains('code_used_up') || s.contains('used up')) {
    return tr('That code has been fully used.');
  }
  if (s.contains('already_redeemed') || s.contains('already redeemed')) {
    return tr('This Circle already used that code.');
  }
  if (s.contains('only the owner')) {
    return tr('Only the Circle’s owner can manage its plan.');
  }
  if (s.contains('not_configured')) {
    return tr('That payment method isn’t available yet.');
  }
  return tr('Something went wrong. Check your connection and try again.');
}

/// ₹1,999 style.
String rupeesWhole(num n) {
  final s = n.round().toString();
  if (s.length <= 3) return '₹$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '₹${parts.join(',')},$last3';
}
