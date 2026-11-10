import 'package:aria/core/theme/app_theme.dart';
import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/theme/presets.dart';
import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/core/theme/theme_settings.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/preferences/domain/app_prefs.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Settings › Appearance & theme (6.3). Changes apply app-wide instantly.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(themeControllerProvider);
    final c = ref.read(themeControllerProvider.notifier);
    final brightness = Theme.of(context).brightness;
    final plan = ref.watch(entitlementProvider).plan;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Appearance & theme'))),
      body: ListView(
        padding: const EdgeInsets.all(AriaTokens.s4),
        children: [
          const _PreviewCard(),
          const SizedBox(height: AriaTokens.s5),
          _Section(tr('Mode'), tr('Follow your phone, or pick one')),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(value: ThemeMode.light, label: Text(tr('Light'))),
              ButtonSegment(value: ThemeMode.dark, label: Text(tr('Dark'))),
              ButtonSegment(value: ThemeMode.system, label: Text(tr('System'))),
            ],
            selected: {s.mode},
            onSelectionChanged: (v) => c.setMode(v.first),
          ),
          const SizedBox(height: AriaTokens.s5),
          _Section(
            tr('Colour theme'),
            tr('Changes colours across the whole app'),
          ),
          Wrap(
            spacing: AriaTokens.s3,
            runSpacing: AriaTokens.s3,
            children: [
              for (final preset in ThemePresets.all)
                _Swatch(
                  preset: preset,
                  brightness: brightness,
                  selected: s.presetId == preset.id,
                  locked: !plan.themeAllowed(preset.id),
                  onTap: () {
                    if (plan.themeAllowed(preset.id) ||
                        requireFeature(context, ref, Feature.allThemes)) {
                      c.setPreset(preset.id);
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: AriaTokens.s5),
          _Section(
            tr('App language'),
            tr(
              'Menus and buttons. Aria’s voice language is in Voice settings.',
            ),
          ),
          SegmentedButton<AppLanguage>(
            key: const Key('app-language'),
            showSelectedIcon: false,
            segments: [
              for (final l in AppLanguage.values)
                ButtonSegment(
                  value: l,
                  label: Text(l == AppLanguage.system ? tr(l.label) : l.label),
                ),
            ],
            selected: {
              ref.watch(appPrefsProvider.select((p) => p.appLanguage)),
            },
            onSelectionChanged: (v) => ref
                .read(appPrefsProvider.notifier)
                .update((p) => p.copyWith(appLanguage: v.first)),
          ),
          const SizedBox(height: AriaTokens.s5),
          _Section(
            tr('Text size'),
            tr('Works on top of your phone’s text size'),
          ),
          SegmentedButton<FontSizeOption>(
            segments: [
              for (final f in FontSizeOption.values)
                ButtonSegment(value: f, label: Text(f.label)),
            ],
            selected: {s.fontSize},
            onSelectionChanged: (v) => c.setFontSize(v.first),
          ),
          const SizedBox(height: AriaTokens.s4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('High contrast')),
            subtitle: Text(tr('Stronger text colours for easier reading')),
            value: s.highContrast,
            onChanged: (v) => c.setHighContrast(value: v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Reduce motion')),
            subtitle: Text(tr('Turns off animations and transitions')),
            value: s.reduceMotion,
            onChanged: (v) => c.setReduceMotion(value: v),
          ),
          const SizedBox(height: AriaTokens.s5),
          _Section(
            plan.has(Feature.customAccent)
                ? tr('Accent colour')
                : tr('Accent colour 🔒'),
            tr('Only colours that stay easy to read are applied'),
          ),
          Wrap(
            spacing: AriaTokens.s2,
            runSpacing: AriaTokens.s2,
            children: [
              ChoiceChip(
                label: Text(tr('Theme default')),
                selected: s.customAccent == null,
                onSelected: (_) =>
                    c.update((x) => x.copyWith(customAccent: () => null)),
              ),
              for (final color in kAccentChoices)
                _AccentDot(
                  color: color,
                  selected: s.customAccent == color.toARGB32(),
                  onTap: () {
                    if (!requireFeature(context, ref, Feature.customAccent)) {
                      return;
                    }
                    final preset = ThemePresets.byId(s.presetId);
                    final base = brightness == Brightness.dark
                        ? preset.dark
                        : preset.light;
                    if (!AppTheme.isAccentAccessible(
                      base.copyWith(primary: color),
                    )) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            tr(
                              'That colour is hard to read on this theme — try a deeper one.',
                            ),
                          ),
                        ),
                      );
                      return;
                    }
                    c.update((x) => x.copyWith(customAccent: color.toARGB32));
                  },
                ),
            ],
          ),
          const SizedBox(height: AriaTokens.s3),
          TextButton(onPressed: c.reset, child: Text(tr('Reset appearance'))),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.subtitle);
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AriaTokens.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleMedium),
          Text(
            subtitle,
            style: text.bodySmall?.copyWith(color: context.palette.muted),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.preset,
    required this.brightness,
    required this.selected,
    required this.onTap,
    this.locked = false,
  });

  final ThemePreset preset;
  final bool locked;
  final Brightness brightness;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = brightness == Brightness.dark ? preset.dark : preset.light;
    final current = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: locked
          ? tr('{0} theme, premium', [preset.label])
          : tr('{0} theme', [preset.label]),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AriaTokens.radiusMd),
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [p.primary, p.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: selected ? current.text : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check_rounded, color: p.onPrimary)
                    : null,
              ),
              const SizedBox(height: AriaTokens.s1),
              Text(
                locked ? '${preset.label} 🔒' : preset.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mini mock of a reminder card; updates live with every change.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return AriaCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: t.primaryGradient,
              borderRadius: BorderRadius.circular(AriaTokens.radiusSm),
            ),
            alignment: Alignment.center,
            child: const ExcludeSemantics(
              child: Text('💊', style: TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: AriaTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Vitamin D'), style: text.titleMedium),
                Text(
                  tr('8:30 AM · 4 tablets left'),
                  style: text.bodyMedium?.copyWith(color: t.palette.muted),
                ),
              ],
            ),
          ),
          FilledButton(onPressed: () {}, child: Text(tr('Done'))),
        ],
      ),
    );
  }
}

/// Deep, saturated accents (most pass AA on light themes).
const kAccentChoices = [
  Color(0xFFD81B60),
  Color(0xFF8E24AA),
  Color(0xFF3949AB),
  Color(0xFF00796B),
  Color(0xFF2E7D32),
  Color(0xFFEF6C00),
  Color(0xFF6D4C41),
];

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: tr('Accent colour'),
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? context.palette.text : Colors.transparent,
            width: 3,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white)
            : null,
      ),
    ),
  );
}
