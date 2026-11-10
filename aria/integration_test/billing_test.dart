// Billing against a running local Supabase (real RPCs, triggers, cron
// function and the revenuecat-webhook Edge Function):
//   flutter test integration_test/billing_test.dart -d <device> \
//     --dart-define-from-file=env/dev.json \
//     --dart-define=SUPABASE_SERVICE_ROLE_KEY=... \
//     --dart-define=REVENUECAT_WEBHOOK_SECRET=<from supabase/functions/.env>
import 'dart:convert';
import 'dart:io';

import 'package:aria/app.dart';
import 'package:aria/core/config/env.dart';
import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/data/providers.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/circles/domain/circle.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/voice/application/voice_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _phone = '+919888888888';
const _serviceKey = String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY');
const _rcSecret = String.fromEnvironment('REVENUECAT_WEBHOOK_SECRET');

Future<Map<String, dynamic>> revenueCat(
  Map<String, dynamic> event, {
  String secret = _rcSecret,
}) async {
  final http = HttpClient();
  try {
    final req = await http.postUrl(
      Uri.parse('${Env.supabaseUrl}/functions/v1/revenuecat-webhook'),
    );
    req.headers
      ..set('Authorization', 'Bearer $secret')
      ..contentType = ContentType.json;
    req.write(jsonEncode({'api_version': '1.0', 'event': event}));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return {
      'status': res.statusCode,
      ...jsonDecode(body) as Map<String, dynamic>,
    };
  } finally {
    http.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'trial → store purchase webhook → cancel → expiry downgrade → promo',
    (tester) async {
      expect(_serviceKey, isNotEmpty);
      expect(_rcSecret, isNotEmpty);
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

      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const AriaApp()),
      );
      await tester.pumpAndSettle();
      await supabase.auth.signInWithOtp(phone: _phone);
      await supabase.auth.verifyOTP(
        phone: _phone,
        token: '123456',
        type: OtpType.sms,
      );
      await tester.pumpAndSettle();
      final me = supabase.auth.currentUser!.id;
      final engine = container.read(syncEngineProvider)!;
      await engine.syncNow();

      Future<String> plan() async {
        await engine.syncNow();
        await tester.pumpAndSettle();
        return container.read(entitlementProvider).plan.code;
      }

      // Start clean: earlier runs may have upgraded the personal Circle.
      final personal = await supabase
          .from('circles')
          .select('id')
          .eq('owner_id', me)
          .eq('type', 'personal')
          .single();
      await admin
          .from('subscriptions')
          .delete()
          .eq('circle_id', personal['id'] as String);
      await admin
          .from('promo_redemptions')
          .delete()
          .eq('circle_id', personal['id'] as String);
      await admin
          .from('billing_events')
          .delete()
          .eq('circle_id', personal['id'] as String);
      expect(await plan(), 'free');

      // 1. Family trial on a new Circle (server-granted, once per Circle).
      final api = container.read(billingApiProvider)!;
      final circleId = await container
          .read(circleApiProvider)
          .createCircle('Billing E2E', CircleType.family);
      addTearDown(() => admin.from('circles').delete().eq('id', circleId));
      final trialEnd = await api.startTrial(circleId, 'family');
      expect(trialEnd.difference(DateTime.now()).inDays, 6);
      expect(await plan(), 'family');
      expect((await api.circleBilling(circleId))!.trialing, isTrue);
      Object? again;
      try {
        await api.startTrial(circleId, 'family');
      } on Object catch (e) {
        again = e;
      }
      expect(again.toString(), contains('trial'));

      // Premium choices made during the trial.
      container
          .read(voiceSettingsProvider.notifier)
          .update((v) => v.copyWith(voiceId: 'meera'));
      container.read(themeControllerProvider.notifier).setPreset('sunset');

      // 2. RevenueCat: bad secret rejected; Team purchase upgrades.
      final now = DateTime.now().millisecondsSinceEpoch;
      final base = {
        'app_user_id': me,
        'product_id': 'aria_team_year',
        'original_transaction_id': 'e2e-$now',
        'period_type': 'NORMAL',
        'currency': 'INR',
        'price_in_purchased_currency': 4999,
        'expiration_at_ms': now + 365 * 86400000,
        'event_timestamp_ms': now,
        'subscriber_attributes': {
          'circle_id': {'value': circleId},
        },
      };
      expect(
        (await revenueCat({
          ...base,
          'id': 'x',
          'type': 'INITIAL_PURCHASE',
        }, secret: 'nope'))['status'],
        401,
      );
      expect(
        (await revenueCat({
          ...base,
          'id': 'p-$now',
          'type': 'INITIAL_PURCHASE',
        }))['result'],
        'ok',
      );
      expect(
        (await revenueCat({
          ...base,
          'id': 'p-$now',
          'type': 'INITIAL_PURCHASE',
        }))['result'],
        'duplicate',
      );
      expect(await plan(), 'team');

      // 3. Cancel keeps Team until the period ends; expiry falls back to the
      //    still-running Family trial (best entitled subscription wins).
      expect(
        (await revenueCat({
          ...base,
          'id': 'c-$now',
          'type': 'CANCELLATION',
        }))['result'],
        'ok',
      );
      expect(await plan(), 'team');
      final b = (await api.circleBilling(circleId))!;
      expect([b.planCode, b.ending], ['team', true]);
      expect(
        (await revenueCat({
          ...base,
          'id': 'e-$now',
          'type': 'EXPIRATION',
        }))['result'],
        'ok',
      );
      expect(await plan(), 'family');

      // 4. Trial runs out → the cron job downgrades; data stays, premium
      //    voice/theme fall back to free defaults on the device.
      await admin
          .from('subscriptions')
          .update({
            'trial_end': DateTime.now()
                .toUtc()
                .subtract(const Duration(minutes: 1))
                .toIso8601String(),
          })
          .eq('circle_id', circleId)
          .not('trial_end', 'is', null);
      expect(
        await admin.rpc<int>('expire_subscriptions'),
        greaterThanOrEqualTo(1),
      );
      expect(await plan(), 'free');
      expect(container.read(voiceSettingsProvider).voiceId, 'aria');
      expect(container.read(themeControllerProvider).presetId, 'neon');

      final history = await api.history(circleId);
      expect(
        history.map((h) => h.type),
        containsAll(['trial_started', 'purchase', 'canceled', 'expired']),
      );
      expect(history.firstWhere((h) => h.type == 'purchase').amountInr, 4999);

      // 5. Student code on the personal Circle.
      await api.redeemPromo(personal['id'] as String, 'student30');
      expect(await plan(), 'personal');

      await admin
          .from('subscriptions')
          .delete()
          .eq('circle_id', personal['id'] as String);
      await admin
          .from('promo_redemptions')
          .delete()
          .eq('circle_id', personal['id'] as String);
      await admin
          .from('billing_events')
          .delete()
          .eq('circle_id', personal['id'] as String);
      await supabase.auth.signOut();
      await tester.pumpAndSettle();
    },
  );
}
