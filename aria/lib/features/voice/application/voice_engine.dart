import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:aria/features/reminders/domain/alert_plan.dart';
import 'package:aria/features/voice/domain/voice_settings.dart';
import 'package:aria/features/voice/domain/voices.dart';
import 'package:aria_device/aria_device.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TTS parameters resolved from a voice + the user's speed/pitch.
@immutable
class VoiceProfile {
  const VoiceProfile({
    required this.locale,
    required this.rate,
    required this.pitch,
    required this.gender,
    this.alarmStream = false,
  });

  factory VoiceProfile.of(VoiceSettings s) {
    final v = Voices.byId(s.voiceId);
    final locale = s.language == VoiceLanguage.hi && !v.hinglish
        ? 'hi-IN'
        : v.locale;
    return VoiceProfile(
      locale: locale,
      rate: (s.speed * v.rate).clamp(0.5, 2.0),
      pitch: (s.pitch * v.pitch).clamp(0.5, 2.0),
      gender: v.gender,
      alarmStream: s.useAlarmStream,
    );
  }

  final String locale;

  /// 1.0 = normal.
  final double rate;
  final double pitch;
  final VoiceGender gender;
  final bool alarmStream;

  String get cacheKey => '$locale|$rate|$pitch|${gender.name}';
}

/// Speaks in the foreground (previews, confirmations, briefings).
abstract interface class Speaker {
  Future<void> speak(String text, VoiceProfile voice);
  Future<void> stop();
}

/// Platform voice delivery for alerts that fire while the app is closed.
abstract interface class VoiceDelivery {
  /// iOS: a notification sound file (in Library/Sounds) that speaks
  /// [text], or null to use the default sound.
  Future<String?> soundFor(String text, VoiceProfile voice);

  /// Android: make the scheduled spoken alarms match [alerts].
  Future<void> syncSpokenAlarms(List<PlannedAlert> alerts, VoiceProfile voice);
}

// --------------------------------------------------------------- device

class DeviceSpeaker implements Speaker {
  @override
  Future<void> speak(String text, VoiceProfile voice) async {
    await AriaDevice.stop();
    await AriaDevice.speak(
      text,
      locale: voice.locale,
      rate: voice.rate,
      pitch: voice.pitch,
      alarmStream: voice.alarmStream,
      gender: voice.gender == VoiceGender.any ? null : voice.gender.name,
    );
  }

  @override
  Future<void> stop() => AriaDevice.stop();

  /// iOS only: render [text] to a .caf in Library/Sounds (where
  /// UNNotificationSound looks). Cached by content hash.
  Future<String?> renderNotificationSound(
    String text,
    VoiceProfile voice,
  ) async {
    if (kIsWeb || !Platform.isIOS) return null;
    final lib = await getLibraryDirectory();
    final dir = Directory('${lib.path}/Sounds');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final hash = sha1
        .convert(utf8.encode('${voice.cacheKey}|$text'))
        .toString()
        .substring(0, 16);
    final name = 'aria_$hash.caf';
    final file = File('${dir.path}/$name');
    if (file.existsSync() && file.lengthSync() > 0) return name;
    final ok = await AriaDevice.synthesizeToFile(
      text,
      path: file.path,
      locale: voice.locale,
      rate: voice.rate,
      pitch: voice.pitch,
      gender: voice.gender == VoiceGender.any ? null : voice.gender.name,
    );
    return ok && file.existsSync() && file.lengthSync() > 0 ? name : null;
  }

  /// Deletes rendered sounds not in [keep] (bounded disk use).
  static Future<void> pruneSounds(Set<String> keep) async {
    if (kIsWeb || !Platform.isIOS) return;
    final dir = Directory('${(await getLibraryDirectory()).path}/Sounds');
    if (!dir.existsSync()) return;
    for (final f in dir.listSync().whereType<File>()) {
      final n = f.uri.pathSegments.last;
      if (n.startsWith('aria_') && !keep.contains(n)) f.deleteSync();
    }
  }
}

// ----------------------------------------------------------- delivery

const _kSpokenAlarmIds = 'aria.spoken_alarm_ids';

/// iOS: voice as the notification sound. Android: exact alarms that wake a
/// background isolate which speaks (respecting the ringer unless the user
/// opted into the alarm stream).
class PlatformVoiceDelivery implements VoiceDelivery {
  PlatformVoiceDelivery(this._speaker, this._prefs);
  final DeviceSpeaker _speaker;
  final SharedPreferences _prefs;

  @override
  Future<String?> soundFor(String text, VoiceProfile voice) =>
      _speaker.renderNotificationSound(text, voice);

  @override
  Future<void> syncSpokenAlarms(
    List<PlannedAlert> alerts,
    VoiceProfile voice,
  ) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final previous = (_prefs.getStringList(_kSpokenAlarmIds) ?? [])
        .map(int.parse)
        .toSet();
    final wanted = {for (final a in alerts) a.id: a};
    for (final id in previous.difference(wanted.keys.toSet())) {
      await AndroidAlarmManager.cancel(id);
    }
    for (final a in alerts) {
      await AndroidAlarmManager.oneShotAt(
        a.fireAt.toLocal(),
        a.id,
        spokenAlarmCallback,
        exact: true,
        wakeup: true,
        allowWhileIdle: true,
        rescheduleOnReboot: true,
        params: {
          'text': a.spoken,
          'locale': voice.locale,
          'rate': voice.rate,
          'pitch': voice.pitch,
          'alarm': voice.alarmStream,
        },
      );
    }
    await _prefs.setStringList(
      _kSpokenAlarmIds,
      wanted.keys.map((e) => '$e').toList(),
    );
  }
}

/// Android background isolate entry point for a spoken reminder.
@pragma('vm:entry-point')
Future<void> spokenAlarmCallback(int id, Map<String, dynamic> params) async {
  WidgetsFlutterBinding.ensureInitialized();
  final text = params['text'] as String?;
  if (text == null || text.isEmpty) return;
  final alarm = params['alarm'] as bool? ?? false;
  // Auto-fallback: phone on silent/vibrate → the text notification alone.
  if (!alarm && await AriaDevice.ringerMode() != RingerMode.normal) return;
  await AriaDevice.speak(
    text,
    locale: params['locale'] as String? ?? 'en-IN',
    rate: (params['rate'] as num?)?.toDouble() ?? 1.0,
    pitch: (params['pitch'] as num?)?.toDouble() ?? 1.0,
    alarmStream: alarm,
  );
}

/// No-op delivery (tests, web).
class NoVoiceDelivery implements VoiceDelivery {
  const NoVoiceDelivery();
  @override
  Future<String?> soundFor(String text, VoiceProfile voice) async => null;
  @override
  Future<void> syncSpokenAlarms(
    List<PlannedAlert> alerts,
    VoiceProfile voice,
  ) async {}
}
