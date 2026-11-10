import 'dart:async';
import 'dart:io';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:aria/app.dart';
import 'package:aria/core/config/env.dart';
import 'package:aria/core/router/app_router.dart';
import 'package:aria/core/telemetry/telemetry.dart';
import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/features/reminders/application/background_actions.dart';
import 'package:aria/features/reminders/application/notification_gateway.dart';
import 'package:aria/features/reminders/application/notification_router.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;

Future<void> main() async {
  final startup = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.hasSupabase) {
    runApp(const _MissingConfigApp());
    return;
  }

  // Errors are captured from the first line; Firebase attaches later.
  final telemetry = DeferredTelemetry();
  installErrorHandlers(telemetry);

  // Only what the first frame needs, all local and in parallel. Firebase
  // starts after the first frame (it isn't needed to show Today).
  ensureTimeZones();
  final (prefs, zone, _, _, _) = await (
    SharedPreferences.getInstance(),
    _detectZone(),
    Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
    ),
    // Hindi month/day names for DateFormat (UI language can be हिन्दी).
    initializeDateFormatting('hi_IN'),
    // Spoken reminders fire through exact alarms in a background isolate.
    !kIsWeb && Platform.isAndroid
        ? AndroidAlarmManager.initialize()
        : Future.value(true),
  ).wait;
  tz.setLocalLocation(locationOf(zone));
  unawaited(prefs.setString(kZonePrefKey, zone));

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      deviceTimeZoneProvider.overrideWith(() => DeviceTimeZone(zone)),
      telemetryProvider.overrideWithValue(telemetry),
    ],
  );

  final plugin = container.read(notificationsPluginProvider);
  await plugin.initialize(
    settings: LocalNotificationGateway.initSettings,
    onDidReceiveNotificationResponse: (r) =>
        unawaited(handleNotificationResponse(container, r)),
    onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationAction,
  );
  unawaited(LocalNotificationGateway(plugin).createChannels());
  final launch = await plugin.getNotificationAppLaunchDetails();

  // Travelling: pick up a new device timezone whenever the app resumes.
  AppLifecycleListener(
    onResume: () async {
      final z = await _detectZone();
      if (container.read(deviceTimeZoneProvider.notifier).update(z)) {
        tz.setLocalLocation(locationOf(z));
        await prefs.setString(kZonePrefKey, z);
        unawaited(container.read(reminderServiceProvider)?.refresh());
      }
    },
  );

  runApp(
    UncontrolledProviderScope(container: container, child: const AriaApp()),
  );

  // Time to first frame (debug log; analytics only with consent).
  unawaited(
    WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) async {
      final ms = startup.elapsedMilliseconds;
      debugPrint('startup: first frame in $ms ms');
      telemetry.event(TelemetryEvent.appStart, {'ms': startupBucket(ms)});
      final firebase = await FirebaseTelemetry.init();
      telemetry.attach(firebase ?? const NoopTelemetry());
    }),
  );

  // Entry points outside the app: long-press shortcuts and home widgets.
  _wireShortcutsAndWidgets(container);

  // Opened by tapping a notification (or an urgent full-screen intent).
  final response = launch?.notificationResponse;
  if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(handleNotificationResponse(container, response)),
    );
  }
}

Future<String> _detectZone() async {
  try {
    return (await FlutterTimezone.getLocalTimezone()).identifier;
  } on Object {
    return 'Asia/Kolkata';
  }
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            tr(
              'Supabase is not configured.\n\nRun with:\nflutter run --dart-define-from-file=env/dev.json',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}

void _wireShortcutsAndWidgets(ProviderContainer container) {
  void open(String location) => container.read(routerProvider).go(location);

  const shortcuts = QuickActions();
  unawaited(
    shortcuts.initialize((type) {
      open(switch (type) {
        'talk' => '/talk',
        'new_reminder' => '/reminder/new',
        'lists' => '/lists',
        'routines' => '/routines',
        _ => '/today',
      });
    }),
  );
  unawaited(
    shortcuts.setShortcutItems(const [
      ShortcutItem(type: 'new_reminder', localizedTitle: 'New reminder'),
      ShortcutItem(type: 'talk', localizedTitle: 'Talk to Aria'),
      ShortcutItem(type: 'lists', localizedTitle: 'Lists'),
      ShortcutItem(type: 'routines', localizedTitle: 'Start routine'),
    ]),
  );

  // Widget taps carry aria:///<path> (see AriaWidgets.kt / AriaWidget.swift).
  void fromWidget(Uri? uri) {
    if (uri != null && uri.path.isNotEmpty) {
      open(uri.path + (uri.hasQuery ? '?${uri.query}' : ''));
    }
  }

  unawaited(HomeWidget.initiallyLaunchedFromHomeWidget().then(fromWidget));
  HomeWidget.widgetClicked.listen(fromWidget);
}
