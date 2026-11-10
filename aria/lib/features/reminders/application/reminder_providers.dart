import 'dart:async';

import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/data/providers.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/calendar/calendar.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/lists/organize_providers.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/reminders/application/background_actions.dart';
import 'package:aria/features/reminders/application/notification_gateway.dart';
import 'package:aria/features/reminders/application/reminder_service.dart';
import 'package:aria/features/reminders/data/reminder_repository.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/voice/application/voice_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridable clock (tests pin time).
final clockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// Ticks every 30 s so time-based sections (Overdue / Now) stay current.
final nowProvider = StreamProvider<DateTime>((ref) {
  final clock = ref.watch(clockProvider);
  final c = StreamController<DateTime>()..add(clock());
  final t = Timer.periodic(const Duration(seconds: 30), (_) => c.add(clock()));
  ref.onDispose(() {
    t.cancel();
    unawaited(c.close());
  });
  return c.stream;
});

/// IANA zone of the device. Seeded in main() and re-checked on resume, so
/// travelling updates times on screen and reschedules alerts.
class DeviceTimeZone extends Notifier<String> {
  DeviceTimeZone([this._initial = 'Asia/Kolkata']);
  final String _initial;

  @override
  String build() => _initial;

  /// Returns true if the zone changed.
  bool update(String zone) {
    if (zone == state) return false;
    state = zone;
    return true;
  }
}

final deviceTimeZoneProvider = NotifierProvider<DeviceTimeZone, String>(
  DeviceTimeZone.new,
);

final notificationsPluginProvider = Provider<FlutterLocalNotificationsPlugin>(
  (_) => FlutterLocalNotificationsPlugin(),
);

final notificationGatewayProvider = Provider<NotificationGateway>(
  (ref) => LocalNotificationGateway(
    ref.watch(notificationsPluginProvider),
    voice: ref.watch(voiceDeliveryProvider),
    profile: () => ref.read(voiceProfileProvider),
    options: () {
      final p = ref.read(appPrefsProvider);
      return GatewayOptions(
        hideOnLockScreen: p.hideOnLockScreen,
        fullScreenUrgent: p.fullScreenUrgent,
      );
    },
  ),
);

final reminderRepositoryProvider = Provider<ReminderRepository?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  return ReminderRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(localStoreProvider),
    userId: uid,
  );
});

/// Lives for the signed-in session; keeps OS notifications in step with
/// data on every change, app resume, and once a minute in the foreground.
final reminderServiceProvider = Provider<ReminderService?>((ref) {
  final repo = ref.watch(reminderRepositoryProvider);
  if (repo == null) return null;
  final service = ReminderService(
    repo: repo,
    gateway: ref.watch(notificationGatewayProvider),
    userId: repo.userId,
    clock: ref.watch(clockProvider),
    voiceSettings: () => ref.read(voiceSettingsProvider),
    briefingText: () => ref.read(appPrefsProvider).dailySummaryText,
    routines: () async {
      final rs = await ref.read(routinesRepositoryProvider)?.all() ?? const [];
      return [
        for (final r in rs)
          (
            id: r.id,
            name: r.name,
            emoji: r.emoji,
            atMinute: r.atMinute,
            days: r.days,
            steps: r.steps.map((s) => s.title).toList(),
          ),
      ];
    },
    zone: () => ref.read(deviceTimeZoneProvider),
    billing: () => ref.read(billingNoticesProvider.notifier).notices(),
    calendar: (day) => ref.read(appPrefsProvider).calendarSync
        ? eventsOn(
            ref.read(calendarBridgeProvider),
            day,
            ref.read(deviceTimeZoneProvider),
          )
        : Future.value(const <CalendarEvent>[]),
  );

  // For the background action isolate.
  unawaited(
    ref.read(sharedPreferencesProvider).setString(kUserIdPrefKey, repo.userId),
  );

  Timer? debounce;
  void schedule() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(service.refresh());
    });
  }

  final sub = repo.watchMine().listen((_) => schedule());
  final routineSub = ref
      .read(routinesRepositoryProvider)
      ?.watchRoutines()
      .listen((_) => schedule());
  // Voice, delivery style, quiet hours or briefing changes → reschedule.
  ref
    ..listen(voiceSettingsProvider, (_, _) => schedule())
    ..listen(appPrefsProvider, (_, _) => schedule())
    ..listen(billingNoticesProvider, (_, _) => schedule());
  final lifecycle = AppLifecycleListener(onResume: schedule);
  final minute = Timer.periodic(const Duration(minutes: 1), (_) => schedule());
  ref.onDispose(() {
    service.closed = true;
    debounce?.cancel();
    minute.cancel();
    lifecycle.dispose();
    unawaited(sub.cancel());
    unawaited(routineSub?.cancel());
  });
  return service;
});

final myRemindersProvider = StreamProvider<List<Reminder>>((ref) {
  final repo = ref.watch(reminderRepositoryProvider);
  return repo?.watchMine() ?? const Stream.empty();
});

// ignore: specify_nonobvious_property_types -- family type is verbose
final reminderByIdProvider = StreamProvider.family<Reminder?, String>((
  ref,
  id,
) {
  final repo = ref.watch(reminderRepositoryProvider);
  return repo?.watch(id) ?? Stream.value(null);
});

final missedProvider = StreamProvider<List<MissedItem>>((ref) {
  final repo = ref.watch(reminderRepositoryProvider);
  return repo?.watchMissed() ?? const Stream.empty();
});

/// The Circle new reminders, lists and notes go into (the active Circle
/// from the switcher; personal by default). Null until the first sync.
final activeCircleIdProvider = StreamProvider<String?>((ref) {
  final repo = ref.watch(circleRepositoryProvider);
  if (repo == null) return Stream.value(null);
  final picked = ref.watch(appPrefsProvider.select((p) => p.activeCircleId));
  return repo.watchMyCircles().map(
    (cs) =>
        cs.where((c) => c.id == picked).firstOrNull?.id ??
        cs.where((c) => c.isPersonal).firstOrNull?.id,
  );
});

/// Permission state for the "reminders may not ring" banner.
final notificationStatusProvider = FutureProvider<NotificationStatus>((ref) {
  final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(lifecycle.dispose);
  return ref.watch(notificationGatewayProvider).status();
});
