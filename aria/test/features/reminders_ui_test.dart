import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

DateTime at(int d, int h, [int m = 0]) =>
    fromWall(DateTime.utc(2026, 11, d, h, m), kTestZone);

Reminder rem(
  String id,
  String title,
  DateTime start, {
  ReminderCategory cat = ReminderCategory.personal,
  String? rrule,
}) => Reminder(
  id: id,
  circleId: kTestCircle,
  createdBy: 'u1',
  title: title,
  category: cat,
  startAt: start,
  rrule: rrule,
  timezone: kTestZone,
);

void main() {
  testWidgets('create a reminder with the editor (2 taps + title)', (
    tester,
  ) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));

    await tester.tap(find.byTooltip('New reminder'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('title-field')),
      'Pay electricity bill',
    );
    await tester.tap(find.text('Tomorrow'));
    await tester.tap(find.textContaining('Morning'));
    // The focused title field would scroll itself back into view.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monthly'));
    await tester.dragUntilVisible(
      find.text('💰 Bills').hitTestable(),
      find.byType(ListView),
      const Offset(0, -150),
    );
    await tester.tap(find.text('💰 Bills'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.widgetWithText(TextField, 'Amount (for bills)').hitTestable(),
      find.byType(ListView),
      const Offset(0, -150),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Amount (for bills)'),
      '1840',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final r = await app.db.select(app.db.reminders).getSingle();
    expect(r.title, 'Pay electricity bill');
    expect(r.category, 'bills');
    expect(r.rrule, 'FREQ=MONTHLY');
    expect(r.amount, 1840);
    expect(r.startAt!.toUtc(), at(10, 8));
    expect(
      find.textContaining('Done! I’ll remind you Tomorrow'),
      findsOneWidget,
    );

    // Back on Today, in "Coming up", with the plain-language repeat.
    expect(find.text('Pay electricity bill'), findsOneWidget);
    expect(find.textContaining('Every month on the 10th'), findsOneWidget);
    expect(find.textContaining('₹1,840'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(app.gateway.reminderAlerts.first.fireAt, at(10, 8));
  });

  testWidgets('editor rejects an empty title and a time in the past', (
    tester,
  ) async {
    await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    await tester.tap(find.byTooltip('New reminder'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('What should I remind you about?'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('title-field')), 'Too late');
    await tester.tap(find.text('Today'));
    await tester.tap(find.textContaining('Morning')); // 8 AM < 10 AM now
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('already passed'), findsOneWidget);
  });

  testWidgets('Today sections, category chips, and swipe → done → undo', (
    tester,
  ) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    final repo = app.container.read(reminderRepositoryProvider)!;
    await repo.save(rem('a', 'Call plumber', at(9, 9, 45)));
    await repo.save(
      rem(
        'b',
        'Vitamin D',
        at(9, 10, 30),
        cat: ReminderCategory.health,
        rrule: 'FREQ=DAILY',
      ),
    );
    await repo.save(
      rem('c', 'Pay rent', at(9, 18), cat: ReminderCategory.bills),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('3 to do'), findsOneWidget);
    final list = find.byType(ListView).first;
    for (final header in ['Overdue · 1', 'Now · 1', 'Later today · 1']) {
      await tester.dragUntilVisible(
        find.text(header),
        list,
        const Offset(0, -120),
      );
      expect(find.text(header), findsOneWidget);
    }
    await tester.drag(list, const Offset(0, 2000)); // back to top
    await tester.pumpAndSettle();

    await tester.tap(find.text('💊 Health'));
    await tester.pumpAndSettle();
    expect(find.text('Pay rent'), findsNothing);
    expect(find.text('Vitamin D'), findsOneWidget);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).first, const Offset(0, 300));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Vitamin D'),
      find.byType(ListView).first,
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    // Swipe right on the recurring pill → done today, next one tomorrow.
    await tester.drag(find.text('Vitamin D'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('That’s done'), findsOneWidget);
    expect(find.text('Done today · 1'), findsOneWidget);
    expect((await repo.get('b'))!.startAt, at(10, 10, 30));

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect((await repo.get('b'))!.startAt, at(9, 10, 30));
    expect(find.text('Done today · 1'), findsNothing);
  });

  testWidgets('swipe left snoozes 15 minutes', (tester) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    final repo = app.container.read(reminderRepositoryProvider)!;
    await repo.save(rem('a', 'Stretch', at(9, 10, 5)));
    await tester.pumpAndSettle();

    await tester.drag(find.text('Stretch'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(
      (await repo.get('a'))!.snoozedUntil,
      kTestNow.add(const Duration(minutes: 15)),
    );
    expect(find.textContaining('I’ll remind you'), findsOneWidget);
  });

  testWidgets('detail screen: snooze sheet and delete with undo', (
    tester,
  ) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    final repo = app.container.read(reminderRepositoryProvider)!;
    await repo.save(rem('a', 'Water plants', at(9, 11)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Water plants'));
    await tester.pumpAndSettle();
    // intl puts a narrow no-break space before AM.
    expect(find.textContaining('Today, 11:00'), findsOneWidget);

    await tester.tap(find.text('Snooze'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('After lunch'));
    await tester.pumpAndSettle();
    expect((await repo.get('a'))!.snoozedUntil, at(9, 14));

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Water plants'), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Water plants'), findsOneWidget);
  });

  testWidgets('missed reminders surface on Today and can be rescheduled', (
    tester,
  ) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    final repo = app.container.read(reminderRepositoryProvider)!;
    await repo.save(rem('a', 'Morning walk', at(9, 6)));
    await app.container.read(reminderServiceProvider)!.refresh();
    await tester.pumpAndSettle();

    expect(find.text('You missed 1 reminder'), findsOneWidget);
    await tester.tap(find.text('You missed 1 reminder'));
    await tester.pumpAndSettle();
    expect(find.text('Morning walk'), findsOneWidget);
    await tester.tap(find.text('Remind in 1 h'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing missed'), findsOneWidget);
    expect(
      (await repo.get('a'))!.startAt,
      kTestNow.add(const Duration(hours: 1)),
    );
  });

  testWidgets('search finds reminders', (tester) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    await app.container
        .read(reminderRepositoryProvider)!
        .save(rem('a', 'Renew passport', at(20, 10)));
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'passp');
    await tester.pumpAndSettle();
    expect(find.text('Renew passport'), findsOneWidget);
  });

  testWidgets('permission banner appears when notifications are off', (
    tester,
  ) async {
    final app = await pumpApp(tester, auth: FakeAuthRepository(userId: 'u1'));
    app.gateway.current = const NotificationStatusOff();
    app.container.invalidate(notificationStatusProvider);
    await tester.pumpAndSettle();
    expect(find.text('Notifications are off'), findsOneWidget);
    await tester.tap(find.text('Fix'));
    await tester.pumpAndSettle();
    expect(find.text('Notifications are off'), findsNothing);
  });
}
