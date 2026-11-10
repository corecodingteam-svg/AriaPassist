import 'dart:convert';
import 'dart:io' show Platform;

import 'package:aria/features/reminders/domain/alert_plan.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/voice/application/voice_engine.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln
    show Priority;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide Priority;
import 'package:timezone/timezone.dart' as tz;

/// Notification action ids (shared by Android actions and iOS category).
abstract final class AlertAction {
  static const done = 'done';
  static const snooze15 = 'snooze15';
  static const snooze60 = 'snooze60';
  static const open = 'open';
  static const moveTomorrow = 'move_tomorrow';
}

const kReminderCategoryId = 'reminder';
const kWrapUpCategoryId = 'wrapup';

/// Parsed notification payload.
typedef AlertRef = ({String reminderId, DateTime occurrence});

AlertRef? parsePayload(String? payload) {
  if (payload == null) return null;
  try {
    final j = jsonDecode(payload) as Map<String, dynamic>;
    return (
      reminderId: j['r'] as String,
      occurrence: DateTime.parse(j['o'] as String).toUtc(),
    );
  } on Object {
    return null;
  }
}

@immutable
class NotificationStatus {
  const NotificationStatus({
    required this.notificationsAllowed,
    required this.exactAlarmsAllowed,
  });
  static const unknown = NotificationStatus(
    notificationsAllowed: true,
    exactAlarmsAllowed: true,
  );

  final bool notificationsAllowed;
  final bool exactAlarmsAllowed;
  bool get allGood => notificationsAllowed && exactAlarmsAllowed;
}

/// What the reminder engine needs from the OS. Faked in tests.
abstract interface class NotificationGateway {
  /// Make the OS's pending set equal [plan] (adds, replaces, removes).
  Future<void> apply(List<PlannedAlert> plan);

  /// Remove already-*displayed* alerts for a reminder (after done/snooze).
  Future<void> dismissFor(String reminderId);

  Future<NotificationStatus> status();
  Future<bool> requestPermissions();

  /// Schedules a test reminder through the normal (exact-alarm) path.
  Future<void> sendTest(Duration delay);
  Future<void> openExactAlarmSettings();
}

/// Display options from Settings (privacy / reminder style).
@immutable
class GatewayOptions {
  const GatewayOptions({
    this.hideOnLockScreen = false,
    this.fullScreenUrgent = true,
  });
  final bool hideOnLockScreen;
  final bool fullScreenUrgent;
}

/// flutter_local_notifications implementation.
class LocalNotificationGateway implements NotificationGateway {
  LocalNotificationGateway(
    this._plugin, {
    this._voice = const NoVoiceDelivery(),
    this._profile,
    this._options,
  });

  final FlutterLocalNotificationsPlugin _plugin;
  final VoiceDelivery _voice;
  final VoiceProfile Function()? _profile;
  final GatewayOptions Function()? _options;
  GatewayOptions get _opts => _options?.call() ?? const GatewayOptions();
  bool _exactAllowed = true;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  // ----------------------------------------------------------- setup

