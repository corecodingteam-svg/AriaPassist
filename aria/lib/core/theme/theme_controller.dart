import 'dart:async';
import 'dart:convert';

import 'package:aria/core/theme/theme_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in `main()` with the already-loaded instance so the first
/// frame is painted in the user's theme (no flash).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);

const _kThemeKey = 'aria.theme.v1';

class ThemeController extends Notifier<ThemeSettings> {
  @override
  ThemeSettings build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_kThemeKey);
    if (raw == null) return const ThemeSettings();
    try {
      return ThemeSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return const ThemeSettings();
    }
  }

  void update(ThemeSettings Function(ThemeSettings s) change) {
    state = change(state);
    // Fire-and-forget; the UI has already updated. Server sync of
    // user_settings.theme_json is added with the settings repo (Phase 4).
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setString(_kThemeKey, jsonEncode(state.toJson())),
    );
  }

  void setMode(ThemeMode m) => update((s) => s.copyWith(mode: m));
  void setPreset(String id) => update((s) => s.copyWith(presetId: id));
  void setFontSize(FontSizeOption f) => update((s) => s.copyWith(fontSize: f));
  void setHighContrast({required bool value}) =>
      update((s) => s.copyWith(highContrast: value));
  void setReduceMotion({required bool value}) =>
      update((s) => s.copyWith(reduceMotion: value));
  void setCustomAccent(int? argb) =>
      update((s) => s.copyWith(customAccent: () => argb));
  void reset() => update((_) => const ThemeSettings());
}

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeSettings>(ThemeController.new);
