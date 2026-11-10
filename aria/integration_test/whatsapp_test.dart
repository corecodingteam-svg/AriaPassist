// WhatsApp reminders against the local stack (dispatcher in log mode):
//   flutter test integration_test/whatsapp_test.dart -d <device> \
//     --dart-define-from-file=env/dev.json \
//     --dart-define=SUPABASE_SERVICE_ROLE_KEY=… \
//     --dart-define=CRON_SECRET=… --dart-define=WHATSAPP_APP_SECRET=…
import 'dart:convert';
import 'dart:io';

import 'package:aria/app.dart';
import 'package:aria/core/config/env.dart';
import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/data/providers.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/circles/domain/circle.dart';
import 'package:aria/features/connected/whatsapp_api.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const _phone = '+919888888888';
const _serviceKey = String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY');
const _cron = String.fromEnvironment('CRON_SECRET');
const _appSecret = String.fromEnvironment('WHATSAPP_APP_SECRET');

Future<Map<String, dynamic>> post(
  String fn,
  Object body,
  Map<String, String> headers,
) async {
  final http = HttpClient();
  try {
    final req = await http.postUrl(
      Uri.parse('${Env.supabaseUrl}/functions/v1/$fn'),
    );
    headers.forEach(req.headers.set);
    req.headers.contentType = ContentType.json;
    final raw = jsonEncode(body);
    if (fn == 'whatsapp-webhook') {
      final sig = Hmac(
        sha256,
        utf8.encode(_appSecret),
      ).convert(utf8.encode(raw)).toString();
      req.headers.set('X-Hub-Signature-256', 'sha256=$sig');
    }
    req.write(raw);
    final res = await req.close();
    return {
      'status': res.statusCode,
      ...jsonDecode(await res.transform(utf8.decoder).join())
          as Map<String, dynamic>,
    };
  } finally {
    http.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opt in → due reminder sent → "Done" reply completes it', (
    tester,
  ) async {
    expect([_serviceKey, _cron, _appSecret].every((s) => s.isNotEmpty), isTrue);
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
    await supabase.auth.signInWithOtp(phone: _phone);
    await supabase.auth.verifyOTP(
      phone: _phone,
      token: '123456',
      type: OtpType.sms,
    );
    await tester.pumpAndSettle();
    final me = supabase.auth.currentUser!.id;
    final engine = container.read(syncEngineProvider)!;

    // Family trial on a fresh Circle (WhatsApp is a Family feature).
    final circleId = await container
        .read(circleApiProvider)
        .createCircle('WhatsApp E2E', CircleType.family);
    addTearDown(() => admin.from('circles').delete().eq('id', circleId));
    await container.read(billingApiProvider)!.startTrial(circleId, 'family');
    await engine.syncNow();

    // Opt in: the server uses the verified sign-in number.
    final wa = container.read(whatsAppApiProvider)!;
    expect(await wa.setEnabled(enabled: true), _phone);
    addTearDown(() => admin.from('whatsapp_optins').delete().eq('user_id', me));

    // A reminder that just came due.
    final id = const Uuid().v4();
    await container.read(localStoreProvider).write('reminders', {
      'id': id,
      'circle_id': circleId,
      'created_by': me,
      'title': 'E2E: BP tablet',
      'category': 'health',
      'all_day': false,
      'timezone': 'Asia/Kolkata',
      'start_at': DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 30))
          .toIso8601String(),
    });
    expect((await engine.syncNow()).failed, 0);

    // The cron job is scheduled; run the dispatcher it calls.
    final job = await admin.rpc<dynamic>('kick_whatsapp_dispatch');
    expect(job, isNotNull, reason: 'Vault URL + cron secret configured');
    expect(
      (await post('whatsapp-dispatch', {}, {
        'x-cron-secret': 'wrong',
      }))['status'],
      401,
    );
    final sent = await post('whatsapp-dispatch', {}, {'x-cron-secret': _cron});
    final outbox = await admin
        .from('whatsapp_outbox')
        .select('status, phone_e164')
        .eq('reminder_id', id)
        .single();
    expect(outbox['phone_e164'], _phone, reason: 'dispatch: $sent');
    expect(
      outbox['status'],
      'logged',
      reason: 'log mode until Meta keys exist',
    );

    // "Done" from WhatsApp (signed like Meta's webhook) completes it.
    final reply = await post('whatsapp-webhook', {
      'entry': [
        {
          'changes': [
            {
              'value': {
                'messages': [
                  {
                    'from': _phone.substring(1),
                    'type': 'text',
                    'text': {'body': 'Done'},
                  },
                ],
              },
            },
          ],
        },
      ],
    }, {});
    expect(reply['result'], ['done']);
    await engine.syncNow();
    final local = await container.read(reminderRepositoryProvider)!.get(id);
    expect(local!.status.name, 'done');

    await wa.setEnabled(enabled: false);
    await supabase.auth.signOut();
    await tester.pumpAndSettle();
  });
}