  static InitializationSettings get initSettings => InitializationSettings(
    android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      // Asked in context (first reminder), never at launch.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          kReminderCategoryId,
          actions: [
            DarwinNotificationAction.plain(AlertAction.done, tr('✓ Done')),
            DarwinNotificationAction.plain(
              AlertAction.snooze15,
              tr('⏰ 15 min'),
            ),
            DarwinNotificationAction.plain(
              AlertAction.snooze60,
              tr('⏰ 1 hour'),
            ),
            DarwinNotificationAction.plain(
              AlertAction.open,
              tr('Open'),
              options: {DarwinNotificationActionOption.foreground},
            ),
          ],
        ),
        DarwinNotificationCategory(
          kWrapUpCategoryId,
          actions: [
            DarwinNotificationAction.plain(
              AlertAction.moveTomorrow,
              tr('Move pending to tomorrow'),
            ),
            DarwinNotificationAction.plain(
              AlertAction.open,
              tr('Open'),
              options: {DarwinNotificationActionOption.foreground},
            ),
          ],
        ),
      ],
    ),
  );

  /// Android channels: one per category (users can fine-tune each in system
  /// settings) + Urgent + Quiet (low priority) + Vibrate-only.
  static final channels = <AndroidNotificationChannel>[
    for (final c in ReminderCategory.values)
      AndroidNotificationChannel(
        'cat_${c.name}',
        '${c.emoji} ${c.label}',
        description: tr('{0} reminders', [c.label]),
        importance: Importance.high,
      ),
    AndroidNotificationChannel(
      'urgent',
      tr('🚨 Urgent'),
      description: tr('Urgent reminders: louder, full-screen when allowed'),
      importance: Importance.max,
    ),
    AndroidNotificationChannel(
      'quiet',
      tr('🔕 Low priority'),
      description: tr('Shown silently in the shade'),
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    ),
    AndroidNotificationChannel(
      'voice',
      tr('🔊 Spoken reminders'),
      description: tr(
        'Aria speaks these, so the notification itself is silent',
      ),
      importance: Importance.high,
      playSound: false,
    ),
    AndroidNotificationChannel(
      'briefings',
      tr('☀️ Briefings'),
      description: tr('Morning briefing and night wrap-up'),
    ),
    AndroidNotificationChannel(
      'vibrate',
      tr('📳 Vibrate only'),
      description: tr('Reminders set to vibrate without sound'),
      importance: Importance.high,
      playSound: false,
    ),
  ];

  Future<void> createChannels() async {
    final a = _android;
    if (a == null) return;
    for (final ch in channels) {
      await a.createNotificationChannel(ch);
    }
  }

  // ----------------------------------------------------------- scheduling

  @override
  Future<void> apply(List<PlannedAlert> plan) async {
    await _refreshExact();
    final voice = _profile?.call();
    final speaking = voice == null
        ? const <PlannedAlert>[]
        : plan.where((a) => a.speaks).toList();

    // iOS: the spoken line *is* the notification sound. Render what's
    // missing (cached by content), then prune old files.
    final sounds = <int, String>{};
    if (voice != null && !kIsWeb && Platform.isIOS) {
      for (final a in speaking) {
        final name = await _voice.soundFor(a.spoken!, voice);
        if (name != null) sounds[a.id] = name;
      }
      await DeviceSpeaker.pruneSounds(sounds.values.toSet());
    }
    // Android: exact alarms that speak in a background isolate.
    if (voice != null) {
      try {
        await _voice.syncSpokenAlarms(speaking, voice);
      } on Object catch (e) {
        debugPrint('spoken alarms failed: $e');
      }
    }

    final pending = await _plugin.pendingNotificationRequests();
    final wanted = {for (final a in plan) a.id: a};
    for (final p in pending) {
      if (!wanted.containsKey(p.id)) await _plugin.cancel(id: p.id);
    }
    // zonedSchedule with an existing id replaces it, so changed
    // times/titles/voices are updated in place; unchanged ones are skipped.
    final pendingById = {for (final p in pending) p.id: p};
    for (final a in plan) {
      // Option changes alter the payload, so affected alerts get rescheduled.
      final payload =
          '${_payload(a, sounds[a.id])}|'
          '${_opts.hideOnLockScreen ? 'h' : ''}${_opts.fullScreenUrgent ? 'f' : ''}';
      final existing = pendingById[a.id];
      if (existing != null &&
          existing.title == a.title &&
          existing.body == a.body &&
          existing.payload == payload) {
        continue;
      }
      await _schedule(a, payload: payload, sound: sounds[a.id]);
    }
  }

  /// `<json>|<fireMillis>|<voiceKey>` — lets `apply` detect any change.
  static String _payload(PlannedAlert a, String? sound) =>
      '${a.payload}|${a.fireAt.millisecondsSinceEpoch}|'
      '${a.speaks ? (sound ?? a.spoken.hashCode) : (a.quiet ? 'q' : '')}';

  Future<void> _schedule(
    PlannedAlert a, {
    required String payload,
    String? sound,
  }) async {
    ensureTimeZones();
    final urgent = a.priority == Priority.urgent;
    final briefing = a.kind != AlertKind.reminder;
    final androidSpeaks = a.speaks && !kIsWeb && Platform.isAndroid;
    AndroidNotificationChannel ch(String id) =>
        channels.firstWhere((c) => c.id == id);
    final channel = switch (a) {
      _ when a.quiet => ch('quiet'),
      _ when urgent => ch('urgent'),
      _ when androidSpeaks => ch('voice'),
      _ when briefing => ch('briefings'),
      _ when a.priority == Priority.low => ch('quiet'),
      _ when a.mode == NotifyMode.vibrate => ch('vibrate'),
      _ => ch('cat_${a.category.name}'),
    };
    final actions = switch (a.kind) {
      AlertKind.reminder => [
        AndroidNotificationAction(AlertAction.done, tr('✓ Done')),
        AndroidNotificationAction(AlertAction.snooze15, tr('⏰ 15 min')),
        const AndroidNotificationAction(AlertAction.snooze60, '⏰ 1 h'),
        AndroidNotificationAction(
          AlertAction.open,
          tr('Open'),
          showsUserInterface: true,
        ),
      ],
      AlertKind.nightWrapUp => [
        AndroidNotificationAction(
          AlertAction.moveTomorrow,
          tr('Move pending to tomorrow'),
        ),
        AndroidNotificationAction(
          AlertAction.open,
          tr('Open'),
          showsUserInterface: true,
        ),
      ],
      AlertKind.morningBriefing ||
      AlertKind.routine ||
      AlertKind.billing => const <AndroidNotificationAction>[],
    };
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: channel.importance,
        priority: urgent ? fln.Priority.max : fln.Priority.high,
        category: urgent
            ? AndroidNotificationCategory.alarm
            : AndroidNotificationCategory.reminder,
        fullScreenIntent: urgent && !a.quiet && _opts.fullScreenUrgent,
        // Lock screen shows "Contents hidden" instead of the reminder.
        visibility: _opts.hideOnLockScreen
            ? NotificationVisibility.private
            : NotificationVisibility.public,
        groupKey: 'aria.reminders',
        styleInformation: briefing ? BigTextStyleInformation(a.body) : null,
        actions: actions,
      ),
      iOS: DarwinNotificationDetails(
        categoryIdentifier: switch (a.kind) {
          AlertKind.reminder => kReminderCategoryId,
          AlertKind.nightWrapUp => kWrapUpCategoryId,
          AlertKind.morningBriefing ||
          AlertKind.routine ||
          AlertKind.billing => null,
        },
        threadIdentifier: a.reminderId,
        presentSound:
            !a.quiet &&
            a.mode != NotifyMode.vibrate &&
            a.priority != Priority.low,
        sound: sound,
        interruptionLevel: a.quiet || a.priority == Priority.low
            ? InterruptionLevel.passive
            : urgent
            ? InterruptionLevel.timeSensitive
            : InterruptionLevel.active,
      ),
    );
    await _plugin.zonedSchedule(
      id: a.id,
      scheduledDate: tz.TZDateTime.from(a.fireAt, tz.UTC),
      notificationDetails: details,
      androidScheduleMode: _exactAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      title: a.title,
      body: a.body,
      payload: payload,
    );
  }

  @override
  Future<void> dismissFor(String reminderId) async {
    final active = await _plugin.getActiveNotifications();
    for (final n in active) {
      if (parsePayload(stripFireTime(n.payload))?.reminderId == reminderId &&
          n.id != null) {
        await _plugin.cancel(id: n.id!);
      }
    }
  }

  // ----------------------------------------------------------- permissions

  Future<void> _refreshExact() async {
    if (!Platform.isAndroid) return;
    _exactAllowed = await _android?.canScheduleExactNotifications() ?? true;
  }

  @override
  Future<NotificationStatus> status() async {
    if (Platform.isAndroid) {
      final a = _android;
      return NotificationStatus(
        notificationsAllowed: await a?.areNotificationsEnabled() ?? true,
        exactAlarmsAllowed: await a?.canScheduleExactNotifications() ?? true,
      );
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final perms = await ios?.checkPermissions();
    return NotificationStatus(
      notificationsAllowed: perms?.isEnabled ?? true,
      exactAlarmsAllowed: true,
    );
  }

  static const kTestAlertId = 999999;

  @override
  Future<void> sendTest(Duration delay) async {
    await _refreshExact();
    final at = DateTime.now().toUtc().add(delay);
    await _schedule(
      PlannedAlert(
        id: kTestAlertId,
        reminderId: 'test',
        occurrence: at,
        attempt: 0,
        totalAttempts: 1,
        fireAt: at,
        title: tr('✅ Test reminder'),
        body: tr('If you can see this, reminders are working.'),
        category: ReminderCategory.personal,
        priority: Priority.normal,
        mode: NotifyMode.text,
      ),
      payload: '{"r":"test","o":"${at.toIso8601String()}"}|test',
    );
  }

  /// Opens the OS notification settings for Aria (iOS "Show Previews").
  Future<void> openNotificationSettings() async {
    await _plugin.openAppNotificationSettings();
  }

  @override
  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      return await _android?.requestNotificationsPermission() ?? true;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
  }

  @override
  Future<void> openExactAlarmSettings() async {
    await _android?.requestExactAlarmsPermission();
  }
}

/// Payloads carry `<json>|<fireMillis>|<voiceKey>`; strip the suffix
/// before parsing (the JSON never contains '|').
String? stripFireTime(String? payload) {
  if (payload == null) return null;
  final i = payload.indexOf('|');
  return i < 0 ? payload : payload.substring(0, i);
}
