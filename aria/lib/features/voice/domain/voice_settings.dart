import 'dart:convert';

import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/foundation.dart';

enum Personality {
  friendly('😊', 'Friendly'),
  professional('💼', 'Professional'),
  coach('🏋️', 'Strict coach'),
  caring('🤗', 'Caring'),
  short('⚡', 'Short & to the point');

  Personality(this.emoji, this._label);
  final String emoji;
  final String _label;
  String get label => tr(_label);
}

enum VoiceLanguage {
  en('English'),
  hi('हिन्दी'),
  hinglish('Hinglish');

  VoiceLanguage(this._label);
  final String _label;
  String get label => tr(_label);
}

/// Minutes since local midnight.
typedef DayMinute = int;

/// Accepts minutes (420) or "HH:mm" ("07:00", the database default format).
DayMinute? dayMinute(Object? v) {
  if (v is int) return v;
  if (v is String) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(v);
    if (m != null) return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }
  return null;
}

@immutable
class QuietHours {
  const QuietHours({
    this.enabled = false,
    this.start = 23 * 60,
    this.end = 7 * 60,
    this.allowUrgent = true,
  });

  factory QuietHours.fromJson(Map<String, dynamic>? j) => j == null
      ? const QuietHours()
      : QuietHours(
          enabled: j['enabled'] as bool? ?? false,
          start: dayMinute(j['start']) ?? 23 * 60,
          end: dayMinute(j['end']) ?? 7 * 60,
          allowUrgent: j['allow_urgent'] as bool? ?? true,
        );

  final bool enabled;
  final DayMinute start;
  final DayMinute end;
  final bool allowUrgent;

  /// Whether a wall-clock minute-of-day falls inside quiet hours
  /// (handles ranges that cross midnight).
  bool contains(DayMinute m) {
    if (!enabled || start == end) return false;
    return start < end ? m >= start && m < end : m >= start || m < end;
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'start': start,
    'end': end,
    'allow_urgent': allowUrgent,
  };

  QuietHours copyWith({
    bool? enabled,
    int? start,
    int? end,
    bool? allowUrgent,
  }) => QuietHours(
    enabled: enabled ?? this.enabled,
    start: start ?? this.start,
    end: end ?? this.end,
    allowUrgent: allowUrgent ?? this.allowUrgent,
  );

  @override
  bool operator ==(Object other) =>
      other is QuietHours &&
      other.enabled == enabled &&
      other.start == start &&
      other.end == end &&
      other.allowUrgent == allowUrgent;
  @override
  int get hashCode => Object.hash(enabled, start, end, allowUrgent);
}

@immutable
class Briefings {
  const Briefings({
    this.morningEnabled = true,
    this.morningAt = 7 * 60 + 30,
    this.nightEnabled = true,
    this.nightAt = 22 * 60,
  });

  factory Briefings.fromJson(Map<String, dynamic>? j) => j == null
      ? const Briefings()
      : Briefings(
          morningEnabled: j['morning_enabled'] as bool? ?? true,
          morningAt: dayMinute(j['morning_at']) ?? 7 * 60 + 30,
          nightEnabled: j['night_enabled'] as bool? ?? true,
          nightAt: dayMinute(j['night_at']) ?? 22 * 60,
        );

  final bool morningEnabled;
  final DayMinute morningAt;
  final bool nightEnabled;
  final DayMinute nightAt;

  Map<String, dynamic> toJson() => {
    'morning_enabled': morningEnabled,
    'morning_at': morningAt,
    'night_enabled': nightEnabled,
    'night_at': nightAt,
  };

  Briefings copyWith({
    bool? morningEnabled,
    int? morningAt,
    bool? nightEnabled,
    int? nightAt,
  }) => Briefings(
    morningEnabled: morningEnabled ?? this.morningEnabled,
    morningAt: morningAt ?? this.morningAt,
    nightEnabled: nightEnabled ?? this.nightEnabled,
    nightAt: nightAt ?? this.nightAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Briefings &&
      other.morningEnabled == morningEnabled &&
      other.morningAt == morningAt &&
      other.nightEnabled == nightEnabled &&
      other.nightAt == nightAt;
  @override
  int get hashCode =>
      Object.hash(morningEnabled, morningAt, nightEnabled, nightAt);
}

/// Voice & reminder-style preferences (spec 6.1, 6.2, 6.5, 6.6).
/// Serialises into `user_settings` columns in Phase 4's settings sync.
@immutable
class VoiceSettings {
  const VoiceSettings({
    this.voiceId = 'aria',
    this.paName = 'Aria',
    this.speed = 1.0,
    this.pitch = 1.0,
    this.personality = Personality.friendly,
    this.language = VoiceLanguage.en,
    this.spokenConfirmations = true,
    this.defaultMode = NotifyMode.both,
    this.categoryModes = const {},
    this.quietHours = const QuietHours(),
    this.briefings = const Briefings(),
    this.useAlarmStream = false,
  });

