import 'package:aria_admin/core/providers.dart';
import 'package:aria_admin/core/router.dart';
import 'package:aria_admin/data/admin_api.dart';
import 'package:aria_admin/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'fakes.dart';

Future<(FakeAuth, FakeApi, ProviderContainer)> pump(
  WidgetTester t, {
  bool signedIn = true,
  AdminRole? role = AdminRole.superAdmin,
}) async {
  t.view
    ..physicalSize = const Size(1400, 1000)
    ..devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final auth = FakeAuth();
  final api = FakeApi()..role = role;
  if (signedIn) auth.signInAs();
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        adminAuthProvider.overrideWithValue(auth),
        adminApiProvider.overrideWithValue(api),
      ],
      child: const AdminApp(),
    ),
  );
  await t.pumpAndSettle();
  final c = ProviderScope.containerOf(t.element(find.byType(AdminApp)));
  return (auth, api, c);
}

Future<void> go(ProviderContainer c, WidgetTester t, String path) async {
  c.read(routerProvider).go(path);
  await t.pumpAndSettle();
}

void main() {
  test('gate: sign-in → two-factor → admin role', () {
    const admin = AsyncData<AdminRole?>(AdminRole.support);
    const none = AsyncData<AdminRole?>(null);
    expect(
      adminRedirect(
        signedIn: false,
        aal: 'aal1',
        role: none,
        location: '/users',
      ),
      '/sign-in',
    );
    expect(
      adminRedirect(signedIn: true, aal: 'aal1', role: admin, location: '/'),
      '/mfa',
    );
    expect(
      adminRedirect(signedIn: true, aal: 'aal2', role: none, location: '/'),
      '/not-admin',
    );
    expect(
      adminRedirect(signedIn: true, aal: 'aal2', role: admin, location: '/mfa'),
      '/',
    );
    expect(
      adminRedirect(
        signedIn: true,
        aal: 'aal2',
        role: admin,
        location: '/admins',
      ),
      '/',
      reason: 'super only',
    );
    expect(
      adminRedirect(
        signedIn: true,
        aal: 'aal2',
        role: const AsyncData(AdminRole.superAdmin),
        location: '/admins',
      ),
      isNull,
    );
  });

  testWidgets(
    'sign in with a code, enrol the authenticator, land on Overview',
    (t) async {
      final (auth, _, _) = await pump(t, signedIn: false);
      expect(
        find.text('Sign in with your admin email or phone.'),
        findsOneWidget,
      );
      await t.enterText(find.byKey(const Key('admin-id')), 'boss@aria.test');
      await t.tap(find.byKey(const Key('admin-continue')));
      await t.pumpAndSettle();
      expect(auth.sent, ['boss@aria.test']);
      await t.enterText(find.byKey(const Key('admin-code')), '123456');
      await t.tap(find.byKey(const Key('admin-continue')));
      await t.pumpAndSettle();

      expect(
        find.text('Two-factor sign-in'),
        findsOneWidget,
        reason: 'admins must add a second factor',
      );
      await t.tap(find.byKey(const Key('mfa-enroll')));
      await t.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.textContaining('JBSWY3DPEHPK3PXP'), findsOneWidget);
      await t.enterText(find.byKey(const Key('mfa-code')), '000000');
      await t.tap(find.byKey(const Key('mfa-verify')));
      await t.pumpAndSettle();
      expect(find.textContaining('That code didn’t work'), findsOneWidget);
      await t.enterText(find.byKey(const Key('mfa-code')), '654321');
      await t.tap(find.byKey(const Key('mfa-verify')));
      await t.pumpAndSettle();
      expect(find.text('Overview'), findsWidgets);
      expect(find.text('₹41,790'), findsOneWidget, reason: 'MRR');
    },
  );

  testWidgets('not an admin → no access', (t) async {
    await pump(t, role: null);
    expect(find.text('No admin access'), findsOneWidget);
  });

  testWidgets('search → user → suspend needs a reason → shown as suspended', (
    t,
  ) async {
    final (_, api, c) = await pump(t);
    await go(c, t, '/users');
    await t.enterText(find.byKey(const Key('user-search')), 'asha');
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    await t.tap(find.text('Asha Rao'));
    await t.pumpAndSettle();
    expect(find.text('Rao family'), findsWidgets);
    expect(
      find.textContaining('14'),
      findsWidgets,
      reason: 'reminder count only',
    );

    await t.tap(find.byKey(const Key('act-suspend')));
    await t.pumpAndSettle();
    final ok = find.byKey(const Key('reason-ok'));
    expect(
      t.widget<FilledButton>(ok).onPressed,
      isNull,
      reason: 'no reason, no action',
    );
    await t.enterText(
      find.byKey(const Key('reason')),
      'spam invites, ticket #12',
    );
    await t.pumpAndSettle();
    await t.tap(ok);
    await t.pumpAndSettle();
    expect(api.calls.single, 'suspend u-1: spam invites, ticket #12');
    expect(find.textContaining('Suspended'), findsWidgets);
    expect(find.byKey(const Key('act-unsuspend')), findsOneWidget);
  });

  testWidgets('finance is read-only', (t) async {
    final (_, _, c) = await pump(t, role: AdminRole.finance);
    await go(c, t, '/users/u-1');
    expect(find.text('Rao family'), findsWidgets);
    expect(find.byKey(const Key('act-suspend')), findsNothing);
    expect(find.text('Admins'), findsNothing, reason: 'super-only page hidden');
    await go(c, t, '/promos');
    expect(find.byKey(const Key('new-promo')), findsNothing);
  });

  testWidgets('delete now: super only, must type DELETE', (t) async {
    final (_, api, c) = await pump(t);
    await go(c, t, '/users/u-1');
    await t.tap(find.byKey(const Key('act-delete')));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const Key('reason')),
      'verified web deletion request',
    );
    await t.pumpAndSettle();
    final ok = find.byKey(const Key('reason-ok'));
    expect(t.widget<FilledButton>(ok).onPressed, isNull);
    await t.enterText(find.byKey(const Key('confirm-word')), 'DELETE');
    await t.pumpAndSettle();
    await t.tap(ok);
    await t.pumpAndSettle();
    expect(api.calls.single, 'delete u-1: verified web deletion request');
  });

  testWidgets('support creates a promo code', (t) async {
    final (_, api, c) = await pump(t, role: AdminRole.support);
    await go(c, t, '/promos');
    await t.tap(find.byKey(const Key('new-promo')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('promo-code')), 'diwali30');
    await t.enterText(find.byKey(const Key('promo-reason')), 'Diwali campaign');
    await t.tap(find.byKey(const Key('promo-create')));
    await t.pumpAndSettle();
    expect(api.calls.single, 'promo diwali30 personal 30');
    expect(find.text('DIWALI30'), findsOneWidget);
  });

  testWidgets('subscriptions: ending soon list; revenue page', (t) async {
    final (_, _, c) = await pump(t);
    await go(c, t, '/subscriptions');
    expect(find.text('Rao family'), findsOneWidget);
    await go(c, t, '/revenue');
    expect(find.text('₹1,990'), findsWidgets);
  });
}
