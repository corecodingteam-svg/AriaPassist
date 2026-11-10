import 'dart:convert';

import 'package:aria/core/router/app_router.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/circles/domain/circle.dart';
import 'package:aria/features/lists/organize_providers.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../helpers/fake_billing_api.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

DateTime at(int d, int h, [int m = 0]) =>
    fromWall(DateTime.utc(2026, 11, d, h, m), kTestZone);

Future<void> go(TestApp app, WidgetTester t, String path) async {
  app.container.read(routerProvider).push(path).ignore();
  await t.pumpAndSettle();
}

/// A family circle I own with Dad (dependent) and Asha (admin), active.
Future<String> family(TestApp app, WidgetTester t) async {
  final id = await app.circles.createCircle('Sharma family', CircleType.family);
  await app.circles.addMember(id, 'dad', CircleRole.dependent, name: 'Dad');
  await app.circles.addMember(id, 'asha', CircleRole.admin, name: 'Asha');
  await setPlan(app.db, id, 'family');
  app.container
      .read(appPrefsProvider.notifier)
      .update((p) => p.copyWith(activeCircleId: () => id));
  await t.pumpAndSettle();
  return id;
}

InvitePreview preview({
  CircleRole role = CircleRole.member,
  bool expired = false,
}) => InvitePreview(
  circleId: 'fam-x',
  circleName: 'Rao family',
  circleType: CircleType.family,
  inviterName: 'Meera',
  role: role,
  expired: expired,
  used: false,
  alreadyMember: false,
);

