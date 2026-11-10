import 'dart:convert';

import 'package:aria/data/local/app_database.dart';
import 'package:aria/features/circles/data/circle_api.dart';
import 'package:aria/features/circles/domain/circle.dart';
import 'package:drift/drift.dart';

/// Stands in for the server *and* the following sync: every operation
/// lands directly in the local database, as a pull would deliver it.
class FakeCircleApi implements CircleApi {
  FakeCircleApi(this.db, this.userId);
  final AppDatabase db;
  final String userId;

  /// token → (preview, role). Tests register invites they want to accept.
  final invites = <String, InvitePreview>{};
  final created = <(String circleId, CircleRole role)>[];
  final audit = <AuditEntry>[];

  /// When set, the next acceptInvite throws this (e.g. seat limit).
  Exception? acceptError;
  var _n = 0;

  Future<void> addMember(
    String circleId,
    String uid,
    CircleRole role, {
    String? name,
    Map<String, dynamic>? settings,
  }) async {
    if (name != null) {
      await db
          .into(db.users)
          .insertOnConflictUpdate(
            UsersCompanion.insert(id: uid, name: Value(name)),
          );
    }
    await db
        .into(db.memberships)
        .insertOnConflictUpdate(
          MembershipsCompanion.insert(
            id: 'm-$circleId-$uid',
            circleId: circleId,
            userId: uid,
            role: role.name,
            status: 'active',
            settingsJson: Value(settings == null ? null : jsonEncode(settings)),
          ),
        );
  }

  @override
  Future<String> createCircle(String name, CircleType type) async {
    final id = 'circle-${++_n}';
    await db
        .into(db.circles)
        .insert(
          CirclesCompanion.insert(
            id: id,
            name: name,
            type: type.name,
            ownerId: userId,
            planId: const Value('plan-free'),
          ),
        );
    await addMember(id, userId, CircleRole.owner);
    return id;
  }

  @override
  Future<void> renameCircle(String circleId, String name) =>
      (db.update(db.circles)..where((c) => c.id.equals(circleId))).write(
        CirclesCompanion(name: Value(name)),
      );

  @override
  Future<void> updateCircleSettings(
    String circleId,
    Map<String, dynamic> settings,
  ) => (db.update(db.circles)..where((c) => c.id.equals(circleId))).write(
    CirclesCompanion(settingsJson: Value(jsonEncode(settings))),
  );

  @override
  Future<String> createInvite(String circleId, CircleRole role) async {
    created.add((circleId, role));
    return 'tok${created.length}';
  }

  @override
  Future<InvitePreview?> previewInvite(String token) async => invites[token];

  @override
  Future<String> acceptInvite(String token) async {
    final e = acceptError;
    if (e != null) {
      acceptError = null;
      throw e;
    }
    final p = invites[token];
    if (p == null) throw Exception('invite not found');
    final exists = await (db.select(
      db.circles,
    )..where((c) => c.id.equals(p.circleId))).getSingleOrNull();
    if (exists == null) {
      await db
          .into(db.circles)
          .insert(
            CirclesCompanion.insert(
              id: p.circleId,
              name: p.circleName,
              type: p.circleType.name,
              ownerId: 'owner-of-${p.circleId}',
              planId: const Value('plan-family'),
            ),
          );
    }
    await addMember(p.circleId, userId, p.role);
    return p.circleId;
  }

  Future<void> _membership(
    String circleId,
    String uid,
    MembershipsCompanion c,
  ) => (db.update(
    db.memberships,
  )..where((m) => m.circleId.equals(circleId) & m.userId.equals(uid))).write(c);

  @override
  Future<void> setRole(String circleId, String uid, CircleRole role) =>
      _membership(circleId, uid, MembershipsCompanion(role: Value(role.name)));

  @override
  Future<void> updateMemberSettings(
    String circleId,
    String uid,
    Map<String, dynamic> settings,
  ) => _membership(
    circleId,
    uid,
    MembershipsCompanion(settingsJson: Value(jsonEncode(settings))),
  );

  @override
  Future<void> removeMember(String circleId, String uid) => _membership(
    circleId,
    uid,
    const MembershipsCompanion(status: Value('removed')),
  );

  @override
  Future<void> leave(String circleId) => removeMember(circleId, userId);

  @override
  Future<void> transferOwnership(String circleId, String newOwner) async {
    await setRole(circleId, userId, CircleRole.admin);
    await setRole(circleId, newOwner, CircleRole.owner);
  }

  @override
  Future<List<AuditEntry>> auditLog(
    String circleId, {
    Map<String, String> names = const {},
  }) async => audit;
}
