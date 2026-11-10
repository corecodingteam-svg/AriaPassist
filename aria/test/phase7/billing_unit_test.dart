import 'package:aria/data/local/app_database.dart';
import 'package:aria/data/sync/local_store.dart';
import 'package:aria/features/circles/domain/circle.dart';
import 'package:aria/features/lists/data/lists_repository.dart';
import 'package:aria/features/reminders/domain/alert_plan.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_billing_api.dart';
import '../helpers/pump_app.dart';

Plan plan(String code) => kTestPlans.firstWhere((p) => p.code == code);

void main() {
  setUpAll(ensureTimeZones);

  group('plans', () {
    test('features follow features_json', () {
      expect(plan('free').voiceAllowed('aria'), isTrue);
      expect(plan('free').voiceAllowed('meera'), isFalse);
      expect(plan('personal').voiceAllowed('meera'), isTrue);
      expect(plan('free').themeAllowed('mint'), isTrue);
      expect(plan('free').themeAllowed('sunset'), isFalse);
      expect(plan('free').maxLists, 2);
      expect(plan('personal').maxLists, isNull);
      expect(plan('personal').has(Feature.routines), isTrue);
      expect(plan('personal').has(Feature.assignReminders), isFalse);
      expect(plan('family').has(Feature.assignReminders), isTrue);
      expect(plan('family').has(Feature.auditLog), isFalse);
      expect(plan('team').has(Feature.auditLog), isTrue);
    });

    test('pricing copy: per person, yearly saving, rupees', () {
      expect(
        plan('family').perPersonMonthly(BillingPeriod.month),
        40,
        reason: 'spec: “just ₹40/person/month”',
      );
      expect(plan('personal').perPersonMonthly(BillingPeriod.month), isNull);
      expect(
        plan('personal').yearlySavingPercent,
        16,
        reason: 'spec: “Save ~16%”',
      );
      expect(rupeesWhole(99), '₹99');
      expect(rupeesWhole(1999), '₹1,999');
      expect(rupeesWhole(199900), '₹1,99,900');
    });

    test('the paywall recommends the cheapest plan with the feature', () {
      expect(
        PlanCatalog.cheapestWith(kTestPlans, Feature.routines).code,
        'personal',
      );
      expect(
        PlanCatalog.cheapestWith(kTestPlans, Feature.assignReminders).code,
        'family',
      );
      expect(
        PlanCatalog.cheapestWith(kTestPlans, Feature.auditLog).code,
        'team',
      );
    });

    test('server JSON round-trips', () {
      final p = Plan.fromJson(plan('family').toJson());
      expect(
        [p.id, p.code, p.maxSeats, p.priceYear, p.mostPopular],
        ['plan-family', 'family', 5, 1999, isTrue],
      );
    });
  });

  test('billing state', () {
    final trial = CircleBilling.fromJson(const {
      'plan_code': 'family',
      'status': 'trialing',
      'trial_end': '2026-11-16T04:30:00Z',
      'trial_used': true,
      'seats_used': 2,
      'max_seats': 5,
    });
    expect(
      [trial.trialing, trial.ending, trial.endsAt],
      [true, true, DateTime.utc(2026, 11, 16, 4, 30)],
    );
    const renewing = CircleBilling(
      planCode: 'personal',
      status: 'active',
      seatsUsed: 1,
      maxSeats: 1,
      autoRenews: true,
    );
    expect(renewing.ending, isFalse);
    const promo = CircleBilling(
      planCode: 'personal',
      status: 'active',
      seatsUsed: 1,
      maxSeats: 1,
    );
    expect(
      promo.ending,
      isTrue,
      reason: 'promo / granted months never renew by themselves',
    );
    const failing = CircleBilling(
      planCode: 'family',
      status: 'past_due',
      seatsUsed: 2,
      maxSeats: 5,
      autoRenews: true,
    );
    expect(failing.paymentIssue, isTrue);
    final lapsed = CircleBilling.fromJson(const {
      'plan_code': 'free',
      'seats_used': 1,
      'max_seats': 1,
      'lapsed_plan_code': 'family',
      'lapsed_at': '2026-11-08T04:30:00Z',
    });
    expect(
      [lapsed.lapsedPlanCode, lapsed.lapsedAt],
      ['family', DateTime.utc(2026, 11, 8, 4, 30)],
    );
  });

  test('billing errors read naturally', () {
    expect(
      billingErrorMessage(Exception('trial already used')),
      contains('already had its free trial'),
    );
    expect(
      billingErrorMessage(Exception('invalid_code')),
      contains('isn’t valid'),
    );
    expect(
      billingErrorMessage(Exception('only the owner can start a trial')),
      contains('owner'),
    );
    expect(billingErrorMessage(Exception('boom')), contains('connection'));
    expect(
      BillingRecord(
        type: 'renewal',
        at: DateTime.utc(2026, 11, 9),
        amountInr: 199,
      ).describe('Family'),
      'Family renewed',
    );
  });

  test('renewal notifications: 7/3/1 days + end for ending plans, 3-day courtesy for auto-renew', () {
    final now = DateTime.utc(2026, 11, 9, 4, 30);
    final alerts = planBillingAlerts(
      [
        (
          circleId: 'c1',
          planName: 'Family',
          endsAt: DateTime.utc(2026, 11, 16, 4, 30),
          ending: true,
        ),
        (
          circleId: 'c2',
          planName: 'Personal',
          endsAt: DateTime.utc(2026, 12, 9),
          ending: false,
        ),
        (
          circleId: 'c3',
          planName: 'Team',
          endsAt: DateTime.utc(2026, 11, 10),
          ending: true,
        ), // too late
      ],
      now: now,
      zone: kTestZone,
    );
    // c1 ends 16 Nov 10:00 IST; "7 days before" (9 Nov 10:00) is now → skipped.
    final c1 = alerts.where((a) => a.reminderId == 'billing:c1').toList();
    expect(c1.map((a) => a.title), [
      '3 days left on your Family plan',
      'Your Family plan ends tomorrow',
      'Your Family plan has ended',
    ]);
    expect(c1.map((a) => a.fireAt), [
      fromWall(DateTime.utc(2026, 11, 13, 10), kTestZone),
      fromWall(DateTime.utc(2026, 11, 15, 10), kTestZone),
      DateTime.utc(2026, 11, 16, 4, 30),
    ]);
    expect(
      c1.map((a) => a.id).toSet().length,
      3,
      reason: 'distinct notification ids',
    );
    final c2 = alerts.where((a) => a.reminderId == 'billing:c2').toList();
    expect(c2.single.title, 'Your Personal plan renews in 3 days');
    // c3 ends tomorrow: only "ends tomorrow"'s 10 AM has passed → just the end notice.
    expect(
      alerts.where((a) => a.reminderId == 'billing:c3').map((a) => a.title),
      ['Your Team plan has ended'],
    );
    expect(alerts.every((a) => a.kind == AlertKind.billing), isTrue);
  });

  test('which Circle a plan applies to', () {
    const personal = Circle(
      id: 'p',
      name: 'Personal',
      type: CircleType.personal,
      ownerId: 'me',
      myRole: CircleRole.owner,
    );
    const fam = Circle(
      id: 'f',
      name: 'Home',
      type: CircleType.family,
      ownerId: 'me',
      myRole: CircleRole.owner,
    );
    const theirs = Circle(
      id: 't',
      name: 'Rao',
      type: CircleType.family,
      ownerId: 'x',
      myRole: CircleRole.member,
    );
    expect(
      targetCircleFor(
        plan('personal'),
        circles: [personal, fam],
        me: 'me',
        active: fam,
      )?.id,
      'p',
    );
    expect(
      targetCircleFor(
        plan('family'),
        circles: [personal, fam],
        me: 'me',
        active: personal,
      )?.id,
      'f',
    );
    expect(
      targetCircleFor(
        plan('family'),
        circles: [personal, theirs],
        me: 'me',
        active: theirs,
      ),
      isNull,
      reason: 'not mine → a new Circle will be created',
    );
  });

  group('list limit', () {
    late AppDatabase db;
    setUp(() async {
      db = memoryDb();
      await seedCircle(db, 'me');
    });
    tearDown(() => db.close());

    test(
      'free plan: a third list is refused, existing lists still match',
      () async {
        final repo = ListsRepository(db, LocalStore(db), userId: 'me');
        await repo.findOrCreate('grocery', circleId: kTestCircle, maxLists: 2);
        await repo.findOrCreate('packing', circleId: kTestCircle, maxLists: 2);
        expect(await repo.count(), 2);
        expect(
          () => repo.findOrCreate('gifts', circleId: kTestCircle, maxLists: 2),
          throwsA(isA<ListLimitReached>()),
        );
        expect(
          await repo.findOrCreate(
            'Grocery list',
            circleId: kTestCircle,
            maxLists: 2,
          ),
          isNotEmpty,
        );
        await repo.findOrCreate('gifts', circleId: kTestCircle);
        expect(await repo.count(), 3, reason: 'no limit when premium');
      },
    );
  });
}
