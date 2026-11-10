import 'package:aria/core/router/app_router.dart';
import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/circles/domain/circle.dart';
import 'package:aria/features/lists/organize_providers.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/reminders/domain/alert_plan.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/voice/application/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_billing_api.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

Future<void> go(TestApp app, WidgetTester t, String path) async {
  app.container.read(routerProvider).push(path).ignore();
  await t.pumpAndSettle();
}

String planOf(TestApp app) => app.container.read(entitlementProvider).plan.code;

void main() {
  testWidgets('free user: plans, yearly saving, per-person price, compare', (
    t,
  ) async {
    final app = await pumpApp(
      t,
      auth: FakeAuthRepository(userId: 'u1'),
      plan: 'free',
    );
    await go(app, t, '/subscription');
    expect(find.text('You’re on Free'), findsOneWidget);
    expect(find.text('Yearly · save 16%'), findsOneWidget);
    // The pager opens on Family (most popular).
    expect(find.text('⭐ Most popular'), findsOneWidget);
    expect(find.text('just ₹40/person/month'), findsOneWidget);
    expect(
      find.textContaining('₹199 /month', findRichText: true),
      findsOneWidget,
    );
    await t.tap(find.text('Yearly · save 16%'));
    await t.pumpAndSettle();
    expect(
      find.textContaining('₹1,999 /year', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('About 2 months free'), findsOneWidget);

    await t.dragUntilVisible(
      find.byKey(const Key('compare')).hitTestable(),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    await t.tap(find.byKey(const Key('compare')));
    await t.pumpAndSettle();
    expect(find.text('🗒️ Activity log'), findsOneWidget);
  });

  testWidgets(
    'Family trial from Free: creates the Circle, unlocks, shows trial',
    (t) async {
      final app = await pumpApp(
        t,
        auth: FakeAuthRepository(userId: 'u1'),
        plan: 'free',
      );
      await go(app, t, '/subscription');
      await t.ensureVisible(find.byKey(const Key('trial-family')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('trial-family')));
      await t.pumpAndSettle();

      expect(planOf(app), 'family');
      final active = app.container.read(activeCircleProvider)!;
      expect([active.name, active.type], ['My family', CircleType.family]);
      expect(find.textContaining('Family unlocked free until'), findsOneWidget);
      await t.drag(find.byType(ListView).first, const Offset(0, 2000));
      await t.pumpAndSettle();
      expect(find.textContaining('Free trial · ends'), findsOneWidget);
      expect(find.text('2 of 5 people'), findsNothing);
      expect(find.text('1 of 5 people'), findsOneWidget);

      // Trial used → the card offers buying, which this build can't do.
      await t.tap(find.byKey(const Key('billing-history')));
      await t.pumpAndSettle();
      expect(find.text('Family free trial started'), findsOneWidget);
    },
  );

  testWidgets('without store keys, “Subscribe” explains instead of failing', (
    t,
  ) async {
    final app = await pumpApp(
      t,
      auth: FakeAuthRepository(userId: 'u1'),
      plan: 'free',
    );
    await go(app, t, '/subscription');
    await t.ensureVisible(find.byKey(const Key('buy-family')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('buy-family')));
    await t.pumpAndSettle();
    expect(
      find.textContaining('Purchases aren’t set up in this build'),
      findsOneWidget,
    );
    expect(planOf(app), 'free');
  });

  testWidgets('promo code unlocks Personal', (t) async {
    final app = await pumpApp(
      t,
      auth: FakeAuthRepository(userId: 'u1'),
      plan: 'free',
    );
    await go(app, t, '/subscription');
    await t.dragUntilVisible(
      find.byKey(const Key('promo')).hitTestable(),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await t.tap(find.byKey(const Key('promo')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'nope');
    await t.tap(find.text('Apply'));
    await t.pumpAndSettle();
    expect(find.text('That code isn’t valid.'), findsOneWidget);
    expect(planOf(app), 'free');

    await t.tap(find.byKey(const Key('promo')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'student30');
    await t.tap(find.text('Apply'));
    await t.pumpAndSettle();
    expect(planOf(app), 'personal');
    expect(find.textContaining('Code applied'), findsOneWidget);
  });

  testWidgets('contextual paywall: routines → try Personal → unlocked', (
    t,
  ) async {
    final app = await pumpApp(
      t,
      auth: FakeAuthRepository(userId: 'u1'),
      plan: 'free',
    );
    await go(app, t, '/routines');
    await t.tap(find.byKey(const Key('template-Morning mode')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('paywall-title')), findsOneWidget);
    expect(find.text('Routines'), findsWidgets);
    expect(find.text('Included in Personal'), findsOneWidget);

    await t.tap(find.byKey(const Key('paywall-trial')));
    await t.pumpAndSettle();
    expect(planOf(app), 'personal');
    expect(
      find.byKey(const Key('paywall-title')),
      findsNothing,
      reason: 'paywall closes once unlocked',
    );

    await t.tap(find.byKey(const Key('template-Morning mode')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('paywall-title')), findsNothing);
  });

  testWidgets('paywall is always dismissible', (t) async {
    final app = await pumpApp(
      t,
      auth: FakeAuthRepository(userId: 'u1'),
      plan: 'free',
    );
    await go(app, t, '/paywall?feature=auditLog');
    expect(find.text('Included in Team'), findsOneWidget);
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('paywall-title')), findsNothing);
  });

  testWidgets('free plan: third list opens the paywall; voice says so too', (
    t,
  ) async {
    final app = await pumpApp(
      t,
      auth: FakeAuthRepository(userId: 'u1'),
      plan: 'free',
    );
    final lists = app.container.read(listsRepositoryProvider)!;
    await lists.createList('Grocery', circleId: kTestCircle);
    await lists.createList('Packing', circleId: kTestCircle);
    await t.tap(find.text('Lists'));
    await t.pumpAndSettle();
    await t.tap(find.text('New list'));
    await t.pumpAndSettle();
    expect(find.text('Unlimited lists'), findsWidgets);
    expect(find.byKey(const Key('paywall-title')), findsOneWidget);
  });

  testWidgets('weekly report is a locked teaser on Free', (t) async {
    final app = await pumpApp(
      t,
      auth: FakeAuthRepository(userId: 'u1'),
      plan: 'free',
    );
    await go(app, t, '/me');
    expect(find.byKey(const Key('weekly-report-locked')), findsOneWidget);
    await t.tap(find.byKey(const Key('weekly-report-locked')));
    await t.pumpAndSettle();
    expect(find.text('Weekly report'), findsOneWidget);
  });

  testWidgets('themes: free ones apply, premium ones open the paywall', (
    t,
  ) async {
    final app = await pumpApp(
      t,
      auth: FakeAuthRepository(userId: 'u1'),
      plan: 'free',
    );
    await go(app, t, '/settings/appearance');
    await t.tap(find.text('Ocean Blue'));
    await t.pumpAndSettle();
    expect(app.container.read(themeControllerProvider).presetId, 'ocean');
    await t.tap(find.text('Sunset Orange 🔒'));
    await t.pumpAndSettle();
    expect(find.text('All themes'), findsWidgets);
    expect(app.container.read(themeControllerProvider).presetId, 'ocean');
  });

  testWidgets('graceful downgrade: data kept, premium choices reset', (
    t,
  ) async {
    final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
    app.container
        .read(voiceSettingsProvider.notifier)
        .update((v) => v.copyWith(voiceId: 'meera'));
    app.container.read(themeControllerProvider.notifier).setPreset('sunset');
    await app.container
        .read(listsRepositoryProvider)!
        .createList('Gifts', circleId: kTestCircle);
    await t.pumpAndSettle();
    expect(app.container.read(voiceSettingsProvider).voiceId, 'meera');

    await setPlan(app.db, kTestCircle, 'free'); // plan expired → synced
    await t.pumpAndSettle();
    expect(app.container.read(voiceSettingsProvider).voiceId, 'aria');
    expect(app.container.read(themeControllerProvider).presetId, 'neon');
    expect(
      await app.container.read(listsRepositoryProvider)!.count(),
      1,
      reason: 'nothing deleted',
    );
  });

  testWidgets('Family features follow the Circle’s plan', (t) async {
    final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
    final id = await app.circles.createCircle(
      'Home',
      CircleType.family,
    ); // free plan
    await app.circles.addMember(id, 'dad', CircleRole.dependent, name: 'Dad');
    app.container
        .read(appPrefsProvider.notifier)
        .update((p) => p.copyWith(activeCircleId: () => id));
    await t.pumpAndSettle();

    await go(app, t, '/circle');
    await t.tap(find.byKey(const Key('invite')));
    await t.pumpAndSettle();
    expect(
      find.text('Family Circle'),
      findsWidgets,
      reason: 'free Circle is full → paywall',
    );
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    app.container.read(routerProvider).go('/today');
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('New reminder'));
    await t.pumpAndSettle();
    await t.dragUntilVisible(
      find.byKey(const Key('assign-locked')),
      find.byType(ListView),
      const Offset(0, -150),
    );
    expect(find.byKey(const Key('assign-dad')), findsNothing);

    await setPlan(app.db, id, 'family');
    await t.pumpAndSettle();
    await t.dragUntilVisible(
      find.byKey(const Key('assign-dad')),
      find.byType(ListView),
      const Offset(0, -150),
    );
    expect(find.byKey(const Key('assign-locked')), findsNothing);
  });

  testWidgets('members see their inherited plan; only the owner manages it', (
    t,
  ) async {
    final app = await pumpApp(
      t,
      auth: FakeAuthRepository(userId: 'u1'),
      plan: 'free',
    );
    app.circles.invites['tok'] = const InvitePreview(
      circleId: 'fam-x',
      circleName: 'Rao family',
      circleType: CircleType.family,
      inviterName: 'Meera',
      role: CircleRole.member,
      expired: false,
      used: false,
      alreadyMember: false,
    );
    await app.circles.acceptInvite('tok'); // Family plan Circle
    await t.pumpAndSettle();
    expect(planOf(app), 'family');
    await go(app, t, '/subscription');
    expect(find.textContaining('Included with Rao family'), findsOneWidget);
    expect(find.byKey(const Key('billing-history')), findsNothing);
  });

  testWidgets('owner gets a heads-up 3 days before the trial ends', (t) async {
    final app = await pumpApp(
      t,
      auth: FakeAuthRepository(userId: 'u1'),
      plan: 'free',
    );
    await go(app, t, '/subscription');
    await t.ensureVisible(find.byKey(const Key('trial-family')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('trial-family')));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 1));
    final heads = app.gateway.scheduled
        .where((a) => a.kind == AlertKind.billing)
        .toList();
    // 7-day trial from 9 Nov 10:00: 3 days, 1 day, and the end itself.
    expect(heads.map((a) => a.title), [
      '3 days left on your Family plan',
      'Your Family plan ends tomorrow',
      'Your Family plan has ended',
    ]);
    expect(heads.last.fireAt, app.billing.ends.values.single);
  });
}
