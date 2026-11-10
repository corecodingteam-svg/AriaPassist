import 'dart:async';

import 'package:aria/core/telemetry/telemetry.dart';
import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/theme/presets.dart';
import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/data/providers.dart';
import 'package:aria/features/assistant/presentation/talk_sheet.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/help/application/reliability.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/preferences/domain/app_prefs.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/voice/application/voice_engine.dart';
import 'package:aria/features/voice/application/voice_providers.dart';
import 'package:aria/features/voice/domain/phrases.dart';
import 'package:aria/features/voice/domain/voice_settings.dart';
import 'package:aria/features/voice/domain/voices.dart';
import 'package:aria/features/voice/presentation/reminder_style_screen.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Onboarding (spec §4): ≤ 60 s, skippable after the welcome step.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  static const steps = 8;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  final _name = TextEditingController();
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _name.text = ref.read(appPrefsProvider).userName ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _say(
          tr(
            "Hi, I'm Aria, your personal assistant. Let's set things up in under a minute.",
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _say(String text) async {
    try {
      await ref
          .read(speakerProvider)
          .speak(text, ref.read(voiceProfileProvider));
    } on Object {
      // Voice is a nicety here; never block onboarding on it.
    }
  }

  void _go(int step) {
    unawaited(ref.read(speakerProvider).stop());
    setState(() => _step = step);
    _pages.animateToPage(
      step,
      duration: context.tokens.motion,
      curve: Curves.easeOut,
    );
  }

  Future<void> _finish() async {
    ref.read(telemetryProvider).event(TelemetryEvent.onboardingCompleted);
    final name = _name.text.trim();
    ref
        .read(appPrefsProvider.notifier)
        .update(
          (p) => p.copyWith(
            onboarded: true,
            userName: () => name.isEmpty ? null : name,
          ),
        );
    if (name.isNotEmpty) {
      final uid = ref.read(currentUserIdProvider);
      try {
        await ref
            .read(supabaseClientProvider)
            .from('users')
            .update({'name': name})
            .eq('id', uid ?? '');
      } on Object {
        // Offline or tests: the local name is enough; it syncs with settings.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final last = _step == OnboardingScreen.steps - 1;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: _step > 0
            ? IconButton(
                tooltip: tr('Back'),
                onPressed: () => _go(_step - 1),
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : null,
        title: Semantics(
          label: tr('Step {0} of {1}', [_step + 1, OnboardingScreen.steps]),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < OnboardingScreen.steps; i++)
                  AnimatedContainer(
                    duration: context.tokens.motion,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _step ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i <= _step
                          ? context.palette.primary
                          : context.palette.muted.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          if (_step > 0 && !last)
            TextButton(onPressed: _finish, child: Text(tr('Skip'))),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _Welcome(name: _name),
                  const _LanguageStep(),
                  const _VoiceStep(),
                  const _ModeStep(),
                  const _ThemeStep(),
                  const _PermissionsStep(),
                  const _CircleStep(),
                  const _FirstReminderStep(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AriaTokens.s5),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('onboarding-next'),
                  onPressed: last ? _finish : () => _go(_step + 1),
                  child: Text(
                    switch (_step) {
                      0 => tr('Let’s go'),
                      _ when last => tr('Finish'),
                      _ => tr('Next'),
                    },
                    style: text.titleMedium?.copyWith(
                      color: context.palette.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.title, required this.children, this.subtitle});
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AriaTokens.s5),
      children: [
        const SizedBox(height: AriaTokens.s4),
        Text(
          title,
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AriaTokens.s2),
          Text(
            subtitle!,
            style: text.bodyLarge?.copyWith(color: context.palette.muted),
          ),
        ],
        const SizedBox(height: AriaTokens.s5),
        ...children,
      ],
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.name});
  final TextEditingController name;

  @override
  Widget build(BuildContext context) => _Step(
    title: tr('Hi, I’m Aria 👋'),
    subtitle: tr(
      'Your personal assistant. I’ll remind you about every small and big thing — by voice or by notification. Setup takes under a minute.',
    ),
    children: [
      TextField(
        key: const Key('onboarding-name'),
        controller: name,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: tr('What should I call you? (optional)'),
          prefixIcon: const Icon(Icons.waving_hand_outlined),
        ),
      ),
    ],
  );
}

class _LanguageStep extends ConsumerWidget {
  const _LanguageStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(voiceSettingsProvider.select((s) => s.language));
    return _Step(
      title: tr('Which language?'),
      subtitle: tr(
        'For my voice and for understanding you. Hinglish works too!',
      ),
      children: [
        for (final l in VoiceLanguage.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AriaTokens.s2),
            child: ChoiceChip(
              label: SizedBox(width: double.infinity, child: Text(l.label)),
              selected: lang == l,
              onSelected: (_) {
                ref
                    .read(voiceSettingsProvider.notifier)
                    .update((s) => s.copyWith(language: l));
                // Hindi voice → Hindi screens too (changeable in Appearance).
                ref
                    .read(appPrefsProvider.notifier)
                    .update(
                      (p) => p.copyWith(
                        appLanguage: l == VoiceLanguage.hi
                            ? AppLanguage.hi
                            : AppLanguage.system,
                      ),
                    );
              },
            ),
          ),
      ],
    );
  }
}

