import 'dart:convert';

import 'package:aria/data/local/app_database.dart';
import 'package:aria/features/circles/domain/circle.dart';
import 'package:drift/drift.dart';

/// Local (synced) view of my Circles and their members.
class CircleRepository {
  CircleRepository(this.db, {required this.userId});
  final AppDatabase db;
  final String userId;

  static Map<String, dynamic> _json(String? s) {
    if (s == null) return const {};
    try {
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    } on Object {
      return const {};
    }
  }

  /// Circles I'm an active member of, personal first.
  Stream<List<Circle>> watchMyCircles() {
    final q =
        db.select(db.memberships).join([
          innerJoin(
            db.circles,
            db.circles.id.equalsExp(db.memberships.circleId),
          ),
        ])..where(
          db.memberships.userId.equals(userId) &
              db.memberships.status.equals('active') &
              db.memberships.deletedAt.isNull() &
              db.circles.deletedAt.isNull(),
        );
    // The join already watches `memberships`, so any membership change
    // re-runs it; counts are a one-shot read per emission. (asyncExpand
    // over a second live stream would buffer every later emission forever.)
    final counts = db.select(db.memberships)
      ..where((m) => m.status.equals('active') & m.deletedAt.isNull());
    return q.watch().asyncMap(
      (rows) => counts.get().then((all) {
        final circles =
            [
              for (final r in rows)
                () {
                  final c = r.readTable(db.circles);
                  final m = r.readTable(db.memberships);
                  return Circle(
                    id: c.id,
                    name: c.name,
                    type: CircleType.parse(c.type),
                    ownerId: c.ownerId,
                    myRole: CircleRole.parse(m.role),
                    settings: _json(c.settingsJson),
                    memberCount: all.where((x) => x.circleId == c.id).length,
                    planId: c.planId,
                  );
                }(),
            ]..sort((a, b) {
              if (a.isPersonal != b.isPersonal) return a.isPersonal ? -1 : 1;
              return a.name.compareTo(b.name);
            });
        return circles;
      }),
    );
  }

  /// Active members with display names, owners/admins first.
  Stream<List<Member>> watchMembers(String circleId) {
    final q =
        db.select(db.memberships).join([
          leftOuterJoin(db.users, db.users.id.equalsExp(db.memberships.userId)),
        ])..where(
          db.memberships.circleId.equals(circleId) &
              db.memberships.status.equals('active') &
              db.memberships.deletedAt.isNull(),
        );
    return q.watch().map((rows) {
      final members = [
        for (final r in rows)
          () {
            final m = r.readTable(db.memberships);
            final u = r.readTableOrNull(db.users);
            return Member(
              userId: m.userId,
              name: m.userId == userId ? 'You' : (u?.name ?? 'Member'),
              role: CircleRole.parse(m.role),
              settings: _json(m.settingsJson),
            );
          }(),
      ]..sort((a, b) => a.role.index.compareTo(b.role.index));
      return members;
    });
  }

  /// user id → display name across all my circles (for labels).
  Future<Map<String, String>> names() async {
    final rows = await db.select(db.users).get();
    return {
      for (final u in rows) u.id: u.id == userId ? 'You' : (u.name ?? 'Member'),
    };
  }

  /// My strictest Simple Mode lock across circles (set by an admin).
  Stream<SimpleLock?> watchMySimpleLock() =>
      (db.select(db.memberships)..where(
            (m) =>
                m.userId.equals(userId) &
                m.status.equals('active') &
                m.deletedAt.isNull(),
          ))
          .watch()
          .map(
            (rows) => rows
                .map(
                  (m) =>
                      SimpleLock.fromJson(_json(m.settingsJson)['simple_lock']),
                )
                .whereType<SimpleLock>()
                .firstOrNull,
          );
}
