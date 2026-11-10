// Create → scheduled with the OS → Done (notification action) → synced.
//   flutter test integration_test/reminder_lifecycle_test.dart -d <device> \
//     --dart-define-from-file=env/dev.json
import 'package:aria/app.dart';
import 'package:aria/core/config/env.dart';
import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/data/providers.dart';
import 'package:aria/features/reminders/application/notification_gateway.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/alert_plan.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide Priority;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const _phone = '+919888888888';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reminder: create → OS-scheduled → Done → synced', (
    tester,
  ) async {
    ensureTimeZones();
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
    await supabase.auth.signInWithOtp(phone: _phone);
    await supabase.auth.verifyOTP(
      phone: _phone,
      token: '123456',
      type: OtpType.sms,
    );
    final userId = supabase.auth.currentUser!.id;

    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    final plugin = container.read(notificationsPluginProvider);
    await plugin.initialize(settings: LocalNotificationGateway.initSettings);
    await plugin.cancelAll();
    // iOS drops scheduling requests from apps without permission. Provisional
    // authorisation is granted silently (no system dialog to tap in a test).
    await plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
          provisional: true,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AriaApp()),
    );
    await tester.pumpAndSettle();

    final engine = container.read(syncEngineProvider)!;
    await engine.syncNow();
    // Keep the provider alive while we await it (Riverpod disposes
    // providers nobody listens to).
    final circleSub = container.listen(activeCircleIdProvider, (_, _) {});
    addTearDown(circleSub.close);
    final circleId = await container.read(activeCircleIdProvider.future);
    expect(circleId, isNotNull, reason: 'personal circle synced down');

    // 1. Create (as the editor does) — due in 2 minutes, default follow-ups.
    final service = container.read(reminderServiceProvider)!;
    final id = const Uuid().v4();
    final due = DateTime.now().toUtc().add(const Duration(minutes: 2));
    await service.save(
      Reminder(
        id: id,
        circleId: circleId!,
        createdBy: userId,
        title: 'E2E: take medicine',
        category: ReminderCategory.health,
        startAt: due,
        timezone: container.read(deviceTimeZoneProvider),
      ),
    );
    await service.refresh();

    // 2. The OS holds the main alert + 3 follow-ups, with stable ids.
    final pending = await plugin.pendingNotificationRequests();
    final mine = pending
        .where((p) => parsePayload(stripFireTime(p.payload))?.reminderId == id)
        .toList();
    expect(mine, hasLength(4));
    expect(mine.map((p) => p.id).toSet(), {
      for (var k = 0; k < 4; k++) alertId(id, due, k),
    });
    expect(mine.first.title, '💊 E2E: take medicine');

    // 3. "Done" from the notification.
    await service.handleAction(AlertAction.done, (
      reminderId: id,
      occurrence: due,
    ));
    final after = await plugin.pendingNotificationRequests();
    expect(
      after.where(
        (p) => parsePayload(stripFireTime(p.payload))?.reminderId == id,
      ),
      isEmpty,
      reason: 'follow-ups cancelled once done',
    );

    // 4. Synced: server sees it done, with a done event.
    final result = await engine.syncNow();
    expect(result.failed, 0);
    final row = await supabase.from('reminders').select().eq('id', id).single();
    expect(row['status'], 'done');
    expect(row['last_done_at'], isNotNull);
    final events = await supabase
        .from('reminder_events')
        .select('type')
        .eq('reminder_id', id);
    expect(events.map((e) => e['type']), ['done']);

    // Cleanup.
    await supabase.from('reminders').delete().eq('id', id);
    await supabase.auth.signOut();
  });
}
