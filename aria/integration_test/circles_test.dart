// Two-user Circle flow against a running local Supabase:
//   supabase start
//   flutter test integration_test/circles_test.dart -d <device> \
//     --dart-define-from-file=env/dev.json \
//     --dart-define=SUPABASE_SERVICE_ROLE_KEY=$(supabase status -o env | sed -n 's/^SERVICE_ROLE_KEY="\(.*\)"/\1/p')
// The service-role key (local stack only) calls apply_billing_event, the
// function the store webhooks use, to upgrade the Circle's plan.
import 'package:aria/app.dart';
import 'package:aria/core/config/env.dart';
import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/data/providers.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/circles/data/circle_repository.dart';
import 'package:aria/features/circles/domain/circle.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const _ownerPhone = '+919888888888';
const _dadPhone = '+919999999999';
const _serviceKey = String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY');

Future<void> signIn(GoTrueClient auth, String phone) async {
  await auth.signInWithOtp(phone: phone);
  await auth.verifyOTP(phone: phone, token: '123456', type: OtpType.sms);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'owner creates a family Circle, invites Dad, assigns, sees it done',
    (tester) async {
      expect(Env.hasSupabase, isTrue, reason: 'pass --dart-define-from-file');
      expect(_serviceKey, isNotEmpty, reason: 'pass SUPABASE_SERVICE_ROLE_KEY');
      SharedPreferences.setMockInitialValues({
        'aria.prefs.v1': '{"onboarded":true}',
      });
      final prefs = await SharedPreferences.getInstance();
      await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabasePublishableKey,
      );
      final supabase = Supabase.instance.client;
      await supabase.auth.signOut();

      // Second user on a separate, in-memory client; admin = billing stand-in.
      final dad = SupabaseClient(
        Env.supabaseUrl,
        Env.supabasePublishableKey,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );
      final admin = SupabaseClient(Env.supabaseUrl, _serviceKey);

      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const AriaApp()),
      );
      await tester.pumpAndSettle();

      await signIn(supabase.auth, _ownerPhone);
      await tester.pumpAndSettle();
      final me = supabase.auth.currentUser!.id;
      final engine = container.read(syncEngineProvider)!;
      await engine.syncNow();

      // 1. Create + invite (real RLS / SECURITY DEFINER functions).
      final api = container.read(circleApiProvider);
      final circleId = await api.createCircle(
        'E2E family ${DateTime.now().millisecondsSinceEpoch}',
        CircleType.family,
      );
      addTearDown(() => admin.from('circles').delete().eq('id', circleId));
      final token = await api.createInvite(circleId, CircleRole.dependent);

      // 2. Dad previews; joining a free-plan Circle hits the seat limit.
      await signIn(dad.auth, _dadPhone);
      final dadId = dad.auth.currentUser!.id;
      final preview = await dad.rpc<List<dynamic>>(
        'preview_invite',
        params: {'p_token': token},
      );
      expect((preview.single as Map)['role'], 'dependent');
      Object? seatError;
      try {
        await dad.rpc<dynamic>('accept_invite', params: {'p_token': token});
      } on PostgrestException catch (e) {
        seatError = e;
      }
      expect(
        circleErrorMessage(seatError!),
        contains('full on its current plan'),
      );

      // 3. "Billing" upgrades to Family; now Dad can join.
      // Same path a store purchase takes (webhook → apply_billing_event).
      final applied = await admin.rpc<String>(
        'apply_billing_event',
        params: {
          'e': {
            'provider': 'revenuecat',
            'event_id': 'circles-e2e-$circleId',
            'type': 'purchase',
            'circle_id': circleId,
            'user_id': me,
            'plan_code': 'family',
            'period': 'month',
            'status': 'active',
            'external_ref': 'circles-e2e-$circleId',
            'current_period_end': DateTime.now()
                .toUtc()
                .add(const Duration(days: 30))
                .toIso8601String(),
          },
        },
      );
      expect(applied, 'ok');
      final joined = await dad.rpc<dynamic>(
        'accept_invite',
        params: {'p_token': token},
      );
      expect(joined, circleId);

      // 4. Owner syncs: Dad is a dependent member.
      await engine.syncNow();
      final repo = CircleRepository(
        container.read(appDatabaseProvider),
        userId: me,
      );
      final members = await repo.watchMembers(circleId).first;
      expect(
        members.map((m) => (m.userId, m.role)),
        containsAll([(me, CircleRole.owner), (dadId, CircleRole.dependent)]),
      );

      // 5. Owner assigns a reminder to Dad (offline-first write → sync).
      final reminderId = const Uuid().v4();
      await container.read(localStoreProvider).write('reminders', {
        'id': reminderId,
        'circle_id': circleId,
        'created_by': me,
        'assigned_to': dadId,
        'title': 'E2E: BP tablet',
        'category': 'health',
        'all_day': false,
        'start_at': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      });
      expect((await engine.syncNow()).failed, 0);

      // 6. Dad sees it through RLS and marks it done.
      final onDadsPhone = await dad
          .from('reminders')
          .select('title,status')
          .eq('id', reminderId)
          .single();
      expect(onDadsPhone['title'], 'E2E: BP tablet');
      await dad
          .from('reminders')
          .update({'status': 'done'})
          .eq('id', reminderId);

      // 7. Owner's monitoring view reflects it after the next pull.
      await engine.syncNow();
      final assigned = await container
          .read(reminderRepositoryProvider)!
          .watchAssignedByMe(circleId)
          .first;
      expect(assigned.single.status.name, 'done');

      // 8. Audit log recorded the join and the assignment.
      final log = await api.auditLog(circleId);
      expect(
        log.map((e) => e.action),
        containsAll(['member.added', 'reminder.assigned']),
      );

      // 9. Dad can't change his own role (RLS filters the update away).
      await dad
          .from('memberships')
          .update({'role': 'owner'})
          .eq('circle_id', circleId)
          .eq('user_id', dadId);
      final role = await admin
          .from('memberships')
          .select('role')
          .eq('circle_id', circleId)
          .eq('user_id', dadId)
          .single();
      expect(role['role'], 'dependent');

      await dad.auth.signOut();
      await supabase.auth.signOut();
      await tester.pumpAndSettle();
    },
  );
}
