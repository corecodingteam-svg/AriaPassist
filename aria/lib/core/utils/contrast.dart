import 'dart:math' as math;
import 'dart:ui';

/// WCAG 2.x relative-luminance contrast ratio between two colours (1–21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Picks whichever of [light] / [dark] reads better on [background].
Color readableOn(
  Color background, {
  Color light = const Color(0xFFFFFFFF),
  Color dark = const Color(0xFF000000),
}) => contrastRatio(background, light) >= contrastRatio(background, dark)
    ? light
    : dark;

/// WCAG AA thresholds.
const double kAaNormalText = 4.5;
const double kAaLargeOrGraphic = 3;
