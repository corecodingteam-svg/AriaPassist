import 'package:aria/core/theme/palette.dart';
import 'package:flutter/material.dart';

/// Design tokens available anywhere via `context.tokens`.
///
/// Everything visual (colours, radii, spacing, motion) reads from here, so a
/// theme change rebuilds the whole tree instantly with no restart.
@immutable
class AriaTokens extends ThemeExtension<AriaTokens> {
  const AriaTokens({required this.palette, required this.motion});

  final AriaPalette palette;

  /// Standard animation duration; `Duration.zero` when reduce-motion is on.
  final Duration motion;

  // Radii: the Neon look's squared-off panels, buttons and inputs.
  static const double radiusSm = 3;
  static const double radiusMd = 3;
  static const double radiusLg = 4;
  static const double radiusPill = 999;

  // Spacing scale.
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 24;
  static const double s6 = 32;

  /// Minimum interactive size (48 dp).
  static const double minTap = 48;
  static const double micSize = 64;

  LinearGradient get primaryGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [palette.primary, palette.gradientEnd],
  );

  @override
  AriaTokens copyWith({AriaPalette? palette, Duration? motion}) => AriaTokens(
    palette: palette ?? this.palette,
    motion: motion ?? this.motion,
  );

  @override
  AriaTokens lerp(AriaTokens? other, double t) {
    if (other == null) return this;
    final a = palette;
    final b = other.palette;
    return AriaTokens(
      motion: t < 0.5 ? motion : other.motion,
      palette: AriaPalette(
        primary: Color.lerp(a.primary, b.primary, t)!,
        secondary: Color.lerp(a.secondary, b.secondary, t)!,
        background: Color.lerp(a.background, b.background, t)!,
        surface: Color.lerp(a.surface, b.surface, t)!,
        text: Color.lerp(a.text, b.text, t)!,
        muted: Color.lerp(a.muted, b.muted, t)!,
        nav: Color.lerp(a.navColor, b.navColor, t),
        success: Color.lerp(a.success, b.success, t)!,
        warning: Color.lerp(a.warning, b.warning, t)!,
        danger: Color.lerp(a.danger, b.danger, t)!,
      ),
    );
  }
}

extension AriaTokensX on BuildContext {
  AriaTokens get tokens => Theme.of(this).extension<AriaTokens>()!;
  AriaPalette get palette => tokens.palette;
}
