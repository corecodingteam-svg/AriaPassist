import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/theme/palette.dart';
import 'package:aria/core/theme/presets.dart';
import 'package:aria/core/theme/theme_settings.dart';
import 'package:aria/core/utils/contrast.dart';
import 'package:flutter/material.dart';

const kFontFamily = 'PlusJakartaSans';
const kFontFallback = ['NotoSansDevanagari'];

abstract final class AppTheme {
  /// Resolves the palette for [settings] in [brightness], applying a custom
  /// accent only when it keeps AA contrast, and high-contrast mode.
  static AriaPalette resolvePalette(
    ThemeSettings settings,
    Brightness brightness,
  ) {
    final preset = ThemePresets.byId(settings.presetId);
    var palette = brightness == Brightness.dark ? preset.dark : preset.light;

    final accent = settings.customAccent;
    if (accent != null) {
      final candidate = palette.copyWith(primary: Color(accent));
      if (isAccentAccessible(candidate)) palette = candidate;
    }
    if (settings.highContrast) palette = palette.highContrast();
    return palette;
  }

  /// A custom accent must keep button text ≥ 4.5:1 and stand out from
  /// the surface ≥ 3:1.
  static bool isAccentAccessible(AriaPalette p) =>
      contrastRatio(p.onPrimary, p.primary) >= kAaNormalText &&
      contrastRatio(p.primary, p.surface) >= kAaLargeOrGraphic;

  static ThemeData build(
    ThemeSettings settings,
    Brightness brightness, {
    bool platformDisablesAnimations = false,
  }) {
    final p = resolvePalette(settings, brightness);
    final reduceMotion = settings.reduceMotion || platformDisablesAnimations;
    final tokens = AriaTokens(
      palette: p,
      motion: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
    );

    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.primary,
      onPrimary: p.onPrimary,
      secondary: p.secondary,
      onSecondary: readableOn(p.secondary, dark: p.text),
      // Selected segments, chips, nav indicators: a soft primary tint.
      primaryContainer: Color.alphaBlend(
        p.primary.withValues(alpha: 0.18),
        p.surface,
      ),
      onPrimaryContainer: p.text,
      secondaryContainer: Color.alphaBlend(
        p.primary.withValues(alpha: 0.18),
        p.surface,
      ),
      onSecondaryContainer: p.text,
      error: p.danger,
      onError: p.onDanger,
      surface: p.surface,
      onSurface: p.text,
      onSurfaceVariant: p.muted,
      surfaceContainerLowest: p.background,
      surfaceContainerLow: p.background,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surface,
      outline: p.muted,
      outlineVariant: p.muted.withValues(alpha: 0.3),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: kFontFamily,
      fontFamilyFallback: kFontFallback,
      scaffoldBackgroundColor: p.background,
      extensions: [tokens],
      materialTapTargetSize: MaterialTapTargetSize.padded,
      pageTransitionsTheme: reduceMotion
          ? const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: _NoTransitionsBuilder(),
                TargetPlatform.iOS: _NoTransitionsBuilder(),
              },
            )
          : null,
    );

    final text = base.textTheme.apply(
      bodyColor: p.text,
      displayColor: p.text,
      fontFamily: kFontFamily,
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AriaTokens.radiusMd),
    );
    const minButton = Size(AriaTokens.minTap, AriaTokens.minTap);

    return base.copyWith(
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AriaTokens.radiusLg),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: minButton,
          shape: shape,
          textStyle: const TextStyle(
            fontFamily: kFontFamily,
            fontFamilyFallback: kFontFallback,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: minButton, shape: shape),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: minButton),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AriaTokens.radiusMd),
          borderSide: BorderSide(color: p.muted.withValues(alpha: 0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AriaTokens.radiusMd),
          borderSide: BorderSide(color: p.muted.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AriaTokens.radiusMd),
          borderSide: BorderSide(color: p.primary, width: 2),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide(color: p.muted.withValues(alpha: 0.3)),
        backgroundColor: p.surface,
        selectedColor: p.primary.withValues(alpha: 0.15),
        labelStyle: TextStyle(color: p.text, fontFamily: kFontFamily),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: shape,
      ),
      dividerTheme: DividerThemeData(color: p.muted.withValues(alpha: 0.2)),
    );
  }
}

class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
