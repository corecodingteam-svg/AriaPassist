import 'package:aria/core/router/app_router.dart';
import 'package:aria/features/lists/organize_providers.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/reminder_logic.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/routines/domain/routine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

DateTime at(int d, int h, [int m = 0]) =>
    fromWall(DateTime.utc(2026, 11, d, h, m), kTestZone);

Future<void> go(TestApp app, WidgetTester t, String path) async {
  app.container.read(routerProvider).push(path).ignore();
  await t.pumpAndSettle();
}

String reply(WidgetTester t) =>
    t.widget<Text>(find.byKey(const Key('talk-reply'))).data!;

void main() {
  testWidgets('create a list, add items in one go, check off, quantity', (
    tester,
  ) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    await tester.tap(find.text('Lists'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New list'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🛒 Grocery'));
    await tester.tap(find.byKey(const Key('create-list')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('add-item')),
      'milk, eggs and bread',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('milk'), findsOneWidget);
    expect(find.text('bread'), findsOneWidget);

    await tester.tap(find.byTooltip('More milk'));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.text('eggs'));
    await tester.pumpAndSettle();
    expect(find.text('Checked · 1'), findsOneWidget);

    final list =
        (await app.container.read(listsRepositoryProvider)!.watchLists().first)
            .single;
    expect(list.name, 'Grocery');
    expect(list.openCount, 2);
  });

  testWidgets('voice: list items, notes (ask + forget), routines', (
    tester,
  ) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    Future<void> say(String s) async {
      if (!app.speech.listening) {
        await tester.tap(find.byTooltip('Speak'));
        await tester.pumpAndSettle();
      }
      app.speech.say(s);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.bySemanticsLabel('Talk to Aria'));
    await tester.pumpAndSettle();

    await say('add milk and eggs to grocery list');
    expect(reply(tester), 'Added milk and eggs to your grocery list.');
    final lists = await app.container
        .read(listsRepositoryProvider)!
        .watchLists()
        .first;
    expect(lists.single.preview, ['Milk', 'Eggs']);

    await say('note that the wifi password is sunflower42');
    expect(reply(tester), "Got it, I'll remember that.");
    await say("what's the wifi password");
    expect(reply(tester), 'The wifi password is sunflower42');
    await say('forget that note');
    expect(reply(tester), contains('I forgot'));
    expect(
      await app.container.read(notesRepositoryProvider)!.allNotes(),
      isEmpty,
    );

    final repo = app.container.read(routinesRepositoryProvider)!;
    final t = Routine.templates.first;
    await repo.save(
      repo.create(t.$1, circleId: kTestCircle, emoji: t.$2, steps: t.$3),
    );
    await say('start morning mode');
    expect(
      find.text('☀️ Morning mode'),
      findsOneWidget,
      reason: 'runner opened',
    );
    expect(app.speaker.spoken.last, contains('First: Drink a glass of water'));
  });

  testWidgets('routine runner: tick every step → done, run recorded', (
    tester,
  ) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    final repo = app.container.read(routinesRepositoryProvider)!;
    final r = repo.create(
      'Leaving home',
      circleId: kTestCircle,
      steps: const [RoutineStep('Lights off'), RoutineStep('Keys')],
    );
    await repo.save(r);
    await go(app, tester, '/routine/${r.id}');
    await tester.tap(find.text('Lights off'));
    await tester.pumpAndSettle();
    expect(app.speaker.spoken.last, 'Next: Keys.');
    await tester.tap(find.text('Keys'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('routine-done')), findsOneWidget);
    expect((await repo.get(r.id))!.runs, hasLength(1));
  });

  testWidgets('people: add with phone + birthday → contact actions', (
    tester,
  ) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    await go(app, tester, '/people');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('person-name')), 'Dad');
    await tester.enterText(find.byKey(const Key('person-phone')), '9876543210');
    await tester.tap(find.text('Every 2 weeks'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Dad'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.textContaining('Time to call'), findsOneWidget);
    final reminders = await app.container
        .read(reminderRepositoryProvider)!
        .activeMine();
    expect(reminders.single.title, 'Call Dad');
  });

  testWidgets('bills screen totals this month', (tester) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    final repo = app.container.read(reminderRepositoryProvider)!;
    Reminder bill(String id, String t, double amt, DateTime d) => Reminder(
      id: id,
      circleId: kTestCircle,
      createdBy: 'u1',
      title: t,
      category: ReminderCategory.bills,
      amount: amt,
      startAt: d,
      timezone: kTestZone,
    );
    await repo.save(bill('a', 'Electricity', 1840, at(20, 10)));
    await repo.save(bill('b', 'Rent', 15000, at(9, 11)));
    await repo.apply(
      ReminderLogic.complete((await repo.get('b'))!, 'u1', at(9, 10, 30)),
    );
    await go(app, tester, '/bills');
    expect(find.text('₹1,840'), findsWidgets);
    expect(find.text('₹15,000'), findsWidgets);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Paid'), findsWidgets);
  });

  testWidgets('weekly report on Me; search finds notes and list items', (
    tester,
  ) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    final repo = app.container.read(reminderRepositoryProvider)!;
    await repo.save(
      Reminder(
        id: 'p',
        circleId: kTestCircle,
        createdBy: 'u1',
        title: 'Vitamin D',
        rrule: 'FREQ=DAILY',
        startAt: at(9, 9, 45),
        timezone: kTestZone,
      ),
    );
    await repo.apply(
      ReminderLogic.complete((await repo.get('p'))!, 'u1', at(9, 10)),
    );
    await app.container
        .read(notesRepositoryProvider)!
        .add('Locker code 4471', circleId: kTestCircle);
    final lists = app.container.read(listsRepositoryProvider)!;
    await lists.addItems(
      await lists.createList('Packing', circleId: kTestCircle),
      ['Locker key'],
    );

    await go(app, tester, '/me');
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    await go(app, tester, '/search');
    await tester.enterText(find.byType(TextField), 'locker');
    await tester.pumpAndSettle();
    expect(find.text('Locker code 4471'), findsOneWidget);
    expect(find.text('Locker key'), findsOneWidget);
  });
}
