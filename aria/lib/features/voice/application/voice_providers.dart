import 'dart:async';
import 'dart:convert';

import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/features/voice/application/speech_input.dart';
import 'package:aria/features/voice/application/voice_engine.dart';
import 'package:aria/features/voice/domain/voice_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kVoiceSettingsKey = 'aria.voice.v1';

/// Reads voice settings straight from prefs (also used by background
/// isolates, which have no ProviderContainer).
VoiceSettings readVoiceSettings(SharedPreferences prefs) {
  final raw = prefs.getString(kVoiceSettingsKey);
  if (raw == null) return const VoiceSettings();
  try {
    return VoiceSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } on Object {
    return const VoiceSettings();
  }
}

class VoiceSettingsController extends Notifier<VoiceSettings> {
  @override
  VoiceSettings build() =>
      readVoiceSettings(ref.read(sharedPreferencesProvider));

  void update(VoiceSettings Function(VoiceSettings s) change) {
    state = change(state);
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setString(kVoiceSettingsKey, jsonEncode(state.toJson())),
    );
  }
}

final voiceSettingsProvider =
    NotifierProvider<VoiceSettingsController, VoiceSettings>(
      VoiceSettingsController.new,
    );

final voiceProfileProvider = Provider<VoiceProfile>(
  (ref) => VoiceProfile.of(ref.watch(voiceSettingsProvider)),
);

final deviceSpeakerProvider = Provider<DeviceSpeaker>((_) => DeviceSpeaker());

final speakerProvider = Provider<Speaker>(
  (ref) => ref.watch(deviceSpeakerProvider),
);

final voiceDeliveryProvider = Provider<VoiceDelivery>(
  (ref) => PlatformVoiceDelivery(
    ref.watch(deviceSpeakerProvider),
    ref.watch(sharedPreferencesProvider),
  ),
);

final speechInputProvider = Provider<SpeechInput>((_) => DeviceSpeechInput());
