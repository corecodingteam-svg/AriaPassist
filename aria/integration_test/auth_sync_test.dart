// End-to-end against a running local Supabase:
//   supabase start
//   flutter test integration_test -d <device> --dart-define-from-file=env/dev.json
import 'package:aria/app.dart';
import 'package:aria/core/config/env.dart';
import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

// Test number from supabase/config.toml (auth.sms.test_otp).
const _phone = '+919888888888';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'phone OTP sign-in → personal circle syncs → reminder round-trips',
    (tester) async {
      expect(Env.hasSupabase, isTrue, reason: 'pass --dart-define-from-file');
      SharedPreferences.setMockInitialValues({
        // Skip onboarding (covered by widget tests).
        'aria.prefs.v1': '{"onboarded":true}',
      });
      final prefs = await SharedPreferences.getInstance();
      await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabasePublishableKey,
      );
      final supabase = Supabase.instance.client;
      await supabase.auth.signOut();

      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const AriaApp()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Send code'), findsOneWidget);

      // Real GoTrue: send + verify the test OTP.
      await supabase.auth.signInWithOtp(phone: _phone);
      await supabase.auth.verifyOTP(
        phone: _phone,
        token: '123456',
        type: OtpType.sms,
      );
      await tester.pumpAndSettle();
      // Today's app bar (the account may already have reminders).
      expect(
        find.byTooltip('New reminder'),
        findsOneWidget,
        reason: 'router moved to Today after sign-in',
      );

      // Pull: the sign-up trigger's personal circle lands in SQLite.
      final engine = container.read(syncEngineProvider)!;
      await engine.syncNow();
      final db = container.read(appDatabaseProvider);
      final circles = await db.select(db.circles).get();
      final personal = circles.singleWhere((c) => c.type == 'personal');
      final userId = supabase.auth.currentUser!.id;
      expect(personal.ownerId, userId);

      // Push: an offline-first write reaches Postgres through RLS.
      final id = const Uuid().v4();
      await container.read(localStoreProvider).write('reminders', {
        'id': id,
        'circle_id': personal.id,
        'created_by': userId,
        'title': 'Integration test: drink water',
        'category': 'health',
        'all_day': false,
      });
      final result = await engine.syncNow();
      expect(result.failed, 0);
      final server = await supabase
          .from('reminders')
          .select()
          .eq('id', id)
          .single();
      expect(server['title'], 'Integration test: drink water');
      expect(server['updated_at'], isNotNull, reason: 'server-stamped');

      // Clean up via soft delete (exercises the delete path too).
      await container.read(localStoreProvider).softDelete('reminders', id);
      await engine.syncNow();
      final deleted = await supabase
          .from('reminders')
          .select('deleted_at')
          .eq('id', id)
          .single();
      expect(deleted['deleted_at'], isNotNull);

      // Settings sync: a theme change reaches user_settings on the server.
      container.read(themeControllerProvider.notifier).setPreset('ocean');
      await tester.pump(const Duration(seconds: 3)); // 2 s debounce
      await Future<void>.delayed(const Duration(seconds: 2));
      final settings = await supabase
          .from('user_settings')
          .select('theme_json')
          .eq('user_id', userId)
          .single();
      expect((settings['theme_json'] as Map)['preset'], 'ocean');

      await supabase.auth.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Send code'), findsOneWidget);
    },
  );
}
