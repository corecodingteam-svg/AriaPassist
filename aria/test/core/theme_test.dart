import 'dart:io';

import 'package:aria/core/theme/app_theme.dart';
import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/theme/presets.dart';
import 'package:aria/core/theme/theme_settings.dart';
import 'package:aria/core/utils/contrast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WCAG AA contrast for every preset', () {
    for (final preset in ThemePresets.all) {
      for (final entry in {
        'light': preset.light,
        'dark': preset.dark,
        'light/high-contrast': preset.light.highContrast(),
        'dark/high-contrast': preset.dark.highContrast(),
      }.entries) {
        test('${preset.id} ${entry.key}', () {
          final p = entry.value;
          void aa(
            Color fg,
            Color bg,
            String what, [
            double min = kAaNormalText,
          ]) {
            final r = contrastRatio(fg, bg);
            expect(
              r,
              greaterThanOrEqualTo(min),
              reason: '$what = ${r.toStringAsFixed(2)}:1',
            );
          }

          aa(p.text, p.background, 'text on background');
          aa(p.text, p.surface, 'text on surface');
          aa(p.muted, p.background, 'muted on background');
          aa(p.muted, p.surface, 'muted on surface');
          aa(p.onPrimary, p.primary, 'button label on primary');
          aa(
            p.onPrimary,
            p.gradientEnd,
            'mic icon on gradient end',
            kAaLargeOrGraphic,
          );
          aa(p.primary, p.surface, 'primary vs surface', kAaLargeOrGraphic);
          // Text buttons use primary as their label colour (a11y audit).
          aa(p.primary, p.background, 'text button on background');
          aa(p.primary, p.surface, 'text button on surface');
          aa(p.onSuccess, p.success, 'on success');
          aa(p.onWarning, p.warning, 'on warning');
          aa(p.onDanger, p.danger, 'on danger');
          final scheme = AppTheme.build(
            ThemeSettings(
              presetId: preset.id,
              highContrast: entry.key.contains('high'),
            ),
            p.isDark ? Brightness.dark : Brightness.light,
          ).colorScheme;
          aa(
            scheme.onSecondaryContainer,
            scheme.secondaryContainer,
            'selected segment label',
          );
        });
      }
    }
  });

  test('custom accent is applied only when it passes AA', () {
    const good = ThemeSettings(customAccent: 0xFF00695C); // dark teal
    const bad = ThemeSettings(customAccent: 0xFFFFF59D); // pale yellow
    expect(
      AppTheme.resolvePalette(good, Brightness.light).primary,
      const Color(0xFF00695C),
    );
    expect(
      AppTheme.resolvePalette(bad, Brightness.light).primary,
      ThemePresets.lavender.light.primary,
      reason: 'inaccessible accent falls back to the preset',
    );
  });

  test('ThemeSettings JSON round-trips', () {
    const s = ThemeSettings(
      mode: ThemeMode.dark,
      presetId: 'ocean',
      fontSize: FontSizeOption.xl,
      highContrast: true,
      reduceMotion: true,
      customAccent: 0xFF123456,
    );
    expect(ThemeSettings.fromJson(s.toJson()), s);
    expect(ThemeSettings.fromJson(const {}), const ThemeSettings());
  });

  test('unknown preset id falls back to Lavender', () {
    expect(ThemePresets.byId('nope').id, 'lavender');
  });

  test('reduce motion zeroes the motion token', () {
    AriaTokens tokens(ThemeSettings s) =>
        AppTheme.build(s, Brightness.light).extension<AriaTokens>()!;
    expect(
      tokens(const ThemeSettings(reduceMotion: true)).motion,
      Duration.zero,
    );
    expect(tokens(const ThemeSettings()).motion, isNot(Duration.zero));
  });

  test('preset ids match the Supabase theme_presets seed', () {
    final sql = File('supabase/migrations/20261108000003_catalogue_data.sql')
        .readAsStringSync();
    for (final p in ThemePresets.all) {
      expect(sql, contains("('${p.id}', '${p.label}'"), reason: p.id);
    }
  });
}