void main() {
  testWidgets('create a family Circle → it becomes active; Me shows it', (
    t,
  ) async {
    final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
    await go(app, t, '/circle');
    expect(find.text('Personal'), findsOneWidget);

    await t.tap(find.byKey(const Key('create-circle')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('circle-name')), 'Sharma family');
    await t.tap(find.byKey(const Key('create-circle-go')));
    await t.pumpAndSettle();

    expect(app.container.read(activeCircleProvider)!.name, 'Sharma family');
    expect(find.text('Members'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);

    // Switch back to personal by tapping it.
    await t.tap(find.text('Personal'));
    await t.pumpAndSettle();
    expect(app.container.read(activeCircleProvider)!.isPersonal, isTrue);
    expect(app.container.read(appPrefsProvider).activeCircleId, isNull);
  });

  testWidgets('invite: pick a role → QR, code, share', (t) async {
    final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
    final id = await family(app, t);
    await go(app, t, '/circle');
    await t.tap(find.byKey(const Key('invite')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(RadioListTile<CircleRole>, 'Dependent'));
    await t.tap(find.byKey(const Key('make-invite')));
    await t.pumpAndSettle();

    expect(app.circles.created.single, (id, CircleRole.dependent));
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Code: tok1'), findsOneWidget);
    expect(find.textContaining('joins as dependent'), findsOneWidget);
  });

  testWidgets('join with a code as a dependent → Simple Mode on', (t) async {
    final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
    app.circles.invites['abc123'] = preview(role: CircleRole.dependent);
    await go(app, t, '/circle');
    await t.tap(find.byKey(const Key('join-code')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'aria:///join/abc123');
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();

    expect(find.text('Rao family'), findsOneWidget);
    expect(find.textContaining('Meera invited you'), findsOneWidget);
    await t.tap(find.byKey(const Key('accept-invite')));
    await t.pumpAndSettle();

    final active = app.container.read(activeCircleProvider)!;
    expect(active.name, 'Rao family');
    expect(active.myRole, CircleRole.dependent);
    expect(app.container.read(simpleModeProvider), isTrue);
    expect(app.container.read(isDependentProvider), isTrue);
  });

  testWidgets('expired invite and full Circle explain themselves', (t) async {
    final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
    app.circles.invites['old'] = preview(expired: true);
    app.circles.invites['full'] = preview();
    await go(app, t, '/join/old');
    expect(find.byKey(const Key('join-problem')), findsOneWidget);
    expect(find.byKey(const Key('accept-invite')), findsNothing);

    app.circles.acceptError = Exception(
      'seat limit reached (upgrade_required)',
    );
    await go(app, t, '/join/full');
    await t.tap(find.byKey(const Key('accept-invite')));
    await t.pumpAndSettle();
    expect(find.textContaining('full on its current plan'), findsOneWidget);
    expect(app.container.read(appPrefsProvider).activeCircleId, isNull);
  });

  testWidgets('assign a reminder to Dad → off my Today, tracked on Circle', (
    t,
  ) async {
    final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
    await family(app, t);
    await t.tap(find.byTooltip('New reminder'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('title-field')), 'BP tablet');
    await t.tap(find.text('Tomorrow'));
    await t.tap(find.textContaining('Morning'));
    await t.dragUntilVisible(
      find.byKey(const Key('assign-dad')),
      find.byType(ListView),
      const Offset(0, -150),
    );
    await t.tap(find.byKey(const Key('assign-dad')));
    await t.pumpAndSettle();
    expect(
      find.textContaining('Share with'),
      findsNothing,
      reason: 'assigned → creator + assignee only',
    );
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    final r = await app.db.select(app.db.reminders).getSingle();
    expect(r.assignedTo, 'dad');
    expect(r.visibility, 'private');
    expect(
      find.text('BP tablet'),
      findsNothing,
      reason: 'it’s Dad’s, not mine',
    );
    await t.pump(const Duration(seconds: 1));
    expect(
      app.gateway.reminderAlerts,
      isEmpty,
      reason: 'only Dad’s phone alerts',
    );

    await go(app, t, '/circle');
    await t.dragUntilVisible(
      find.text('BP tablet'),
      find.byType(ListView),
      const Offset(0, -150),
    );
    expect(find.textContaining('for Dad · pending'), findsOneWidget);
  });

  testWidgets('members can assign only when the owner allows it', (t) async {
    final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
    final id = await family(app, t);
    await app.circles.setRole(id, 'u1', CircleRole.member);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('New reminder'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('assign-dad')), findsNothing);
    await t.dragUntilVisible(
      find.textContaining('Share with Sharma family'),
      find.byType(ListView),
      const Offset(0, -150),
    );
    expect(find.textContaining('Share with Sharma family'), findsOneWidget);
    await t.drag(find.byType(ListView), const Offset(0, 2000));
    await t.pumpAndSettle();

    await app.circles.updateCircleSettings(id, {'members_can_assign': true});
    await t.pumpAndSettle();
    await t.dragUntilVisible(
      find.byKey(const Key('assign-dad')),
      find.byType(ListView),
      const Offset(0, -150),
    );
    expect(find.byKey(const Key('assign-dad')), findsOneWidget);
  });

  testWidgets('a reminder from Asha says so', (t) async {
    final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
    final id = await family(app, t);
    await app.container
        .read(reminderRepositoryProvider)!
        .save(
          Reminder(
            id: 'r1',
            circleId: id,
            createdBy: 'asha',
            assignedTo: 'u1',
            title: 'Pick up Dad’s medicines',
            startAt: at(9, 18),
            timezone: kTestZone,
          ),
        );
    app.container.invalidate(memberNamesProvider);
    await t.pumpAndSettle();
    await t.dragUntilVisible(
      find.text('Pick up Dad’s medicines'),
      find.byType(ListView).first,
      const Offset(0, -120),
    );
    expect(find.textContaining('from Asha'), findsOneWidget);
    await t.tap(find.text('Pick up Dad’s medicines'));
    await t.pumpAndSettle();
    expect(find.text('From'), findsOneWidget);
    expect(find.text('Asha'), findsOneWidget);
  });

  testWidgets('admin locks Simple Mode for Dad with a PIN', (t) async {
    final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
    await family(app, t);
    await go(app, t, '/circle');
    await t.tap(find.byTooltip('Manage Dad'));
    await t.pumpAndSettle();
    await t.tap(find.text('Lock Simple Mode with a PIN'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '4821');
    await t.tap(find.text('Lock'));
    await t.pumpAndSettle();

    final m = await (app.db.select(
      app.db.memberships,
    )..where((x) => x.userId.equals('dad'))).getSingle();
    final lock = SimpleLock.fromJson(
      (jsonDecode(m.settingsJson!) as Map)['simple_lock'],
    );
    expect(lock!.verify('4821'), isTrue);
    expect(find.textContaining('Simple Mode locked'), findsOneWidget);
  });

  testWidgets('dependent: locked Simple Mode needs the PIN to turn off', (
    t,
  ) async {
    final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
    await app.circles.addMember(
      'fam',
      'u1',
      CircleRole.dependent,
      settings: {'simple_lock': SimpleLock.create('4821').toJson()},
    );
    await t.pumpAndSettle();
    expect(
      app.container.read(simpleModeProvider),
      isTrue,
      reason: 'forced on although the pref is off',
    );

    await go(app, t, '/settings/simplify');
    expect(find.textContaining('Turned on by your Circle'), findsOneWidget);
    await t.tap(find.byKey(const Key('simple-mode')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '0000');
    await t.tap(find.text('Unlock'));
    await t.pumpAndSettle();
    expect(find.text('That PIN isn’t right'), findsOneWidget);
    expect(app.container.read(simpleModeProvider), isTrue);

    await t.tap(find.byKey(const Key('simple-mode')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '4821');
    await t.tap(find.text('Unlock'));
    await t.pumpAndSettle();
    expect(app.container.read(simpleModeProvider), isFalse);
  });

  testWidgets('share a note and a list with the Circle', (t) async {
    final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
    final id = await family(app, t);
    final notes = app.container.read(notesRepositoryProvider)!;
    await notes.add('Wifi password is mango42', circleId: id);
    await go(app, t, '/notes');
    await t.tap(find.byTooltip('Share with Circle'));
    await t.pumpAndSettle();
    expect(
      (await app.db.select(app.db.notes).getSingle()).visibility,
      'shared',
    );

    final lists = app.container.read(listsRepositoryProvider)!;
    final listId = await lists.createList('Grocery', circleId: id);
    app.container.read(routerProvider).go('/lists/$listId');
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('List options'));
    await t.pumpAndSettle();
    await t.tap(find.text('Share with Sharma family'));
    await t.pumpAndSettle();
    expect(
      (await app.db.select(app.db.lists).getSingle()).visibility,
      'shared',
    );
  });

  testWidgets('leave a Circle → back to personal', (t) async {
    final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
    final id = await family(app, t);
    await app.circles.transferOwnership(id, 'asha');
    await t.pumpAndSettle();
    await go(app, t, '/circle');
    await t.dragUntilVisible(
      find.byKey(const Key('leave-circle')),
      find.byType(ListView),
      const Offset(0, -150),
    );
    await t.ensureVisible(find.byKey(const Key('leave-circle')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('leave-circle')));
    await t.pumpAndSettle();
    expect(app.container.read(activeCircleProvider)!.isPersonal, isTrue);
    expect(find.text('Sharma family'), findsNothing);
  });
}
