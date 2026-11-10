import 'dart:ui';

import 'package:aria/data/local/app_database.dart';
import 'package:aria/data/sync/local_store.dart';
import 'package:aria/features/reminders/application/notification_gateway.dart';
import 'package:aria/features/reminders/application/reminder_service.dart';
import 'package:aria/features/reminders/data/reminder_repository.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/voice/application/voice_engine.dart';
import 'package:aria/features/voice/application/voice_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted on sign-in so a background isolate knows whose data it is.
const kUserIdPrefKey = 'aria.user_id';

/// Last known device timezone, for background isolates.
const kZonePrefKey = 'aria.zone';

/// Runs in a background isolate when Done / Snooze is tapped while the app
/// is not in the foreground. Changes go to SQLite + the outbox; they sync
/// the next time the app runs.
@pragma('vm:entry-point')
Future<void> onBackgroundNotificationAction(NotificationResponse r) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  ensureTimeZones();

  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString(kUserIdPrefKey);
  if (userId == null) return;

  final db = AppDatabase();
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(settings: LocalNotificationGateway.initSettings);
    // Same voice settings as the app, so re-planning after this action
    // keeps spoken reminders spoken.
    final settings = readVoiceSettings(prefs);
    final service = ReminderService(
      repo: ReminderRepository(db, LocalStore(db), userId: userId),
      gateway: LocalNotificationGateway(
        plugin,
        voice: PlatformVoiceDelivery(DeviceSpeaker(), prefs),
        profile: () => VoiceProfile.of(settings),
      ),
      userId: userId,
      voiceSettings: () => settings,
      zone: () => prefs.getString(kZonePrefKey) ?? 'Asia/Kolkata',
    );
    await service.handleAction(
      r.actionId,
      parsePayload(stripFireTime(r.payload)),
    );
  } finally {
    await db.close();
  }
}
