import 'package:aria/data/local/app_database.dart';
import 'package:aria/data/sync/local_store.dart';
import 'package:aria/features/circles/data/circle_repository.dart';
import 'package:aria/features/circles/domain/circle.dart';
import 'package:aria/features/reminders/data/reminder_repository.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_circle_api.dart';
import '../helpers/pump_app.dart';

Circle circle(
  CircleRole role, {
  CircleType type = CircleType.family,
  bool membersAssign = false,
}) => Circle(
  id: 'c',
  name: 'Home',
  type: type,
  ownerId: 'o',
  myRole: role,
  settings: {'members_can_assign': membersAssign},
);

void main() {
  group('SimpleLock', () {
    test('verifies only the right PIN; stores no PIN', () {
      final lock = SimpleLock.create('4821', salt: 'abc');
      expect(lock.verify('4821'), isTrue);
      expect(lock.verify('4822'), isFalse);
      expect(lock.toJson().toString(), isNot(contains('4821')));
      final back = SimpleLock.fromJson(lock.toJson())!;
      expect(back.verify('4821'), isTrue);
    });

    test('salt changes the hash', () {
      expect(
        SimpleLock.create('1111', salt: 'a').pinHash,
        isNot(SimpleLock.create('1111', salt: 'b').pinHash),
      );
    });

    test('fromJson tolerates junk', () {
      expect(SimpleLock.fromJson(null), isNull);
      expect(SimpleLock.fromJson({'salt': 'x'}), isNull);
      expect(SimpleLock.fromJson('nope'), isNull);
    });
  });

  test('canAssign mirrors the server rule', () {
    expect(circle(CircleRole.owner).canAssign, isTrue);
    expect(circle(CircleRole.admin).canAssign, isTrue);
    expect(circle(CircleRole.member).canAssign, isFalse);
    expect(circle(CircleRole.member, membersAssign: true).canAssign, isTrue);
    expect(
      circle(CircleRole.dependent, membersAssign: true).canAssign,
      isFalse,
    );
    expect(
      circle(CircleRole.owner, type: CircleType.personal).canAssign,
      isFalse,
    );
  });

  test('server errors become friendly messages', () {
    expect(
      circleErrorMessage(Exception('seat limit reached; upgrade_required')),
      contains('upgrade'),
    );
    expect(
      circleErrorMessage(Exception('invite expired')),
      contains('expired'),
    );
    expect(
      circleErrorMessage(Exception('invite already used')),
      contains('already used'),
    );
    expect(
      circleErrorMessage(Exception('invite not found')),
      contains('doesn’t exist'),
    );
    expect(
      circleErrorMessage(Exception('owner must transfer ownership')),
      contains('owner'),
    );
    expect(circleErrorMessage(Exception('socket')), contains('connection'));
  });

  test('invite preview usability and links', () {
    const p = InvitePreview(
      circleId: 'c',
      circleName: 'Home',
      circleType: CircleType.family,
      inviterName: 'Asha',
      role: CircleRole.member,
      expired: false,
      used: false,
      alreadyMember: false,
    );
    expect(p.usable, isTrue);
    expect(inviteLink('t0k'), 'aria:///join/t0k');
  });

  test('audit entries read naturally', () {
    final at = DateTime.utc(2026, 11, 9);
    expect(
      AuditEntry(
        action: 'reminder.assigned',
        at: at,
        actorName: 'Asha',
        targetName: 'Dad',
        detail: 'BP tablet',
      ).describe(),
      'Asha assigned “BP tablet” to Dad',
    );
    expect(
      AuditEntry(
        action: 'member.removed',
        at: at,
        actorName: 'You',
        targetName: 'Ravi',
      ).describe(),
      'You removed Ravi',
    );
  });

  group('repository', () {
    late AppDatabase db;
    late FakeCircleApi api;
    late CircleRepository repo;
    setUpAll(ensureTimeZones);
    setUp(() async {
      db = memoryDb();
      await seedCircle(db, 'me');
      api = FakeCircleApi(db, 'me');
      repo = CircleRepository(db, userId: 'me');
    });
    tearDown(() => db.close());

    test('my circles: personal first, member counts, roles', () async {
      final fam = await api.createCircle('Sharma family', CircleType.family);
      await api.addMember(fam, 'dad', CircleRole.dependent, name: 'Dad');
      await api.addMember(fam, 'asha', CircleRole.admin, name: 'Asha');
      final cs = await repo.watchMyCircles().first;
      expect(cs.map((c) => c.name), ['Personal', 'Sharma family']);
      expect(cs[1].memberCount, 3);
      expect(cs[1].myRole, CircleRole.owner);
    });

    test('members: "You", sorted by role; removed members disappear', () async {
      final fam = await api.createCircle('Home', CircleType.family);
      await api.addMember(fam, 'dad', CircleRole.dependent, name: 'Dad');
      await api.addMember(fam, 'asha', CircleRole.admin, name: 'Asha');
      var ms = await repo.watchMembers(fam).first;
      expect(ms.map((m) => m.name), ['You', 'Asha', 'Dad']);
      await api.removeMember(fam, 'asha');
      ms = await repo.watchMembers(fam).first;
      expect(ms.map((m) => m.name), ['You', 'Dad']);
    });

    test('leaving hides the circle', () async {
      final fam = await api.createCircle('Home', CircleType.family);
      await api.setRole(fam, 'me', CircleRole.member);
      await api.leave(fam);
      expect((await repo.watchMyCircles().first).map((c) => c.id), [
        kTestCircle,
      ]);
    });

    test('my simple lock comes from my membership settings', () async {
      expect(await repo.watchMySimpleLock().first, isNull);
      await api.addMember(
        'fam',
        'me',
        CircleRole.dependent,
        settings: {'simple_lock': SimpleLock.create('1234').toJson()},
      );
      final lock = await repo.watchMySimpleLock().first;
      expect(lock!.verify('1234'), isTrue);
    });

    test('reminders I assigned to others', () async {
      final r = ReminderRepository(db, LocalStore(db), userId: 'me');
      Reminder rem(String id, {String? to, String by = 'me'}) => Reminder(
        id: id,
        circleId: 'fam',
        createdBy: by,
        title: id,
        assignedTo: to,
        startAt: DateTime.utc(2026, 11, 10),
        timezone: kTestZone,
      );
      await r.save(rem('for-dad', to: 'dad'));
      await r.save(rem('for-me', to: 'me'));
      await r.save(rem('mine'));
      await r.save(rem('from-asha', to: 'dad', by: 'asha'));
      final assigned = await r.watchAssignedByMe('fam').first;
      expect(assigned.map((x) => x.id), ['for-dad']);
    });
  });
}
