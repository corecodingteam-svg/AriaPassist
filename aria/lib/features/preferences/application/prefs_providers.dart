import 'dart:async';
import 'dart:convert';

import 'package:aria/core/telemetry/telemetry.dart';
import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/features/preferences/domain/app_prefs.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kAppPrefsKey = 'aria.prefs.v1';

AppPrefs readAppPrefs(SharedPreferences prefs) {
  final raw = prefs.getString(kAppPrefsKey);
  if (raw == null) return const AppPrefs();
  try {
    return AppPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } on Object {
    return const AppPrefs();
  }
}

class AppPrefsController extends Notifier<AppPrefs> {
  @override
  AppPrefs build() => readAppPrefs(ref.read(sharedPreferencesProvider));

  void update(AppPrefs Function(AppPrefs p) change) {
    state = change(state);
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setString(kAppPrefsKey, jsonEncode(state.toJson())),
    );
  }

  void dismissTip(String id) =>
      update((p) => p.copyWith(dismissedTips: {...p.dismissedTips, id}));
}

final appPrefsProvider = NotifierProvider<AppPrefsController, AppPrefs>(
  AppPrefsController.new,
);

/// Haptic feedback that respects Settings › Haptics.
class Haptics {
  Haptics({required this._enabled});
  final bool _enabled;

  Future<void> light() async {
    if (_enabled) await HapticFeedback.lightImpact();
  }

  Future<void> medium() async {
    if (_enabled) await HapticFeedback.mediumImpact();
  }

  Future<void> selection() async {
    if (_enabled) await HapticFeedback.selectionClick();
  }
}

final hapticsProvider = Provider<Haptics>(
  (ref) =>
      Haptics(enabled: ref.watch(appPrefsProvider.select((p) => p.haptics))),
);

/// Applies the privacy choices (Settings › Privacy) to crash reporting and
/// analytics, now and whenever they change.
final telemetryConsentProvider = Provider<void>((ref) {
  final analytics = ref.watch(appPrefsProvider.select((p) => p.analytics));
  final crashes = ref.watch(appPrefsProvider.select((p) => p.crashReports));
  unawaited(
    ref
        .read(telemetryProvider)
        .setConsent(analytics: analytics, crashes: crashes),
  );
});
