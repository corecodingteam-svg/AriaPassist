// Admin safety layer + renewal reminders against the local stack:
//   flutter test integration_test/admin_test.dart -d <device> \
//     --dart-define-from-file=env/dev.json --dart-define=SUPABASE_SERVICE_ROLE_KEY=… \
//     --dart-define=CRON_SECRET=…
import 'dart:convert';
import 'dart:io';

import 'package:aria/app.dart';
import 'package:aria/core/config/env.dart';
import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/data/providers.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/circles/domain/circle.dart';
import 'package:aria/features/connected/whatsapp_api.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/subscription/presentation/renewal_banner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _owner = '+919888888888';
const _other = '+919999999999';
const _serviceKey = String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY');
const _cron = String.fromEnvironment('CRON_SECRET');

Future<Map<String, dynamic>> dispatch() async {
  final http = HttpClient();
  try {
    final req = await http.postUrl(
      Uri.parse('${Env.supabaseUrl}/functions/v1/renewal-dispatch'),
    );
    req.headers.set('x-cron-secret', _cron);
    final res = await req.close();
    return jsonDecode(await res.transform(utf8.decoder).join())
        as Map<String, dynamic>;
  } finally {
    http.close();
  }
}

Future<void> signIn(GoTrueClient auth, String phone) async {
  await auth.signInWithOtp(phone: phone);
  await auth.verifyOTP(phone: phone, token: '123456', type: OtpType.sms);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'suspend → locked out → unsuspend; renewal reminder sent once; grant logged',
    (tester) async {
      expect([_serviceKey, _cron].every((s) => s.isNotEmpty), isTrue);
      SharedPreferences.setMockInitialValues({
        'aria.prefs.v1': '{"onboarded":true}',
      });
      final prefs = await SharedPreferences.getInstance();
      await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabasePublishableKey,
      );
      final supabase = Supabase.instance.client;
      final admin = SupabaseClient(Env.supabaseUrl, _serviceKey);
      await supabase.auth.signOut();

      // ---------------------------------------------------------- suspension
      final other = SupabaseClient(
        Env.supabaseUrl,
        Env.supabasePublishableKey,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );
      await signIn(other.auth, _other);
      final otherId = other.auth.currentUser!.id;
      addTearDown(() async {
        try {
          await admin.rpc<dynamic>(
            'admin_unsuspend_user',
            params: {'p_user': otherId, 'p_reason': 'test cleanup'},
          );
        } on Object {
          // not suspended
        }
      });
      expect(await other.from('circles').select('id'), isNotEmpty);

      await admin.rpc<dynamic>(
        'admin_suspend_user',
        params: {'p_user': otherId, 'p_reason': 'integration test'},
      );
      Object? blocked;
      try {
        await other.from('circles').select('id');
      } on PostgrestException catch (e) {
        blocked = e;
      }
      expect(
        blocked.toString(),
        contains('account suspended'),
        reason: 'existing session cut off at once',
      );
      Object? refresh;
      try {
        await other.auth.refreshSession();
      } on Object catch (e) {
        refresh = e;
      }
      expect(refresh, isNotNull, reason: 'sessions revoked');
      // (The auth ban itself is asserted in 08_admin.test.sql.)

      await admin.rpc<dynamic>(
        'admin_unsuspend_user',
        params: {'p_user': otherId, 'p_reason': 'integration test done'},
      );
      // GoTrue allows one OTP per number per minute: wait, then sign back in.
      await Future<void>.delayed(const Duration(seconds: 61));
      await signIn(other.auth, _other);
      expect(
        await other.from('circles').select('id'),
        isNotEmpty,
        reason: 'access restored',
      );
      await other.auth.signOut();

      // ------------------------------------------------------------ renewals
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const AriaApp()),
      );
      await signIn(supabase.auth, _owner);
      await tester.pumpAndSettle();
      final me = supabase.auth.currentUser!.id;
      final engine = container.read(syncEngineProvider)!;

      final circleId = await container
          .read(circleApiProvider)
          .createCircle('Renewal E2E', CircleType.family);
      addTearDown(() => admin.from('circles').delete().eq('id', circleId));
      await container.read(billingApiProvider)!.startTrial(circleId, 'family');
      await container.read(whatsAppApiProvider)!.setEnabled(enabled: true);
      addTearDown(
        () => admin.from('whatsapp_optins').delete().eq('user_id', me),
      );
      // Trial ends in 2½ days → the "3 days left" step.
      final ends = DateTime.now().toUtc().add(
        const Duration(days: 2, hours: 12),
      );
      await admin
          .from('subscriptions')
          .update({'trial_end': ends.toIso8601String()})
          .eq('circle_id', circleId);
      await engine.syncNow();

      final first = await dispatch();
      expect(first['logged'], greaterThanOrEqualTo(1), reason: '$first');
      final notice = await admin
          .from('renewal_notices')
          .select('step, channel, status')
          .eq('circle_id', circleId)
          .single();
      expect(
        [notice['step'], notice['channel'], notice['status']],
        ['d3', 'whatsapp', 'logged'],
      );
      await dispatch();
      expect(
        await admin
            .from('renewal_notices')
            .select('id')
            .eq('circle_id', circleId),
        hasLength(1),
        reason: 'sent only once',
      );

      // The app shows the renewal banner for the owner.
      container.invalidate(circleBillingProvider(circleId));
      await tester.pumpAndSettle();
      await container.read(circleBillingProvider(circleId).future);
      await tester.pumpAndSettle();
      final banner = container.read(renewalBannerProvider);
      expect([banner?.kind, banner?.daysLeft], [RenewalKind.ending, 3]);

      // Support grants 30 more days (extends from the trial end), logged.
      final until = DateTime.parse(
        await admin.rpc<String>(
          'admin_grant_plan',
          params: {
            'p_circle': circleId,
            'p_plan': 'family',
            'p_days': 30,
            'p_reason': 'integration goodwill',
          },
        ),
      );
      expect(until.difference(ends).inDays, 30);
      // (reports.* are for the read-only SQL login, not exposed via the API.)
      final log = await admin
          .from('admin_actions')
          .select('action, reason')
          .order('at', ascending: false)
          .limit(10);
      expect(
        log.map((r) => r['action']),
        containsAll(['user.suspended', 'user.unsuspended', 'plan.granted']),
      );

      await container.read(whatsAppApiProvider)!.setEnabled(enabled: false);
      await supabase.auth.signOut();
      await tester.pumpAndSettle();
    },
  );
}
