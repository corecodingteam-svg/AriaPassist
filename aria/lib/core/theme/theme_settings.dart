import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';

enum FontSizeOption {
  s(0.9, 'S'),
  m(1, 'M'),
  l(1.15, 'L'),
  xl(1.3, 'XL');

  FontSizeOption(this.factor, this._label);
  final double factor;
  final String _label;
  String get label => tr(_label);
}

/// User-chosen appearance. Serialises to `user_settings.theme_json`.
@immutable
class ThemeSettings {
  const ThemeSettings({
    this.mode = ThemeMode.system,
    this.presetId = 'neon',
    this.fontSize = FontSizeOption.m,
    this.highContrast = false,
    this.reduceMotion = false,
    this.customAccent,
  });

  factory ThemeSettings.fromJson(Map<String, dynamic> json) => ThemeSettings(
    mode: ThemeMode.values.asNameMap()[json['mode']] ?? ThemeMode.system,
    presetId: json['preset'] as String? ?? 'neon',
    fontSize:
        FontSizeOption.values.asNameMap()[json['font_size']] ??
        FontSizeOption.m,
    highContrast: json['high_contrast'] as bool? ?? false,
    reduceMotion: json['reduce_motion'] as bool? ?? false,
    customAccent: json['custom_accent'] as int?,
  );

  final ThemeMode mode;
  final String presetId;
  final FontSizeOption fontSize;
  final bool highContrast;
  final bool reduceMotion;

  /// ARGB int; premium feature, applied only if it passes AA (see AppTheme).
  final int? customAccent;

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'preset': presetId,
    'font_size': fontSize.name,
    'high_contrast': highContrast,
    'reduce_motion': reduceMotion,
    'custom_accent': customAccent,
  };

  ThemeSettings copyWith({
    ThemeMode? mode,
    String? presetId,
    FontSizeOption? fontSize,
    bool? highContrast,
    bool? reduceMotion,
    int? Function()? customAccent,
  }) => ThemeSettings(
    mode: mode ?? this.mode,
    presetId: presetId ?? this.presetId,
    fontSize: fontSize ?? this.fontSize,
    highContrast: highContrast ?? this.highContrast,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    customAccent: customAccent != null ? customAccent() : this.customAccent,
  );

  @override
  bool operator ==(Object other) =>
      other is ThemeSettings &&
      other.mode == mode &&
      other.presetId == presetId &&
      other.fontSize == fontSize &&
      other.highContrast == highContrast &&
      other.reduceMotion == reduceMotion &&
      other.customAccent == customAccent;

  @override
  int get hashCode => Object.hash(
    mode,
    presetId,
    fontSize,
    highContrast,
    reduceMotion,
    customAccent,
  );
}
