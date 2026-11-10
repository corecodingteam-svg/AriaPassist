import 'package:supabase_flutter/supabase_flutter.dart';

/// One JSON row from an admin function.
typedef Rec = Map<String, dynamic>;

enum AdminRole {
  superAdmin('super'),
  support('support'),
  finance('finance');

  AdminRole(this.wire);
  final String wire;
  static AdminRole? parse(Object? s) =>
      values.where((r) => r.wire == s).firstOrNull;

  bool get canAct => this != finance;
  bool get isSuper => this == superAdmin;
  String get label => switch (this) {
    superAdmin => 'Super-admin',
    support => 'Support',
    finance => 'Finance (read-only)',
  };
}

/// Every call goes through role-checked SECURITY DEFINER functions; the
/// panel never reads tables directly.
abstract interface class AdminApi {
  Future<({AdminRole? role, String aal})> me();
  Future<Rec> overview();
  Future<List<Rec>> report(String name, {int limit = 200, int offset = 0});
  Future<List<Rec>> searchUsers(String q, {int limit = 50});
  Future<Rec> userDetail(String userId);
  Future<List<Rec>> promos();
  Future<List<Rec>> admins();

  Future<void> suspend(String userId, String reason);
  Future<void> unsuspend(String userId, String reason);
  Future<void> signOutEverywhere(String userId, String reason);
  Future<DateTime> grantPlan(
    String circleId,
    String plan,
    int days,
    String reason,
  );
  Future<void> cancelDeletion(String userId, String reason);
  Future<void> deleteNow(String userId, String reason);
  Future<String> createPromo({
    required String code,
    required String plan,
    required int days,
    required int? maxRedemptions,
    required DateTime? expiresAt,
    required String? note,
    required String reason,
  });
  Future<void> disablePromo(String code, String reason);
  Future<void> setRole(String userId, AdminRole? role, String reason);
}

class SupabaseAdminApi implements AdminApi {
  SupabaseAdminApi(this._db);
  final SupabaseClient _db;

  Future<T> _rpc<T>(String fn, [Map<String, dynamic>? params]) async =>
      await _db.rpc<T>(fn, params: params);

  List<Rec> _rows(Object? v) => [
    for (final r in (v as List? ?? const []))
      Map<String, dynamic>.from(r as Map),
  ];

  @override
  Future<({AdminRole? role, String aal})> me() async {
    final m = Map<String, dynamic>.from(
      await _rpc<Map<dynamic, dynamic>>('admin_me'),
    );
    return (
      role: AdminRole.parse(m['role']),
      aal: m['aal'] as String? ?? 'aal1',
    );
  }

  @override
  Future<Rec> overview() async => Map<String, dynamic>.from(
    await _rpc<Map<dynamic, dynamic>>('admin_overview'),
  );

  @override
  Future<List<Rec>> report(
    String name, {
    int limit = 200,
    int offset = 0,
  }) async => _rows(
    await _rpc<dynamic>('admin_report', {
      'p_name': name,
      'p_limit': limit,
      'p_offset': offset,
    }),
  );

  @override
  Future<List<Rec>> searchUsers(String q, {int limit = 50}) async => _rows(
    await _rpc<dynamic>('admin_search_users', {'p_q': q, 'p_limit': limit}),
  );

  @override
  Future<Rec> userDetail(String userId) async => Map<String, dynamic>.from(
    await _rpc<Map<dynamic, dynamic>>('admin_user_detail', {'p_user': userId}),
  );

  @override
  Future<List<Rec>> promos() async =>
      _rows(await _rpc<dynamic>('admin_list_promos'));

  @override
  Future<List<Rec>> admins() async =>
      _rows(await _rpc<dynamic>('admin_list_admins'));

  @override
  Future<void> suspend(String userId, String reason) => _rpc<dynamic>(
    'admin_suspend_user',
    {'p_user': userId, 'p_reason': reason},
  );

  @override
  Future<void> unsuspend(String userId, String reason) => _rpc<dynamic>(
    'admin_unsuspend_user',
    {'p_user': userId, 'p_reason': reason},
  );

  @override
  Future<void> signOutEverywhere(String userId, String reason) => _rpc<dynamic>(
    'admin_sign_out_everywhere',
    {'p_user': userId, 'p_reason': reason},
  );

  @override
  Future<DateTime> grantPlan(
    String circleId,
    String plan,
    int days,
    String reason,
  ) async => DateTime.parse(
    await _rpc<String>('admin_grant_plan', {
      'p_circle': circleId,
      'p_plan': plan,
      'p_days': days,
      'p_reason': reason,
    }),
  );

  @override
  Future<void> cancelDeletion(String userId, String reason) => _rpc<dynamic>(
    'admin_cancel_deletion',
    {'p_user': userId, 'p_reason': reason},
  );

  @override
  Future<void> deleteNow(String userId, String reason) =>
      _rpc<dynamic>('admin_delete_now', {'p_user': userId, 'p_reason': reason});

  @override
  Future<String> createPromo({
    required String code,
    required String plan,
    required int days,
    required int? maxRedemptions,
    required DateTime? expiresAt,
    required String? note,
    required String reason,
  }) => _rpc<String>('admin_create_promo', {
    'p_code': code,
    'p_plan': plan,
    'p_days': days,
    'p_max': maxRedemptions,
    'p_expires': expiresAt?.toUtc().toIso8601String(),
    'p_note': note,
    'p_reason': reason,
  });

  @override
  Future<void> disablePromo(String code, String reason) => _rpc<dynamic>(
    'admin_disable_promo',
    {'p_code': code, 'p_reason': reason},
  );

  @override
  Future<void> setRole(String userId, AdminRole? role, String reason) =>
      _rpc<dynamic>('admin_set_role', {
        'p_user': userId,
        'p_role': role?.wire,
        'p_reason': reason,
      });
}
