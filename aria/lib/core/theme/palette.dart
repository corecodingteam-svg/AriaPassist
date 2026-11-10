import 'dart:ui';

import 'package:aria/core/utils/contrast.dart';

/// The raw colour set for one preset in one brightness.
///
/// Derived colours (on-colours, gradient end) are computed so that every
/// preset — including a user's custom accent — keeps WCAG AA contrast.
class AriaPalette {
  const AriaPalette({
    required this.primary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.text,
    required this.muted,
    this.nav,
    this.success = const Color(0xFF22B07D),
    this.warning = const Color(0xFFF5A524),
    this.danger = const Color(0xFFEF4F6B),
  });

  final Color primary;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color text;
  final Color muted;

  /// The Neon navigation bar (Neon's sidebar colour); [primary] when not set.
  final Color? nav;
  final Color success;
  final Color warning;
  final Color danger;

  bool get isDark => background.computeLuminance() < 0.2;

  Color get navColor => nav ?? primary;

  /// Titles and the selected item on [navColor].
  Color get onNav => readableOn(navColor, dark: const Color(0xFF1A1E24));

  /// Unselected navigation items: [onNav] softened, the way Neon's sidebar greys its links, but kept at AA.
  Color get navMuted {
    for (final a in const [0.72, 0.8, 0.88]) {
      final c = Color.alphaBlend(onNav.withValues(alpha: a), navColor);
      if (contrastRatio(c, navColor) >= kAaNormalText) return c;
    }
    return onNav;
  }

  /// Text/icon colour on top of [primary] (buttons, mic).
  Color get onPrimary => _on(primary);
  Color get onSuccess => _on(success);
  Color get onWarning => _on(warning);
  Color get onDanger => _on(danger);

  /// End stop of the primary gradient. Kept close to [primary] so the
  /// on-primary icon still clears 3:1 across the whole gradient.
  Color get gradientEnd => Color.lerp(primary, secondary, 0.4)!;

  Color _on(Color c) => readableOn(c, dark: isDark ? background : text);

  AriaPalette copyWith({Color? primary, Color? text, Color? muted}) =>
      AriaPalette(
        primary: primary ?? this.primary,
        secondary: secondary,
        background: background,
        surface: surface,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        nav: nav,
        success: success,
        warning: warning,
        danger: danger,
      );

  /// High-contrast variant: pure text colours, muted collapses to text.
  AriaPalette highContrast() {
    final t = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    return copyWith(text: t, muted: t);
  }
}
