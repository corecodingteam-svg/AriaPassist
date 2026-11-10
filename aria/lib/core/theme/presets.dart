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

  /// Free plan gets the free presets; the rest are premium (Phase 7 enforces).
  final bool isFree;
}

/// The Neon look: Neon (dark slate with a blue accent) and its skins. [AriaPalette.nav] is the skin's header and
/// navigation colour; [AriaPalette.primary] is the same hue made dark (or, in dark mode, light) enough for buttons
/// and links to keep AA contrast, which Neon's bright greens, yellows and blues would not.
///
/// Ids must match `public.theme_presets.id` in Supabase; the existing ids keep their names so plans and saved
/// choices still apply.
/// Neon's danger red: white text on it passes AA, which the default red does not with these lighter text colours.
/// Dark palettes keep the default red, which reads better as error text on dark panels.
const _neonDanger = Color(0xFFCC2424);

abstract final class ThemePresets {
  static const neon = ThemePreset(
    id: 'neon',
    label: 'Neon',
    isFree: true,
    light: AriaPalette(
      primary: Color(0xFF303641),
      secondary: Color(0xFF21A9E1),
      background: Color(0xFFF3F3F3),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF2B303A),
      muted: Color(0xFF5F6570),
      nav: Color(0xFF303641),
      danger: _neonDanger,
    ),
    dark: AriaPalette(
      primary: Color(0xFF5CC0EA),
      secondary: Color(0xFF8FD3F0),
      background: Color(0xFF1A1E24),
      surface: Color(0xFF262B33),
      text: Color(0xFFECEEF1),
      muted: Color(0xFFA8ADB5),
      nav: Color(0xFF303641),
    ),
  );

  /// Neon's Purple skin.
  static const lavender = ThemePreset(
    id: 'lavender',
    label: 'Lavender',
    isFree: true,
    light: AriaPalette(
      primary: Color(0xFF643590),
      secondary: Color(0xFFBA79CB),
      background: Color(0xFFF3F3F3),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF2B2433),
      muted: Color(0xFF635C6C),
      nav: Color(0xFF522B76),
      danger: _neonDanger,
    ),
    dark: AriaPalette(
      primary: Color(0xFFCFA8EE),
      secondary: Color(0xFFE0BDF0),
      background: Color(0xFF1C1822),
      surface: Color(0xFF29232F),
      text: Color(0xFFF1EDF5),
      muted: Color(0xFFB1A8BB),
      nav: Color(0xFF522B76),
    ),
  );

  /// Neon's Blue skin.
  static const ocean = ThemePreset(
    id: 'ocean',
    label: 'Ocean Blue',
    isFree: true,
    light: AriaPalette(
      primary: Color(0xFF063D7D),
      secondary: Color(0xFF21A9E1),
      background: Color(0xFFF3F3F3),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF13243A),
      muted: Color(0xFF56657A),
      nav: Color(0xFF003471),
      danger: _neonDanger,
    ),
    dark: AriaPalette(
      primary: Color(0xFF86B9F2),
      secondary: Color(0xFF8FD3F0),
      background: Color(0xFF111A26),
      surface: Color(0xFF1B2635),
      text: Color(0xFFEAF1FA),
      muted: Color(0xFFA2B1C4),
      nav: Color(0xFF003471),
    ),
  );

  /// Neon's Green skin (the bar a little deeper than Neon's #00A651 so its white text passes AA).
  static const mint = ThemePreset(
    id: 'mint',
    label: 'Mint Green',
    isFree: true,
    light: AriaPalette(
      primary: Color(0xFF00733A),
      secondary: Color(0xFF00A651),
      background: Color(0xFFF3F3F3),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF122A1D),
      muted: Color(0xFF526459),
      nav: Color(0xFF00843F),
      danger: _neonDanger,
    ),
    dark: AriaPalette(
      primary: Color(0xFF5FD39A),
      secondary: Color(0xFF8FE3B8),
      background: Color(0xFF0F1A14),
      surface: Color(0xFF18261E),
      text: Color(0xFFE7F5ED),
      muted: Color(0xFF9FB7A9),
      nav: Color(0xFF00843F),
    ),
  );

  /// Neon's orange stat tile as a skin.
  static const sunset = ThemePreset(
    id: 'sunset',
    label: 'Sunset Orange',
    light: AriaPalette(
      primary: Color(0xFFA8530A),
      secondary: Color(0xFFFFA812),
      background: Color(0xFFF3F3F3),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF2E1C0C),
      muted: Color(0xFF6E5B4B),
      nav: Color(0xFFF89D00),
      danger: _neonDanger,
    ),
    dark: AriaPalette(
      primary: Color(0xFFFFB35C),
      secondary: Color(0xFFFFC97A),
      background: Color(0xFF1C140C),
      surface: Color(0xFF2A1F14),
      text: Color(0xFFFBEFE2),
      muted: Color(0xFFC4AB95),
      nav: Color(0xFFF89D00),
    ),
  );

  /// Neon's Red skin.
  static const rose = ThemePreset(
    id: 'rose',
    label: 'Rose Pink',
    light: AriaPalette(
      primary: Color(0xFFA22424),
      secondary: Color(0xFFF56954),
      background: Color(0xFFF3F3F3),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF2E1414),
      muted: Color(0xFF6C5656),
      nav: Color(0xFF981B1B),
      danger: _neonDanger,
    ),
    dark: AriaPalette(
      primary: Color(0xFFFF9488),
      secondary: Color(0xFFFFB3A8),
      background: Color(0xFF1D1212),
      surface: Color(0xFF2B1B1B),
      text: Color(0xFFFBECEC),
      muted: Color(0xFFC4A6A6),
      nav: Color(0xFF981B1B),
    ),
  );

  /// Neon's Black skin.
  static const midnight = ThemePreset(
    id: 'midnight',
    label: 'Midnight',
    light: AriaPalette(
      primary: Color(0xFF222222),
      secondary: Color(0xFF21A9E1),
      background: Color(0xFFF3F3F3),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF1F1F1F),
      muted: Color(0xFF5C5C5C),
      nav: Color(0xFF222222),
      danger: _neonDanger,
    ),
    dark: AriaPalette(
      primary: Color(0xFF7CC8EE),
      secondary: Color(0xFFA6DBF5),
      background: Color(0xFF141414),
      surface: Color(0xFF1F1F1F),
      text: Color(0xFFF0F0F0),
      muted: Color(0xFFA9A9A9),
      nav: Color(0xFF222222),
    ),
  );

  /// Neon's Cafe skin.
  static const sand = ThemePreset(
    id: 'sand',
    label: 'Sand',
    light: AriaPalette(
      primary: Color(0xFF5B4632),
      secondary: Color(0xFFA5876B),
      background: Color(0xFFFBF1DF),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF2B2116),
      muted: Color(0xFF6A5A48),
      nav: Color(0xFF31271E),
      danger: _neonDanger,
    ),
    dark: AriaPalette(
      primary: Color(0xFFE3C6A2),
      secondary: Color(0xFFEAD3B5),
      background: Color(0xFF19140F),
      surface: Color(0xFF262019),
      text: Color(0xFFF6EEE3),
      muted: Color(0xFFBFB09C),
      nav: Color(0xFF31271E),
    ),
  );

  /// Neon's White skin.
  static const monochrome = ThemePreset(
    id: 'monochrome',
    label: 'Monochrome',
    light: AriaPalette(
      primary: Color(0xFF51555D),
      secondary: Color(0xFF8A8F97),
      background: Color(0xFFF3F3F3),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF26282C),
      muted: Color(0xFF5B5F66),
      nav: Color(0xFFFFFFFF),
      danger: _neonDanger,
    ),
    dark: AriaPalette(
      primary: Color(0xFFE6E6E6),
      secondary: Color(0xFFBDBDBD),
      background: Color(0xFF121212),
      surface: Color(0xFF1E1E1E),
      text: Color(0xFFF2F2F2),
      muted: Color(0xFFA8A8A8),
      nav: Color(0xFF303030),
    ),
  );

  static const all = <ThemePreset>[
    neon,
    lavender,
    ocean,
    mint,
    sunset,
    rose,
    midnight,
    sand,
    monochrome,
  ];

  /// The default look, also for an id this app does not know.
  static ThemePreset byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => neon);
}