  factory VoiceSettings.fromJson(Map<String, dynamic> j) => VoiceSettings(
    voiceId: j['voice_id'] as String? ?? 'aria',
    paName: j['pa_name'] as String? ?? 'Aria',
    speed: (j['speed'] as num?)?.toDouble() ?? 1.0,
    pitch: (j['pitch'] as num?)?.toDouble() ?? 1.0,
    personality:
        Personality.values.asNameMap()[j['personality']] ??
        Personality.friendly,
    language:
        VoiceLanguage.values.asNameMap()[j['language']] ?? VoiceLanguage.en,
    spokenConfirmations: j['spoken_confirmations'] as bool? ?? true,
    defaultMode:
        NotifyMode.parse(j['default_mode'] as String?) ?? NotifyMode.both,
    categoryModes: {
      for (final e
          in (j['category_modes'] as Map<String, dynamic>? ?? {}).entries)
        ?ReminderCategory.values.asNameMap()[e.key]: ?NotifyMode.parse(
          e.value as String?,
        ),
    },
    quietHours: QuietHours.fromJson(j['quiet_hours'] as Map<String, dynamic>?),
    briefings: Briefings.fromJson(j['briefings'] as Map<String, dynamic>?),
    useAlarmStream: j['use_alarm_stream'] as bool? ?? false,
  );

  final String voiceId;
  final String paName;

  /// 0.75–1.5
  final double speed;

  /// 0.5–2.0
  final double pitch;
  final Personality personality;
  final VoiceLanguage language;
  final bool spokenConfirmations;
  final NotifyMode defaultMode;
  final Map<ReminderCategory, NotifyMode> categoryModes;
  final QuietHours quietHours;
  final Briefings briefings;

  /// Android: speak on the alarm stream so voice works on silent.
  final bool useAlarmStream;

  /// Effective delivery for a reminder: its own override, then the
  /// category override, then the default.
  NotifyMode modeFor(Reminder r) =>
      r.notifyMode ?? categoryModes[r.category] ?? defaultMode;

  Map<String, dynamic> toJson() => {
    'voice_id': voiceId,
    'pa_name': paName,
    'speed': speed,
    'pitch': pitch,
    'personality': personality.name,
    'language': language.name,
    'spoken_confirmations': spokenConfirmations,
    'default_mode': defaultMode.name,
    'category_modes': {
      for (final e in categoryModes.entries) e.key.name: e.value.name,
    },
    'quiet_hours': quietHours.toJson(),
    'briefings': briefings.toJson(),
    'use_alarm_stream': useAlarmStream,
  };

  VoiceSettings copyWith({
    String? voiceId,
    String? paName,
    double? speed,
    double? pitch,
    Personality? personality,
    VoiceLanguage? language,
    bool? spokenConfirmations,
    NotifyMode? defaultMode,
    Map<ReminderCategory, NotifyMode>? categoryModes,
    QuietHours? quietHours,
    Briefings? briefings,
    bool? useAlarmStream,
  }) => VoiceSettings(
    voiceId: voiceId ?? this.voiceId,
    paName: paName ?? this.paName,
    speed: speed ?? this.speed,
    pitch: pitch ?? this.pitch,
    personality: personality ?? this.personality,
    language: language ?? this.language,
    spokenConfirmations: spokenConfirmations ?? this.spokenConfirmations,
    defaultMode: defaultMode ?? this.defaultMode,
    categoryModes: categoryModes ?? this.categoryModes,
    quietHours: quietHours ?? this.quietHours,
    briefings: briefings ?? this.briefings,
    useAlarmStream: useAlarmStream ?? this.useAlarmStream,
  );

  // Deep equality via the canonical JSON (nested maps included).
  @override
  bool operator ==(Object other) =>
      other is VoiceSettings &&
      jsonEncode(other.toJson()) == jsonEncode(toJson());
  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}