class _VoiceStep extends ConsumerWidget {
  const _VoiceStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(voiceSettingsProvider);
    final ctl = ref.read(voiceSettingsProvider.notifier);
    return _Step(
      title: tr('Choose my voice'),
      subtitle: tr('Tap ▶ to hear each one. You can change this any time.'),
      children: [
        for (final v in Voices.all.where((v) => v.isFree || v.id != 'device'))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              s.voiceId == v.id
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: context.palette.primary,
            ),
            title: Text(v.isFree ? v.name : '${v.name}  🔒'),
            subtitle: Text(v.description),
            trailing: IconButton(
              tooltip: tr('Preview {0}', [v.name]),
              icon: const Icon(Icons.play_circle_fill_rounded),
              onPressed: () {
                final with_ = s.copyWith(voiceId: v.id);
                unawaited(
                  ref
                      .read(speakerProvider)
                      .speak(Phrases(with_).sample(), VoiceProfile.of(with_)),
                );
              },
            ),
            onTap: v.isFree
                ? () => ctl.update((x) => x.copyWith(voiceId: v.id))
                : null,
          ),
        const SizedBox(height: AriaTokens.s3),
        TextFormField(
          initialValue: s.paName,
          maxLength: 30,
          decoration: InputDecoration(
            labelText: tr('Rename your assistant (optional)'),
          ),
          onChanged: (v) {
            if (v.trim().isNotEmpty) {
              ctl.update((x) => x.copyWith(paName: v.trim()));
            }
          },
        ),
      ],
    );
  }
}

class _ModeStep extends ConsumerWidget {
  const _ModeStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(voiceSettingsProvider.select((s) => s.defaultMode));
    return _Step(
      title: tr('How should I remind you?'),
      subtitle: tr(
        'You can pick differently per category later (e.g. voice for medicines).',
      ),
      children: [
        for (final m in [
          NotifyMode.voice,
          NotifyMode.text,
          NotifyMode.both,
          NotifyMode.vibrate,
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: AriaTokens.s2),
            child: ChoiceChip(
              key: Key('mode-${m.name}'),
              label: SizedBox(
                width: double.infinity,
                child: Text('${kModeLabels[m]!.$1}  ${kModeLabels[m]!.$2}'),
              ),
              selected: mode == m,
              onSelected: (_) => ref
                  .read(voiceSettingsProvider.notifier)
                  .update((s) => s.copyWith(defaultMode: m)),
            ),
          ),
      ],
    );
  }
}

