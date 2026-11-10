import 'dart:ui';

import 'package:aria/core/theme/palette.dart';
import 'package:aria/l10n/tr.dart';

/// A named colour theme with light and dark palettes.
class ThemePreset {
  const ThemePreset({
    required this.id,
    required this._label,
    required this.light,
    required this.dark,
    this.isFree = false,
  });

  final String id;
  final String _label;
  String get label => tr(_label);
  final AriaPalette light;
  final AriaPalette dark;

  /// Free plan gets 3 presets; the rest are premium (Phase 7 enforces).
  final bool isFree;
}

/// Ids must match `public.theme_presets.id` in Supabase.
abstract final class ThemePresets {
  static const lavender = ThemePreset(
    id: 'lavender',
    label: 'Lavender',
    isFree: true,
    light: AriaPalette(
      // Darkened from #7C4DFF so text buttons pass AA (≥4.5:1) on the background.
      primary: Color(0xFF7848FF),
      secondary: Color(0xFFFF6FAE),
      background: Color(0xFFF7F3FC),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF1F1633),
      // Spec #7A7090 is 4.2:1 on the background; darkened to pass AA.
      muted: Color(0xFF6E6487),
    ),
    dark: AriaPalette(
      primary: Color(0xFFB39DFF),
      secondary: Color(0xFFFF8DC0),
      background: Color(0xFF15111F),
      surface: Color(0xFF211B2E),
      text: Color(0xFFF3EEFB),
      muted: Color(0xFFABA1C2),
    ),
  );

  static const ocean = ThemePreset(
    id: 'ocean',
    label: 'Ocean Blue',
    isFree: true,
    light: AriaPalette(
      // Darkened from #1E6FD9 so text buttons pass AA (≥4.5:1) on the background.
      primary: Color(0xFF1E6DD6),
      secondary: Color(0xFF00B3C7),
      background: Color(0xFFF2F7FD),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF0F1C2E),
      muted: Color(0xFF56667B),
    ),
    dark: AriaPalette(
      primary: Color(0xFF7FB2FF),
      secondary: Color(0xFF4FD8E8),
      background: Color(0xFF0D1520),
      surface: Color(0xFF172231),
      text: Color(0xFFEAF2FC),
      muted: Color(0xFF9FB0C4),
    ),
  );

  static const mint = ThemePreset(
    id: 'mint',
    label: 'Mint Green',
    isFree: true,
    light: AriaPalette(
      primary: Color(0xFF0F7F60),
      secondary: Color(0xFF7BD389),
      background: Color(0xFFF1FAF6),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF10241D),
      muted: Color(0xFF4F6A63),
    ),
    dark: AriaPalette(
      primary: Color(0xFF5FD3AE),
      secondary: Color(0xFFA5E8B0),
      background: Color(0xFF0C1714),
      surface: Color(0xFF15241F),
      text: Color(0xFFE6F6F0),
      muted: Color(0xFF9DB8B0),
    ),
  );

  static const sunset = ThemePreset(
    id: 'sunset',
    label: 'Sunset Orange',
    light: AriaPalette(
      primary: Color(0xFFC2410C),
      secondary: Color(0xFFFFB347),
      background: Color(0xFFFFF6EF),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF2A160C),
      muted: Color(0xFF74594C),
    ),
    dark: AriaPalette(
      primary: Color(0xFFFF9A5C),
      secondary: Color(0xFFFFC978),
      background: Color(0xFF1A110C),
      surface: Color(0xFF271A13),
      text: Color(0xFFFBEDE4),
      muted: Color(0xFFC2A799),
    ),
  );

  static const rose = ThemePreset(
    id: 'rose',
    label: 'Rose Pink',
    light: AriaPalette(
      primary: Color(0xFFC2185B),
      secondary: Color(0xFFFF8FB1),
      background: Color(0xFFFFF3F7),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF2B0F1C),
      muted: Color(0xFF775564),
    ),
    dark: AriaPalette(
      primary: Color(0xFFFF8FB8),
      secondary: Color(0xFFFFB3CB),
      background: Color(0xFF1B0E14),
      surface: Color(0xFF2A1720),
      text: Color(0xFFFBE9F0),
      muted: Color(0xFFC4A2B1),
    ),
  );

  static const midnight = ThemePreset(
    id: 'midnight',
    label: 'Midnight',
    light: AriaPalette(
      // Darkened from #3D5AFE so text buttons pass AA (≥4.5:1) on the background.
      primary: Color(0xFF3A58FE),
      secondary: Color(0xFF00B8D4),
      background: Color(0xFFEEF0F8),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF0E1330),
      muted: Color(0xFF555B7B),
    ),
    dark: AriaPalette(
      primary: Color(0xFF8C9EFF),
      secondary: Color(0xFF5CE1F5),
      background: Color(0xFF0A0D1C),
      surface: Color(0xFF141A30),
      text: Color(0xFFE8EBFA),
      muted: Color(0xFFA3A9C8),
    ),
  );

  static const sand = ThemePreset(
    id: 'sand',
    label: 'Sand',
    light: AriaPalette(
      primary: Color(0xFF8A5A2B),
      secondary: Color(0xFFD9A55B),
      background: Color(0xFFFBF7F0),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF2B2116),
      muted: Color(0xFF6F604A),
    ),
    dark: AriaPalette(
      primary: Color(0xFFE0B784),
      secondary: Color(0xFFEBC98F),
      background: Color(0xFF17130D),
      surface: Color(0xFF241E16),
      text: Color(0xFFF5EDE1),
      muted: Color(0xFFBFB09A),
    ),
  );

  static const monochrome = ThemePreset(
    id: 'monochrome',
    label: 'Monochrome',
    light: AriaPalette(
      primary: Color(0xFF2B2B2B),
      secondary: Color(0xFF6B6B6B),
      background: Color(0xFFF5F5F5),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF111111),
      muted: Color(0xFF5B5B5B),
    ),
    dark: AriaPalette(
      primary: Color(0xFFE6E6E6),
      secondary: Color(0xFFB0B0B0),
      background: Color(0xFF0F0F0F),
      surface: Color(0xFF1C1C1C),
      text: Color(0xFFF2F2F2),
      muted: Color(0xFFA8A8A8),
    ),
  );

  static const all = <ThemePreset>[
    lavender,
    ocean,
    mint,
    sunset,
    rose,
    midnight,
    sand,
    monochrome,
  ];

  static ThemePreset byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => lavender);
}
