import 'package:aria/features/circles/domain/circle.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Server-authoritative Circle operations (need a connection). RLS and the
/// SECURITY DEFINER functions decide what's allowed; the client never
/// asserts roles itself.
abstract interface class CircleApi {
  Future<String> createCircle(String name, CircleType type);
  Future<void> renameCircle(String circleId, String name);
  Future<void> updateCircleSettings(
    String circleId,
    Map<String, dynamic> settings,
  );
  Future<String> createInvite(String circleId, CircleRole role);
  Future<InvitePreview?> previewInvite(String token);
  Future<String> acceptInvite(String token);
  Future<void> setRole(String circleId, String userId, CircleRole role);
  Future<void> updateMemberSettings(
    String circleId,
    String userId,
    Map<String, dynamic> settings,
  );
  Future<void> removeMember(String circleId, String userId);
  Future<void> leave(String circleId);
  Future<void> transferOwnership(String circleId, String newOwner);
  Future<List<AuditEntry>> auditLog(
    String circleId, {
    Map<String, String> names = const {},
  });
}

class SupabaseCircleApi implements CircleApi {
  SupabaseCircleApi(this._db);
  final SupabaseClient _db;

  String get _uid => _db.auth.currentUser!.id;

  @override
  Future<String> createCircle(String name, CircleType type) async {
    final row = await _db
        .from('circles')
        .insert({'name': name.trim(), 'type': type.name, 'owner_id': _uid})
        .select('id')
        .single();
    return row['id'] as String;
  }

  @override
  Future<void> renameCircle(String circleId, String name) =>
      _db.from('circles').update({'name': name.trim()}).eq('id', circleId);

  @override
  Future<void> updateCircleSettings(
    String circleId,
    Map<String, dynamic> settings,
  ) => _db
      .from('circles')
      .update({'settings_json': settings})
      .eq('id', circleId);

  @override
  Future<String> createInvite(String circleId, CircleRole role) async {
    final row = await _db
        .from('invites')
        .insert({'circle_id': circleId, 'role': role.name, 'created_by': _uid})
        .select('token')
        .single();
    return row['token'] as String;
  }

  @override
  Future<InvitePreview?> previewInvite(String token) async {
    final rows = await _db.rpc<List<dynamic>>(
      'preview_invite',
      params: {'p_token': token},
    );
    if (rows.isEmpty) return null;
    final r = rows.first as Map<String, dynamic>;
    return InvitePreview(
      circleId: r['circle_id'] as String,
      circleName: r['circle_name'] as String,
      circleType: CircleType.parse(r['circle_type'] as String?),
      inviterName: r['inviter_name'] as String?,
      role: CircleRole.parse(r['role'] as String?),
      expired: r['expired'] as bool? ?? false,
      used: r['used'] as bool? ?? false,
      alreadyMember: r['already_member'] as bool? ?? false,
    );
  }

  @override
  Future<String> acceptInvite(String token) async =>
      await _db.rpc<String>('accept_invite', params: {'p_token': token});

  @override
  Future<void> setRole(String circleId, String userId, CircleRole role) => _db
      .from('memberships')
      .update({'role': role.name})
      .eq('circle_id', circleId)
      .eq('user_id', userId);

  @override
  Future<void> updateMemberSettings(
    String circleId,
    String userId,
    Map<String, dynamic> settings,
  ) => _db
      .from('memberships')
      .update({'settings_json': settings})
      .eq('circle_id', circleId)
      .eq('user_id', userId);

  @override
  Future<void> removeMember(String circleId, String userId) => _db
      .from('memberships')
      .update({'status': 'removed'})
      .eq('circle_id', circleId)
      .eq('user_id', userId);

  @override
  Future<void> leave(String circleId) =>
      _db.rpc<void>('leave_circle', params: {'p_circle': circleId});

  @override
  Future<void> transferOwnership(String circleId, String newOwner) =>
      _db.rpc<void>(
        'transfer_ownership',
        params: {'p_circle': circleId, 'p_new_owner': newOwner},
      );

  @override
  Future<List<AuditEntry>> auditLog(
    String circleId, {
    Map<String, String> names = const {},
  }) async {
    final rows = await _db
        .from('audit_logs')
        .select('action, actor_id, target, meta_json, at')
        .eq('circle_id', circleId)
        .order('at', ascending: false)
        .limit(100);
    return [
      for (final r in rows)
        AuditEntry(
          action: r['action'] as String,
          at: DateTime.parse(r['at'] as String),
          actorName: names[r['actor_id']],
          targetName: names[r['target']],
          detail:
              (r['meta_json'] as Map?)?['title'] as String? ??
              (r['meta_json'] as Map?)?['role'] as String?,
        ),
    ];
  }
}
