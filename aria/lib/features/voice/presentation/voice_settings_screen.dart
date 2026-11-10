import 'dart:async';

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:aria/features/voice/application/voice_engine.dart';
import 'package:aria/features/voice/application/voice_providers.dart';
import 'package:aria/features/voice/domain/phrases.dart';
import 'package:aria/features/voice/domain/voice_settings.dart';
import 'package:aria/features/voice/domain/voices.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Settings › Voice & personality (spec 6.1).
class VoiceSettingsScreen extends ConsumerWidget {
  const VoiceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(voiceSettingsProvider);
    final ctl = ref.read(voiceSettingsProvider.notifier);
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final plan = ref.watch(entitlementProvider).plan;

    Future<void> preview(VoiceSettings with_) => ref
        .read(speakerProvider)
        .speak(Phrases(with_).sample(), VoiceProfile.of(with_));

    return Scaffold(
      appBar: AppBar(title: Text(tr('Voice & personality'))),
      body: ListView(
        padding: const EdgeInsets.all(AriaTokens.s4),
        children: [
          _Header(tr('Choose voice'), tr('Tap ▶ to hear a sample reminder')),
          for (final v in Voices.all)
            Padding(
              padding: const EdgeInsets.only(bottom: AriaTokens.s2),
              child: _VoiceCard(
                voice: v,
                selected: s.voiceId == v.id,
                onPreview: () => preview(s.copyWith(voiceId: v.id)),
                locked: !plan.voiceAllowed(v.id),
                onSelect: () {
                  if (!plan.voiceAllowed(v.id) &&
                      !requireFeature(context, ref, Feature.premiumVoices)) {
                    return;
                  }
                  ctl.update((x) => x.copyWith(voiceId: v.id));
                },
              ),
            ),
          const SizedBox(height: AriaTokens.s3),
          _Header(tr('Your PA’s name'), tr('Used in greetings and replies')),
          TextFormField(
            key: const Key('pa-name'),
            initialValue: s.paName,
            maxLength: 30,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            onChanged: (v) {
              final name = v.trim();
              if (name.isNotEmpty) ctl.update((x) => x.copyWith(paName: name));
            },
          ),
          _Header(tr('Speaking speed'), '${s.speed.toStringAsFixed(2)}×'),
          Slider(
            value: s.speed,
            min: 0.75,
            max: 1.5,
            divisions: 15,
            label: '${s.speed.toStringAsFixed(2)}×',
            onChanged: (v) => ctl.update((x) => x.copyWith(speed: v)),
            onChangeEnd: (_) => preview(ref.read(voiceSettingsProvider)),
          ),
          _Header(
            tr('Pitch'),
            s.pitch == 1 ? 'Natural' : s.pitch.toStringAsFixed(2),
          ),
          Slider(
            value: s.pitch,
            min: 0.5,
            max: 2,
            divisions: 30,
            onChanged: (v) => ctl.update((x) => x.copyWith(pitch: v)),
            onChangeEnd: (_) => preview(ref.read(voiceSettingsProvider)),
          ),
          _Header(tr('Personality'), tr('Changes how Aria phrases things')),
          RadioGroup<Personality>(
            groupValue: s.personality,
            onChanged: (v) {
              if (v == null) return;
              ctl.update((x) => x.copyWith(personality: v));
              unawaited(preview(ref.read(voiceSettingsProvider)));
            },
            child: Column(
              children: [
                for (final pers in Personality.values)
                  RadioListTile<Personality>(
                    contentPadding: EdgeInsets.zero,
                    value: pers,
                    title: Text('${pers.emoji} ${pers.label}'),
                    subtitle: Text(
                      '“${Phrases(s.copyWith(personality: pers)).sample()}”',
                      style: text.bodySmall?.copyWith(color: p.muted),
                    ),
                  ),
              ],
            ),
          ),
          _Header(
            tr('Language of voice'),
            tr('What Aria speaks and listens for'),
          ),
          SegmentedButton<VoiceLanguage>(
            segments: [
              for (final l in VoiceLanguage.values)
                ButtonSegment(value: l, label: Text(l.label)),
            ],
            selected: {s.language},
            onSelectionChanged: (v) =>
                ctl.update((x) => x.copyWith(language: v.first)),
          ),
          const SizedBox(height: AriaTokens.s3),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Spoken confirmations')),
            subtitle: Text(tr('Aria says “Done, reminder set” out loud')),
            value: s.spokenConfirmations,
            onChanged: (v) =>
                ctl.update((x) => x.copyWith(spokenConfirmations: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Speak even on silent (Android)')),
            subtitle: Text(
              tr(
                'Uses the alarm volume so you hear Aria when the ringer is off',
              ),
            ),
            value: s.useAlarmStream,
            onChanged: (v) => ctl.update((x) => x.copyWith(useAlarmStream: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Wake phrase “Hey Aria”')),
            subtitle: Text(tr('Coming later — off to save battery')),
            value: false,
            onChanged: null,
          ),
        ],
      ),
    );
  }
}

class _VoiceCard extends StatelessWidget {
  const _VoiceCard({
    required this.voice,
    required this.selected,
    required this.onPreview,
    required this.onSelect,
    this.locked = false,
  });

  final VoiceOption voice;
  final bool locked;
  final bool selected;
  final VoidCallback onPreview;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      child: AriaCard(
        onTap: onSelect,
        padding: const EdgeInsets.symmetric(
          horizontal: AriaTokens.s4,
          vertical: AriaTokens.s2,
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? p.primary : p.muted,
            ),
            const SizedBox(width: AriaTokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    locked ? '${voice.name}  🔒' : voice.name,
                    style: text.titleMedium,
                  ),
                  Text(
                    voice.description,
                    style: text.bodySmall?.copyWith(color: p.muted),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: tr('Preview {0}', [voice.name]),
              onPressed: onPreview,
              icon: const Icon(Icons.play_circle_fill_rounded),
              color: p.primary,
              iconSize: 32,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title, this.subtitle);
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AriaTokens.s4, bottom: AriaTokens.s2),
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
