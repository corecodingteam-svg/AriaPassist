import 'package:aria_admin/data/admin_api.dart';
import 'package:aria_admin/data/admin_auth.dart';
import 'package:flutter/foundation.dart';

class FakeAuth extends ChangeNotifier implements AdminAuth {
  bool _signedIn = false;
  String _aal = 'aal1';
  List<String> factors = [];
  final sent = <String>[];

  void signInAs({String aal = 'aal2'}) {
    _signedIn = true;
    _aal = aal;
    notifyListeners();
  }

  @override
  bool get signedIn => _signedIn;
  @override
  String get aal => _aal;
  @override
  String? get userLabel => _signedIn ? 'boss@aria.test' : null;
  @override
  Future<void> sendCode(String id) async => sent.add(id);
  @override
  Future<void> verifyCode(String id, String code) async {
    if (code != '123456') throw Exception('Token has expired or is invalid');
    signInAs(aal: 'aal1');
  }

  @override
  Future<List<String>> verifiedFactorIds() async => factors;
  @override
  Future<({String factorId, String uri, String secret})> enroll() async => (
    factorId: 'f1',
    uri: 'otpauth://totp/Aria%20Admin:boss?secret=JBSWY3DPEHPK3PXP&issuer=Aria%20Admin',
    secret: 'JBSWY3DPEHPK3PXP',
  );
  @override
  Future<void> verifyFactor(String factorId, String code) async {
    if (code != '654321') throw Exception('invalid TOTP code');
    factors = [factorId];
    _aal = 'aal2';
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    _signedIn = false;
    _aal = 'aal1';
    notifyListeners();
  }
}

class FakeApi implements AdminApi {
  AdminRole? role = AdminRole.superAdmin;
  final calls = <String>[];
  final users = <Rec>[
    {
      'id': 'u-1',
      'name': 'Asha Rao',
      'phone': '919800000001',
      'email': null,
      'created_at': '2026-11-01T00:00:00Z',
      'last_seen_at': '2026-11-08T00:00:00Z',
      'suspended_at': null,
      'suspended_reason': null,
      'circles': 2,
      'reminders': 14,
      'deletion_after': null,
      'admin_role': null,
    },
  ];
  final promoRows = <Rec>[];

  @override
  Future<({AdminRole? role, String aal})> me() async =>
      (role: role, aal: 'aal2');
  @override
  Future<Rec> overview() async => {
    'users': 1234,
    'signups_7d': 56,
    'active_7d': 700,
    'active_30d': 980,
    'paid_circles': 210,
    'trials': 30,
    'granted': 4,
    'mrr_inr': 41790,
    'revenue_this_month_inr': 52000,
    'expiring_7d': 12,
    'lapsed_30d': 9,
    'past_due': 2,
    'suspended': 1,
    'pending_deletions': 3,
    'reminders_7d': 8800,
  };
  @override
  Future<List<Rec>> report(
    String name, {
    int limit = 200,
    int offset = 0,
  }) async => switch (name) {
    'activity_daily' => [
      for (var i = 0; i < 30; i++)
        {
          'day': '2026-10-${(i + 1).toString().padLeft(2, '0')}',
          'signups': i,
          'active_users': 100 + i,
          'reminders_created': 50,
          'reminders_missed': 2,
        },
    ],
    'expiring' => [
      {
        'circle_name': 'Rao family',
        'owner_id': 'u-1',
        'current_plan': 'family',
        'paid_until': '2026-11-12T00:00:00Z',
        'days_left': 3,
        'auto_renews': false,
        'provider': 'manual',
        'total_paid_inr': 0,
      },
    ],
    'revenue_monthly' => [
      {
        'month': '2026-11-01',
        'plan_code': 'family',
        'provider': 'revenuecat',
        'payments': 10,
        'gross_inr': 1990,
      },
    ],
    _ => const [],
  };
  @override
  Future<List<Rec>> searchUsers(String q, {int limit = 50}) async => [
    for (final u in users)
      if (q.isEmpty || '${u['name']}'.toLowerCase().contains(q.toLowerCase()))
        u,
  ];
  @override
  Future<Rec> userDetail(String userId) async => {
    'user': users.firstWhere((u) => u['id'] == userId),
    'circles': [
      {
        'id': 'c-1',
        'name': 'Rao family',
        'type': 'family',
        'role': 'owner',
        'status': 'active',
        'plan': 'family',
        'paid_until': '2026-11-12T00:00:00Z',
        'auto_renews': false,
        'provider': 'manual',
        'members': 3,
      },
    ],
    'billing': [
      {
        'type': 'trial_started',
        'plan': 'family',
        'amount_inr': null,
        'provider': 'manual',
        'at': '2026-11-05T00:00:00Z',
      },
    ],
    'renewal_notices': <Rec>[],
    'actions': [
      for (final c in calls.where((c) => c.contains(userId)))
        {
          'action': c,
          'actor': 'boss',
          'reason': 'test',
          'at': '2026-11-09T00:00:00Z',
        },
    ],
  };
  @override
  Future<List<Rec>> promos() async => promoRows;
  @override
  Future<List<Rec>> admins() async => [
    {
      'user_id': 'a-1',
      'role': 'super',
      'name': 'Boss',
      'email': 'boss@aria.test',
      'since': '2026-11-01T00:00:00Z',
    },
  ];

  @override
  Future<void> suspend(String userId, String reason) async {
    calls.add('suspend $userId: $reason');
    users.first['suspended_at'] = '2026-11-09T05:00:00Z';
    users.first['suspended_reason'] = reason;
  }

  @override
  Future<void> unsuspend(String userId, String reason) async {
    calls.add('unsuspend $userId: $reason');
    users.first['suspended_at'] = null;
  }

  @override
  Future<void> signOutEverywhere(String userId, String reason) async =>
      calls.add('signout $userId: $reason');
  @override
  Future<DateTime> grantPlan(
    String circleId,
    String plan,
    int days,
    String reason,
  ) async {
    calls.add('grant $circleId $plan $days: $reason');
    return DateTime.utc(2026, 12, 12);
  }

  @override
  Future<void> cancelDeletion(String userId, String reason) async =>
      calls.add('cancel-deletion $userId');
  @override
  Future<void> deleteNow(String userId, String reason) async =>
      calls.add('delete $userId: $reason');
  @override
  Future<String> createPromo({
    required String code,
    required String plan,
    required int days,
    required int? maxRedemptions,
    required DateTime? expiresAt,
    required String? note,
    required String reason,
  }) async {
    if (reason.length < 3) {
      throw Exception('message: a reason is required, hint: reason_required');
    }
    calls.add('promo $code $plan $days');
    promoRows.add({
      'code': code.toUpperCase(),
      'plan': plan,
      'days': days,
      'redemptions': 0,
      'max_redemptions': maxRedemptions,
      'is_active': true,
      'note': note,
    });
    return code.toUpperCase();
  }

  @override
  Future<void> disablePromo(String code, String reason) async =>
      calls.add('disable $code');
  @override
  Future<void> setRole(String userId, AdminRole? role, String reason) async =>
      calls.add('role $userId ${role?.wire}');
}