class _ThemeStep extends ConsumerWidget {
  const _ThemeStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(themeControllerProvider);
    final ctl = ref.read(themeControllerProvider.notifier);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _Step(
      title: tr('Pick a look'),
      subtitle: tr('The whole app changes as you tap.'),
      children: [
        SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(value: ThemeMode.light, label: Text(tr('Light'))),
            ButtonSegment(value: ThemeMode.dark, label: Text(tr('Dark'))),
            ButtonSegment(value: ThemeMode.system, label: Text(tr('Auto'))),
          ],
          selected: {s.mode},
          onSelectionChanged: (v) => ctl.setMode(v.first),
        ),
        const SizedBox(height: AriaTokens.s4),
        Wrap(
          spacing: AriaTokens.s3,
          runSpacing: AriaTokens.s3,
          children: [
            for (final preset in ThemePresets.all.where((p) => p.isFree))
              Semantics(
                button: true,
                selected: s.presetId == preset.id,
                label: tr('{0} theme', [preset.label]),
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => ctl.setPreset(preset.id),
                  borderRadius: BorderRadius.circular(AriaTokens.radiusLg),
                  child: Container(
                    width: 96,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AriaTokens.radiusLg),
                      gradient: LinearGradient(
                        colors: [
                          (dark ? preset.dark : preset.light).primary,
                          (dark ? preset.dark : preset.light).secondary,
                        ],
                      ),
                      border: Border.all(
                        color: s.presetId == preset.id
                            ? context.palette.text
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    alignment: Alignment.bottomLeft,
                    padding: const EdgeInsets.all(AriaTokens.s2),
                    child: Text(
                      preset.label,
                      style: TextStyle(
                        color: (dark ? preset.dark : preset.light).onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AriaTokens.s3),
        Text(
          tr('More themes are in Settings › Appearance.'),
          style: TextStyle(color: context.palette.muted),
        ),
      ],
    );
  }
}

/// Explains *why* before asking (spec §4 step 6).
class _PermissionsStep extends ConsumerStatefulWidget {
  const _PermissionsStep();

  @override
  ConsumerState<_PermissionsStep> createState() => _PermissionsStepState();
}

class _PermissionsStepState extends ConsumerState<_PermissionsStep> {
  @override
  Widget build(BuildContext context) {
    final checks =
        ref.watch(reliabilityChecksProvider).value ??
        const <ReliabilityCheck>[];
    final device = ref.watch(deviceHealthProvider);
    final mic = ref.watch(_micReadyProvider).value;

    Widget row(
      String emoji,
      String title,
      String why, {
      required bool? ok,
      VoidCallback? onAllow,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: AriaTokens.s2),
      child: AriaCard(
        child: Row(
          children: [
            ExcludeSemantics(
              child: Text(emoji, style: const TextStyle(fontSize: 26)),
            ),
            const SizedBox(width: AriaTokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(why, style: TextStyle(color: context.palette.muted)),
                ],
              ),
            ),
            if (ok ?? false)
              Icon(
                Icons.check_circle_rounded,
                color: context.palette.success,
                semanticLabel: tr('Allowed'),
              )
            else
              TextButton(onPressed: onAllow, child: Text(tr('Allow'))),
          ],
        ),
      ),
    );

    ReliabilityCheck? check(String id) =>
        checks.where((c) => c.id == id).firstOrNull;
    Future<void> runFix(String id) async {
      await check(id)?.fix?.call();
      ref.invalidate(reliabilityChecksProvider);
    }

    final oem = check('oem');
    return _Step(
      title: tr('A few permissions'),
      subtitle: tr('So reminders ring on time — even when your phone is idle.'),
      children: [
        row(
          '🔔',
          tr('Notifications'),
          tr('To show your reminders.'),
          ok: check('notifications')?.status == CheckStatus.ok,
          onAllow: () => runFix('notifications'),
        ),
        if (device.isAndroid) ...[
          row(
            '⏰',
            tr('Alarms & reminders'),
            tr('To ring at the exact minute, not a few minutes late.'),
            ok: check('exact')?.status == CheckStatus.ok,
            onAllow: () => runFix('exact'),
          ),
          row(
            '🔋',
            tr('Battery'),
            tr('So your phone doesn’t silence Aria to save battery.'),
            ok: check('battery')?.status == CheckStatus.ok,
            onAllow: () => runFix('battery'),
          ),
        ],
        row(
          '🎙️',
          tr('Microphone (optional)'),
          tr('To set reminders by voice. Audio is never stored.'),
          ok: mic,
          onAllow: () => ref.invalidate(_micReadyProvider),
        ),
        if (oem != null) ...[
          const SizedBox(height: AriaTokens.s2),
          Text(oem.detail, style: TextStyle(color: context.palette.muted)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => runFix('oem'),
              child: Text(tr('Open phone settings')),
            ),
          ),
        ],
        const SizedBox(height: AriaTokens.s2),
        Text(
          tr(
            'Location and calendar are optional and come with location reminders and calendar sync.',
          ),
          style: TextStyle(color: context.palette.muted),
        ),
      ],
    );
  }
}

/// Asks for mic + speech permission when (re)read.
final FutureProvider<bool> _micReadyProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.read(speechInputProvider).init(),
);

class _CircleStep extends StatelessWidget {
  const _CircleStep();

  @override
  Widget build(BuildContext context) => _Step(
    title: tr('Manage reminders with family?'),
    subtitle: tr(
      'Share lists, remind each other, and look after parents — one plan for up to 5 people.',
    ),
    children: [
      AriaCard(
        child: Text(
          tr('👪  You can create a family Circle any time from Me › Circle.'),
        ),
      ),
    ],
  );
}

class _FirstReminderStep extends ConsumerWidget {
  const _FirstReminderStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final created = ref.watch(myRemindersProvider).value?.isNotEmpty ?? false;
    return _Step(
      title: tr('Let’s set your first reminder'),
      subtitle: tr('Try saying: “Remind me to drink water at 11 AM.”'),
      children: [
        FilledButton.tonalIcon(
          key: const Key('onboarding-try'),
          onPressed: () => showTalkSheet(context),
          icon: const Icon(Icons.mic_rounded),
          label: Text(tr('Talk to Aria')),
        ),
        if (created) ...[
          const SizedBox(height: AriaTokens.s4),
          AriaCard(
            child: Text(
              tr(
                '🎉 Nice! Your first reminder is set. Tap Finish to see your day.',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ],
    );
  }
}
