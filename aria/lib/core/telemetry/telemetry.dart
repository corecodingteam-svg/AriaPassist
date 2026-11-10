import 'dart:async';
import 'dart:io';

import 'package:aria/core/config/env.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Product events. Parameters are enums/counts only — never reminder
/// titles, names, phone numbers or note text.
enum TelemetryEvent {
  onboardingCompleted,
  reminderCreated, // source: voice | tap | quick_action | assistant_list
  reminderDone,
  reminderSnoozed,
  voiceParsed, // engine: llm | rules; ok: bool
  listCreated,
  noteSaved,
  routineStarted,
  circleCreated,
  inviteAccepted,
  reminderAssigned,
  paywallShown, // feature
  trialStarted, // plan
  purchaseStarted, // plan, period
  purchaseCompleted, // plan
  promoRedeemed,
  suggestionAccepted, // kind
  locationReminderCreated,
  appStart, // ms (time to first frame, bucketed)
}

/// Crash + analytics sink. Consent is applied by [setConsent].
abstract interface class Telemetry {
  Future<void> setConsent({required bool analytics, required bool crashes});
  void event(TelemetryEvent e, [Map<String, Object> params = const {}]);
  void recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  });
  void screen(String name);
}

class NoopTelemetry implements Telemetry {
  const NoopTelemetry();
  @override
  Future<void> setConsent({
    required bool analytics,
    required bool crashes,
  }) async {}
  @override
  void event(TelemetryEvent e, [Map<String, Object> params = const {}]) {}
  @override
  void recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  }) => debugPrint('error${reason == null ? '' : ' ($reason)'}: $error');
  @override
  void screen(String name) {}
}

/// Firebase Crashlytics + Analytics. Analytics stays disabled until the
/// user opts in; crash collection follows the crash-report setting.
class FirebaseTelemetry implements Telemetry {
  FirebaseTelemetry._();

  /// Null when this build has no Firebase config (dev, tests).
  static Future<FirebaseTelemetry?> init() async {
    final options = Env.firebaseOptions;
    if (options == null) return null;
    try {
      await Firebase.initializeApp(options: options);
      // Off until consent is applied from prefs (never collect early).
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
      return FirebaseTelemetry._();
    } on Object catch (e) {
      debugPrint('Firebase init failed: $e');
      return null;
    }
  }

  bool _crashes = false;

  @override
  Future<void> setConsent({
    required bool analytics,
    required bool crashes,
  }) async {
    _crashes = crashes && !kDebugMode;
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
      analytics && !kDebugMode,
    );
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      _crashes,
    );
  }

  @override
  void event(TelemetryEvent e, [Map<String, Object> params = const {}]) =>
      unawaited(
        FirebaseAnalytics.instance
            .logEvent(
              name: snake(e.name),
              parameters: params.isEmpty ? null : params,
            )
            .catchError((Object _) {}),
      );

  @override
  void recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  }) {
    debugPrint('error: $error');
    if (!_crashes) return;
    unawaited(
      FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        fatal: fatal,
        reason: reason,
      ),
    );
  }

  @override
  void screen(String name) => unawaited(
    FirebaseAnalytics.instance
        .logScreenView(screenName: name)
        .catchError((Object _) {}),
  );
}

/// camelCase → snake_case (Firebase event naming).
String snake(String s) =>
    s.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

/// Overridden in main() with the real sink.
final telemetryProvider = Provider<Telemetry>((_) => const NoopTelemetry());

/// Routes uncaught Flutter/Dart errors to [t].
void installErrorHandlers(Telemetry t) {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    previous?.call(details);
    t.recordError(
      details.exception,
      details.stack,
      fatal: !kDebugMode && !details.silent,
      reason: details.context?.toDescription(),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    t.recordError(error, stack, fatal: true);
    return true;
  };
}

/// Platform label for event params.
String get platformName => kIsWeb ? 'web' : Platform.operatingSystem;

/// Screen views from the router.
class TelemetryRouteObserver extends NavigatorObserver {
  TelemetryRouteObserver(this.t);
  final Telemetry t;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null) t.screen(name);
  }
}

/// Starts with no backend and forwards to the real one once it's ready
/// (Firebase initialises after the first frame, off the critical path).
/// Events and errors before then are buffered, not lost.
class DeferredTelemetry implements Telemetry {
  Telemetry? _inner;
  final _pending = <void Function(Telemetry)>[];

  void attach(Telemetry t) {
    _inner = t;
    for (final f in _pending) {
      f(t);
    }
    _pending.clear();
  }

  void _run(void Function(Telemetry) f) {
    final t = _inner;
    if (t != null) {
      f(t);
    } else if (_pending.length < 200) {
      _pending.add(f);
    }
  }

  @override
  Future<void> setConsent({
    required bool analytics,
    required bool crashes,
  }) async => _run(
    (t) => unawaited(t.setConsent(analytics: analytics, crashes: crashes)),
  );
  @override
  void event(TelemetryEvent e, [Map<String, Object> params = const {}]) =>
      _run((t) => t.event(e, params));
  @override
  void recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  }) {
    debugPrint('error: $error');
    _run((t) => t.recordError(error, stack, fatal: fatal, reason: reason));
  }

  @override
  void screen(String name) => _run((t) => t.screen(name));
}

/// 0–500, 500–1000, … ms buckets (no exact device fingerprinting).
int startupBucket(int ms) => (ms ~/ 500) * 500;
