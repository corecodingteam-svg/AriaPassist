import 'dart:convert';

import 'package:aria/l10n/tr.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

enum CircleType {
  personal('🙂', 'Personal'),
  family('👪', 'Family'),
  team('💼', 'Team');

  CircleType(this.emoji, this._label);
  final String emoji;
  final String _label;
  String get label => tr(_label);
  static CircleType parse(String? s) =>
      values.asNameMap()[s] ?? CircleType.personal;
}

enum CircleRole {
  owner('Owner', 'Billing, members and everything else'),
  admin('Admin', 'Manage members, assign reminders, lock Simple Mode'),
  member('Member', 'Own and shared items'),
  dependent('Dependent', 'Child or elder: simple app, receives reminders');

  CircleRole(this._label, this._description);
  final String _label;
  String get label => tr(_label);
  final String _description;
  String get description => tr(_description);
  static CircleRole parse(String? s) =>
      values.asNameMap()[s] ?? CircleRole.member;

  bool get canManage => this == owner || this == admin;
}

@immutable
class Circle {
  const Circle({
    required this.id,
    required this.name,
    required this.type,
    required this.ownerId,
    required this.myRole,
    this.settings = const {},
    this.memberCount = 1,
    this.planId,
  });

  final String id;
  final String name;
  final CircleType type;
  final String ownerId;
  final CircleRole myRole;
  final Map<String, dynamic> settings;
  final int memberCount;

  /// `plans.id` (server-derived from the Circle's subscriptions).
  final String? planId;

  bool get isPersonal => type == CircleType.personal;
  bool get membersCanAssign => settings['members_can_assign'] == true;

  /// Whether I may assign reminders to others here (mirrors can_assign()).
  bool get canAssign =>
      !isPersonal &&
      (myRole.canManage || (myRole == CircleRole.member && membersCanAssign));
}

@immutable
class Member {
  const Member({
    required this.userId,
    required this.name,
    required this.role,
    this.settings = const {},
  });

  final String userId;
  final String name;
  final CircleRole role;
  final Map<String, dynamic> settings;

  /// Admin-set Simple Mode lock on a dependent.
  SimpleLock? get simpleLock => SimpleLock.fromJson(settings['simple_lock']);
}

/// Simple Mode PIN lock. Only a salted hash is stored (in the membership
/// row, which the dependent can read but not change — RLS).
@immutable
class SimpleLock {
  const SimpleLock({required this.salt, required this.pinHash});

  factory SimpleLock.create(String pin, {String? salt}) {
    final s = salt ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return SimpleLock(salt: s, pinHash: _hash(s, pin));
  }

  static SimpleLock? fromJson(Object? j) => j is Map && j['pin_hash'] is String
      ? SimpleLock(
          salt: j['salt'] as String? ?? '',
          pinHash: j['pin_hash'] as String,
        )
      : null;

  final String salt;
  final String pinHash;

  static String _hash(String salt, String pin) =>
      sha256.convert(utf8.encode('aria-simple-lock|$salt|$pin')).toString();

  bool verify(String pin) => _hash(salt, pin) == pinHash;

  Map<String, dynamic> toJson() => {'salt': salt, 'pin_hash': pinHash};
}

@immutable
class InvitePreview {
  const InvitePreview({
    required this.circleId,
    required this.circleName,
    required this.circleType,
    required this.inviterName,
    required this.role,
    required this.expired,
    required this.used,
    required this.alreadyMember,
  });

  final String circleId;
  final String circleName;
  final CircleType circleType;
  final String? inviterName;
  final CircleRole role;
  final bool expired;
  final bool used;
  final bool alreadyMember;

  bool get usable => !expired && !used && !alreadyMember;
}

@immutable
class AuditEntry {
  const AuditEntry({
    required this.action,
    required this.at,
    this.actorName,
    this.targetName,
    this.detail,
  });
  final String action;
  final DateTime at;
  final String? actorName;
  final String? targetName;
  final String? detail;

  String describe() {
    final who = actorName ?? tr('Someone');
    final whom = targetName ?? tr('a member');
    return switch (action) {
      'member.added' => tr('{0} added {1}', [who, whom]),
      'member.removed' => tr('{0} removed {1}', [who, whom]),
      'member.role_changed' => tr('{0} changed {1}’s role{2}', [
        who,
        whom,
        detail == null ? '' : ' to $detail',
      ]),
      'reminder.assigned' => tr('{0} assigned “{1}” to {2}', [
        who,
        detail ?? 'a reminder',
        whom,
      ]),
      'circle.ownership_transferred' => tr('{0} made {1} the owner', [
        who,
        whom,
      ]),
      _ => '$who: $action',
    };
  }
}

/// Invite link shared over WhatsApp/SMS/QR.
String inviteLink(String token) => 'aria:///join/$token';

/// Friendly failure for joining/inviting.
String circleErrorMessage(Object e) {
  final s = e.toString();
  if (s.contains('upgrade_required') || s.contains('seat limit')) {
    return tr(
      'This Circle is full on its current plan. Ask the owner to upgrade to add more people.',
    );
  }
  if (s.contains('expired')) {
    return tr('This invite has expired. Ask for a new one.');
  }
  if (s.contains('already used')) {
    return tr('This invite was already used. Ask for a new one.');
  }
  if (s.contains('not found')) return tr('That invite code doesn’t exist.');
  if (s.contains('owner must transfer')) {
    return tr('Make someone else the owner before leaving.');
  }
  return tr('Something went wrong. Check your connection and try again.');
}
