import 'dart:async';

import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/core/theme/theme_settings.dart';
import 'package:aria/data/providers.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/preferences/domain/app_prefs.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/voice/application/voice_providers.dart';
import 'package:aria/features/voice/domain/voice_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Local settings ⇄ `public.user_settings` columns. Pure, unit-tested.
abstract final class SettingsMapping {
  static Map<String, dynamic> toRow(
    ThemeSettings theme,
    VoiceSettings voice,
    AppPrefs prefs,
  ) => {
    'voice_id': voice.voiceId,
    'pa_name': voice.paName,
    'speed': double.parse(voice.speed.toStringAsFixed(2)),
    'pitch': double.parse(voice.pitch.toStringAsFixed(2)),
    'personality': voice.personality.name,
    'language': voice.language.name,
    'notify_mode_default': voice.defaultMode.name,
    'category_overrides_json': {
      for (final e in voice.categoryModes.entries) e.key.name: e.value.name,
    },
    'theme_json': theme.toJson(),
    'simple_mode': prefs.simpleMode,
    'quick_actions_json': prefs.quickActions.map((q) => q.name).toList(),
    'quiet_hours_json': voice.quietHours.toJson(),
    'follow_up_json': prefs.followUp.toJson(),
    'briefing_json': voice.briefings.toJson(),
    'extra_json': {
      'voice': {
        'spoken_confirmations': voice.spokenConfirmations,
        'use_alarm_stream': voice.useAlarmStream,
      },
      'prefs': prefs.toJson(),
    },
  };

  static (ThemeSettings, VoiceSettings, AppPrefs) fromRow(
    Map<String, dynamic> row,
  ) {
    final extra = row['extra_json'] as Map<String, dynamic>? ?? const {};
    final extraVoice = extra['voice'] as Map<String, dynamic>? ?? const {};
    final prefsJson = extra['prefs'] as Map<String, dynamic>?;
    final voice = VoiceSettings.fromJson({
      'voice_id': row['voice_id'],
      'pa_name': row['pa_name'],
      'speed': row['speed'],
      'pitch': row['pitch'],
      'personality': row['personality'],
      'language': row['language'],
      'default_mode': row['notify_mode_default'],
      'category_modes': row['category_overrides_json'],
      'quiet_hours': row['quiet_hours_json'],
      'briefings': row['briefing_json'],
      ...extraVoice,
    });
    final follow = FollowUp.fromJson(
      row['follow_up_json'] as Map<String, dynamic>?,
    );
    final prefs =
        (prefsJson == null ? const AppPrefs() : AppPrefs.fromJson(prefsJson))
            .copyWith(
              simpleMode: row['simple_mode'] as bool?,
              followUpEnabled: follow.enabled,
              followUpEveryMin: follow.everyMin,
              followUpMax: follow.maxAttempts,
            );
    final theme = ThemeSettings.fromJson(
      row['theme_json'] as Map<String, dynamic>? ?? const {},
    );
    return (theme, voice, prefs);
  }
}

const _kChangedAt = 'aria.settings.changed_at';

/// Keeps settings in sync across devices (last change wins).
class SettingsSync {
  SettingsSync(this.ref, this.client, this.userId);
  final Ref ref;
  final SupabaseClient client;
  final String userId;
  Timer? _debounce;
  bool _applying = false;

  /// On sign-in / start: take the server's settings if they're newer than
  /// this device's last local change (or this device never changed any).
  Future<void> pull() async {
    try {
      final row = await client
          .from('user_settings')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) return;
      final prefs = ref.read(sharedPreferencesProvider);
      final local = DateTime.tryParse(prefs.getString(_kChangedAt) ?? '');
      final server = DateTime.tryParse(row['updated_at'] as String? ?? '');
      if (local != null && server != null && !server.isAfter(local)) return;
      final (theme, voice, appPrefs) = SettingsMapping.fromRow(row);
      _applying = true;
      ref.read(themeControllerProvider.notifier).update((_) => theme);
      ref.read(voiceSettingsProvider.notifier).update((_) => voice);
      // Device-local state (onboarding, tips) is never overwritten.
      final current = ref.read(appPrefsProvider);
      ref
          .read(appPrefsProvider.notifier)
          .update(
            (_) => appPrefs.copyWith(
              onboarded: current.onboarded || appPrefs.onboarded,
              dismissedTips: current.dismissedTips,
              // Never replace a name with "no name".
              userName: () => appPrefs.userName ?? current.userName,
            ),
          );
      _applying = false;
      if (server != null) {
        await prefs.setString(_kChangedAt, server.toIso8601String());
      }
    } on Object catch (e) {
      _applying = false;
      debugPrint('settings pull failed: $e');
    }
  }

  /// Called on every local settings change.
  void changed() {
    if (_applying) return;
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setString(_kChangedAt, DateTime.now().toUtc().toIso8601String()),
    );
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(push()));
  }

  Future<void> push() async {
    try {
      await client
          .from('user_settings')
          .update(
            SettingsMapping.toRow(
              ref.read(themeControllerProvider),
              ref.read(voiceSettingsProvider),
              ref.read(appPrefsProvider),
            ),
          )
          .eq('user_id', userId);
    } on Object catch (e) {
      // Offline: the next change (or next start) pushes again.
      debugPrint('settings push failed: $e');
    }
  }

  void dispose() => _debounce?.cancel();
}

final settingsSyncProvider = Provider<SettingsSync?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  final SupabaseClient client;
  try {
    client = ref.watch(supabaseClientProvider);
  } on Object {
    return null; // tests without Supabase
  }
  final sync = SettingsSync(ref, client, uid);
  ref
    ..listen(themeControllerProvider, (_, _) => sync.changed())
    ..listen(voiceSettingsProvider, (_, _) => sync.changed())
    ..listen(appPrefsProvider, (_, _) => sync.changed())
    ..onDispose(sync.dispose);
  unawaited(sync.pull());
  return sync;
});
