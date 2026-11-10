import 'dart:convert';

import 'package:aria/features/subscription/domain/plan.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Server-side billing (RLS + SECURITY DEFINER RPCs). Purchases through the
/// stores go via `StoreBilling`; the webhook then updates the Circle.
abstract interface class BillingApi {
  Future<List<Plan>> plans();
  Future<CircleBilling?> circleBilling(String circleId);
  Future<DateTime> startTrial(String circleId, String planCode);
  Future<DateTime> redeemPromo(String circleId, String code);
  Future<List<BillingRecord>> history(String circleId);

  /// Hosted Razorpay checkout URL (direct/web payments builds only).
  Future<Uri> razorpayCheckout(
    String circleId,
    String planCode,
    BillingPeriod period,
  );
}

const kPlansCacheKey = 'aria.plans.v1';

class SupabaseBillingApi implements BillingApi {
  SupabaseBillingApi(this._db, this._prefs);
  final SupabaseClient _db;
  final SharedPreferences _prefs;

  @override
  Future<List<Plan>> plans() async {
    try {
      final rows = await _db
          .from('plans')
          .select()
          .eq('is_active', true)
          .order('sort');
      await _prefs.setString(kPlansCacheKey, jsonEncode(rows));
      return rows.map(Plan.fromJson).toList();
    } on Object {
      return cachedPlans(_prefs);
    }
  }

  @override
  Future<CircleBilling?> circleBilling(String circleId) async {
    final rows = await _db.rpc<List<dynamic>>(
      'circle_billing',
      params: {'p_circle': circleId},
    );
    return rows.isEmpty
        ? null
        : CircleBilling.fromJson(Map<String, dynamic>.from(rows.first as Map));
  }

  @override
  Future<DateTime> startTrial(String circleId, String planCode) async =>
      DateTime.parse(
        await _db.rpc<String>(
          'start_trial',
          params: {'p_circle': circleId, 'p_plan': planCode},
        ),
      );

  @override
  Future<DateTime> redeemPromo(String circleId, String code) async =>
      DateTime.parse(
        await _db.rpc<String>(
          'redeem_promo',
          params: {'p_circle': circleId, 'p_code': code},
        ),
      );

  @override
  Future<List<BillingRecord>> history(String circleId) async {
    final rows = await _db
        .from('billing_events')
        .select('type, plan_code, amount_inr, occurred_at')
        .eq('circle_id', circleId)
        .order('occurred_at', ascending: false)
        .limit(50);
    return rows.map(BillingRecord.fromJson).toList();
  }

  @override
  Future<Uri> razorpayCheckout(
    String circleId,
    String planCode,
    BillingPeriod period,
  ) async {
    final res = await _db.functions.invoke(
      'razorpay-checkout',
      body: {
        'circle_id': circleId,
        'plan_code': planCode,
        'period': period.name,
      },
    );
    final url = (res.data as Map?)?['url'] as String?;
    if (res.status != 200 || url == null) {
      throw Exception((res.data as Map?)?['error'] ?? 'checkout_failed');
    }
    return Uri.parse(url);
  }
}

/// Last server catalogue, else the bundled copy.
List<Plan> cachedPlans(SharedPreferences prefs) {
  final raw = prefs.getString(kPlansCacheKey);
  if (raw == null) return PlanCatalog.fallback;
  try {
    return (jsonDecode(raw) as List)
        .map((j) => Plan.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
  } on Object {
    return PlanCatalog.fallback;
  }
}
