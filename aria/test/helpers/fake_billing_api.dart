import 'package:aria/data/local/app_database.dart';
import 'package:aria/features/subscription/data/billing_api.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:drift/drift.dart';

/// Fallback catalogue with ids, as the server would return it.
final List<Plan> kTestPlans = [
  for (final p in PlanCatalog.fallback)
    Plan.fromJson({...p.toJson(), 'id': 'plan-${p.code}'}),
];

/// Sets a circle's plan locally (what a webhook + sync would deliver).
Future<void> setPlan(AppDatabase db, String circleId, String code) =>
    (db.update(db.circles)..where((c) => c.id.equals(circleId))).write(
      CirclesCompanion(planId: Value('plan-$code')),
    );

/// Server billing stand-in writing straight to the local database.
class FakeBillingApi implements BillingApi {
  FakeBillingApi(this.db);
  final AppDatabase db;
  final trials = <String>{};
  final ends = <String, DateTime>{};
  final codes = <String, String>{'STUDENT30': 'personal'};
  final records = <BillingRecord>[];
  DateTime now = DateTime.utc(2026, 11, 9, 4, 30);

  @override
  Future<List<Plan>> plans() async => kTestPlans;

  Future<String> _planCode(String circleId) async {
    final c = await (db.select(
      db.circles,
    )..where((x) => x.id.equals(circleId))).getSingle();
    return (c.planId ?? 'plan-free').replaceFirst('plan-', '');
  }

  /// Tests can force what the server reports for a circle.
  final forced = <String, CircleBilling>{};

  @override
  Future<CircleBilling?> circleBilling(String circleId) async {
    if (forced[circleId] case final f?) return f;
    final code = await _planCode(circleId);
    final seats =
        await (db.select(db.memberships)..where(
              (m) => m.circleId.equals(circleId) & m.status.equals('active'),
            ))
            .get();
    final plan = kTestPlans.firstWhere((p) => p.code == code);
    final trialing = trials.contains(circleId) && code != 'free';
    return CircleBilling(
      planCode: code,
      status: code == 'free' ? null : (trialing ? 'trialing' : 'active'),
      provider: code == 'free' ? null : 'manual',
      trialEnd: trialing ? ends[circleId] : null,
      currentPeriodEnd: trialing ? null : ends[circleId],
      trialUsed: trials.contains(circleId),
      seatsUsed: seats.length,
      maxSeats: plan.maxSeats,
    );
  }

  @override
  Future<DateTime> startTrial(String circleId, String planCode) async {
    if (trials.contains(circleId)) {
      throw Exception('trial already used (trial_used)');
    }
    trials.add(circleId);
    final end = now.add(const Duration(days: 7));
    ends[circleId] = end;
    await setPlan(db, circleId, planCode);
    records.add(
      BillingRecord(type: 'trial_started', at: now, planCode: planCode),
    );
    return end;
  }

  @override
  Future<DateTime> redeemPromo(String circleId, String code) async {
    final plan = codes[code.trim().toUpperCase()];
    if (plan == null) throw Exception('promo code not valid (invalid_code)');
    final end = now.add(const Duration(days: 30));
    ends[circleId] = end;
    await setPlan(db, circleId, plan);
    records.add(
      BillingRecord(type: 'promo', at: now, planCode: plan, amountInr: 0),
    );
    return end;
  }

  @override
  Future<List<BillingRecord>> history(String circleId) async =>
      records.reversed.toList();

  @override
  Future<Uri> razorpayCheckout(
    String circleId,
    String planCode,
    BillingPeriod period,
  ) => throw Exception('not_configured');
}
