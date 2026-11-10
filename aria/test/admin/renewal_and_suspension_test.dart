import 'package:aria/core/router/app_router.dart';
import 'package:aria/features/account/application/account_status.dart';
import 'package:aria/features/auth/presentation/sign_in_screen.dart';
import 'package:aria/features/circles/domain/circle.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:aria/features/subscription/presentation/renewal_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_billing_api.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

final now = DateTime.utc(2026, 11, 9, 4, 30);
const me = 'u1';
const personal = Circle(
  id: 'p',
  name: 'Personal',
  type: CircleType.personal,
  ownerId: me,
  myRole: CircleRole.owner,
);
const theirs = Circle(
  id: 'f',
  name: 'Rao family',
  type: CircleType.family,
  ownerId: 'x',
  myRole: CircleRole.member,
);

RenewalBannerInfo? banner(
  Map<String, CircleBilling> b, {
  Set<String> dismissed = const {},
  String? granting,
}) => renewalBannerFor(
  circles: const [personal, theirs],
  billing: b,
  me: me,
  grantingCircleId: granting,
  plans: kTestPlans,
  now: now,
  dismissed: dismissed,
);

CircleBilling paid(
  Duration left, {
  bool auto = false,
  String status = 'active',
  String plan = 'personal',
}) => CircleBilling(
  planCode: plan,
  status: status,
  seatsUsed: 1,
  maxSeats: 1,
  currentPeriodEnd: now.add(left),
  autoRenews: auto,
);

void main() {
  group('renewal banner rules', () {
    test('owner: ending within 7 days → Renew; further away → nothing', () {
      final b = banner({'p': paid(const Duration(days: 3))})!;
      expect(
        [b.kind, b.daysLeft, b.planName],
        [RenewalKind.ending, 3, 'Personal'],
      );
      expect(banner({'p': paid(const Duration(days: 9))}), isNull);
    });

    test('auto-renewing plans never nag', () {
      expect(banner({'p': paid(const Duration(days: 2), auto: true)}), isNull);
    });

    test('dismissing hides it until the next step', () {
      final at3 = banner({'p': paid(const Duration(days: 3))})!;
      expect(
        banner({'p': paid(const Duration(days: 3))}, dismissed: {at3.key}),
        isNull,
      );
      final at1 = banner(
        {'p': paid(const Duration(hours: 20))},
        dismissed: {at3.key},
      );
      expect(at1?.daysLeft, 1, reason: 'the 1-day step shows again');
    });

    test('lapsed within 14 days → "ended", older → nothing', () {
      CircleBilling lapsed(Duration ago) => CircleBilling(
        planCode: 'free',
        seatsUsed: 1,
        maxSeats: 1,
        lapsedPlanCode: 'personal',
        lapsedAt: now.subtract(ago),
      );
      expect(
        banner({'p': lapsed(const Duration(days: 2))})?.kind,
        RenewalKind.ended,
      );
      expect(banner({'p': lapsed(const Duration(days: 20))}), isNull);
    });

    test('failed renewal payment beats everything', () {
      final b = banner({
        'p': paid(const Duration(days: 5), auto: true, status: 'past_due'),
      })!;
      expect(b.kind, RenewalKind.paymentIssue);
    });

    test('members get an info note only in the last 3 days', () {
      final fam = paid(const Duration(days: 2), plan: 'family');
      expect(banner({'f': fam}, granting: 'f')?.kind, RenewalKind.memberInfo);
      expect(
        banner({
          'f': paid(const Duration(days: 6), plan: 'family'),
        }, granting: 'f'),
        isNull,
      );
    });
  });

  testWidgets('Today shows the renewal banner; Renew opens plans', (t) async {
    final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
    app.billing.forced[kTestCircle] = CircleBilling(
      planCode: 'personal',
      status: 'active',
      seatsUsed: 1,
      maxSeats: 1,
      provider: 'manual',
      currentPeriodEnd: kTestNow.add(const Duration(days: 3)),
      cancelAtPeriodEnd: true,
    );
    app.container.invalidate(circleBillingProvider(kTestCircle));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('renewal-banner')), findsOneWidget);
    expect(
      find.textContaining('Your Personal plan ends in 3 days'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('renewal-renew')));
    await t.pumpAndSettle();
    expect(find.text('Choose what fits you'), findsOneWidget);
    expect(
      find.byKey(const Key('no-refunds')),
      findsNothing,
      reason: 'below the fold',
    );
  });

  testWidgets('suspended account → suspended screen; unsuspended → back', (
    t,
  ) async {
    final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
    app.account.isSuspended = true;
    await app.container.read(suspendedProvider.notifier).check();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('suspended-title')), findsOneWidget);

    app.container.read(routerProvider).go('/settings');
    await t.pumpAndSettle();
    expect(
      find.byKey(const Key('suspended-title')),
      findsOneWidget,
      reason: 'can’t navigate around it',
    );

    app.account.isSuspended = false;
    await t.tap(find.text('Check again'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('suspended-title')), findsNothing);
    expect(find.text('Nothing planned yet'), findsOneWidget);
  });

  test('redirect rule and messages', () {
    expect(
      authRedirect(signedIn: true, location: '/today', suspended: true),
      '/suspended',
    );
    expect(
      authRedirect(signedIn: true, location: '/suspended', suspended: true),
      isNull,
    );
    expect(authRedirect(signedIn: true, location: '/suspended'), '/today');
    expect(
      authRedirect(signedIn: false, location: '/today', suspended: true),
      '/sign-in',
    );
    expect(
      friendlyAuthError(Exception('AuthApiException(message: User is banned)')),
      contains('suspended'),
    );
    expect(
      isSuspendedError(
        Exception(
          'PostgrestException(message: account suspended, code: PT403)',
        ),
      ),
      isTrue,
    );
    expect(isSuspendedError(Exception('SocketException')), isFalse);
  });
}
