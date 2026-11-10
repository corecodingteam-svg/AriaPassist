import 'dart:async';

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/features/assistant/application/assistant_controller.dart';
import 'package:aria/features/assistant/domain/parse_result.dart';
import 'package:aria/features/assistant/domain/when_text.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/alert_plan.dart';
import 'package:aria/features/reminders/domain/describe.dart';
import 'package:aria/features/reminders/domain/recurrence.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/voice/application/voice_providers.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Opens "Talk to Aria". [startListening] is false in tests / keyboard mode.
Future<void> showTalkSheet(
  BuildContext context, {
  bool startListening = true,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => TalkSheet(startListening: startListening),
);

class TalkSheet extends ConsumerStatefulWidget {
  const TalkSheet({this.startListening = true, super.key});
  final bool startListening;

  @override
  ConsumerState<TalkSheet> createState() => _TalkSheetState();
}

class _TalkSheetState extends ConsumerState<TalkSheet> {
  final _text = TextEditingController();
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    if (widget.startListening) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(ref.read(assistantProvider.notifier).listen());
      });
    } else {
      _typing = true;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _text.text;
    _text.clear();
    await ref.read(assistantProvider.notifier).submit(t);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(assistantProvider.select((s) => s.navigateTo), (_, to) {
      if (to == null || !context.mounted) return;
      final router = GoRouter.of(
        context,
      ); // before the sheet's context goes away
      Navigator.pop(context);
      unawaited(router.push(to));
    });
    final s = ref.watch(assistantProvider);
    // Keep the active circle resolved so ✓ can save immediately.
    ref.watch(activeCircleIdProvider);
    final ctl = ref.read(assistantProvider.notifier);
    final pa = ref.watch(voiceSettingsProvider).paName;
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final listening = s.phase == TalkPhase.listening;

    final status = switch (s.phase) {
      TalkPhase.listening => s.transcript.isEmpty ? 'Listening…' : s.transcript,
      TalkPhase.thinking => tr('Thinking…'),
      _ when !s.speechAvailable => tr(
        'Voice input isn’t available — type instead.',
      ),
      _ =>
        s.transcript.isEmpty
            ? tr('Tap the mic and tell me anything')
            : '“${s.transcript}”',
    };

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The conversation scrolls; the actions below stay pinned.
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: AriaTokens.s5),
                children: [
                  Text(
                    tr('Talk to {0}', [pa]),
                    textAlign: TextAlign.center,
                    style: text.titleLarge,
                  ),
                  const SizedBox(height: AriaTokens.s4),
                  Center(
                    child: _Orb(
                      level: s.level,
                      active: listening,
                      thinking: s.phase == TalkPhase.thinking,
                    ),
                  ),
                  const SizedBox(height: AriaTokens.s4),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      status,
                      key: const Key('talk-status'),
                      textAlign: TextAlign.center,
                      style: text.bodyLarge?.copyWith(color: p.muted),
                    ),
                  ),
                  if (s.reply != null) ...[
                    const SizedBox(height: AriaTokens.s4),
                    _ReplyBubble(text: s.reply!),
                  ],
                  for (final (i, d) in s.drafts.indexed) ...[
                    const SizedBox(height: AriaTokens.s3),
                    _DraftCard(
                      item: d,
                      onRemove: () => ctl.removeDraft(i),
                      onEdit: () async {
                        final r = await ctl.reminderFor(d);
                        if (r == null || !context.mounted) return;
                        ctl.removeDraft(i);
                        Navigator.pop(context);
                        unawaited(context.push('/reminder/new', extra: r));
                      },
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AriaTokens.s5,
                0,
                AriaTokens.s5,
                AriaTokens.s5,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (s.drafts.isNotEmpty) ...[
                    const SizedBox(height: AriaTokens.s3),
                    FilledButton.icon(
                      key: const Key('confirm-drafts'),
                      onPressed: () async {
                        unawaited(HapticFeedback.lightImpact());
                        await ctl.confirm();
                      },
                      icon: const Icon(Icons.check_rounded),
                      label: Text(
                        s.drafts.length == 1
                            ? tr('Add reminder')
                            : tr('Add {0} reminders', [s.drafts.length]),
                      ),
                    ),
                  ],
                  const SizedBox(height: AriaTokens.s4),
                  if (_typing)
                    TextField(
                      key: const Key('talk-input'),
                      controller: _text,
                      autofocus: true,
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        hintText: tr(
                          'e.g. remind me to pay rent on the 1st of every month',
                        ),
                        suffixIcon: IconButton(
                          tooltip: tr('Send'),
                          onPressed: _send,
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  const SizedBox(height: AriaTokens.s3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        tooltip: _typing
                            ? tr('Hide keyboard')
                            : tr('Type instead'),
                        onPressed: () => setState(() => _typing = !_typing),
                        icon: Icon(
                          _typing
                              ? Icons.keyboard_hide_rounded
                              : Icons.keyboard_rounded,
                        ),
                      ),
                      const SizedBox(width: AriaTokens.s5),
                      IconButton.filled(
                        tooltip: listening ? tr('Stop listening') : tr('Speak'),
                        iconSize: 32,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(64, 64),
                        ),
                        onPressed: listening ? ctl.stopListening : ctl.listen,
                        icon: Icon(
                          listening ? Icons.stop_rounded : Icons.mic_rounded,
                        ),
                      ),
                      const SizedBox(width: AriaTokens.s5),
                      IconButton.filledTonal(
                        tooltip: tr('Close'),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Breathing orb; grows with mic level, pulses while thinking.
class _Orb extends StatelessWidget {
  const _Orb({
    required this.level,
    required this.active,
    required this.thinking,
  });
  final double level;
  final bool active;
  final bool thinking;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scale = 1.0 + (active ? level * 0.35 : 0.0) + (thinking ? 0.08 : 0.0);
    return ExcludeSemantics(
      child: AnimatedScale(
        scale: scale,
        duration: t.motion == Duration.zero
            ? Duration.zero
            : const Duration(milliseconds: 120),
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: t.primaryGradient,
            boxShadow: [
              BoxShadow(
                color: t.palette.primary.withValues(alpha: active ? 0.45 : 0.2),
                blurRadius: 28,
                spreadRadius: active ? 6 : 0,
              ),
            ],
          ),
          child: Icon(
            thinking ? Icons.auto_awesome_rounded : Icons.graphic_eq_rounded,
            color: t.palette.onPrimary,
            size: 40,
          ),
        ),
      ),
    );
  }
}

class _ReplyBubble extends StatelessWidget {
  const _ReplyBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(AriaTokens.s4),
      decoration: BoxDecoration(
        color: p.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AriaTokens.radiusLg),
      ),
      child: Text(
        text,
        key: const Key('talk-reply'),
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}

class _DraftCard extends ConsumerWidget {
  const _DraftCard({
    required this.item,
    required this.onRemove,
    required this.onEdit,
  });
  final ParsedItem item;
  final VoidCallback onRemove;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zone = ref.watch(deviceTimeZoneProvider);
    final now = ref.read(clockProvider)();
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final rule = RecurrenceRule.tryParse(item.rrule);
    final when = item.at == null && item.place != null
        ? '📍 ${item.placeOn == PlaceTransition.arrive ? tr('When you get to') : tr('When you leave')} ${item.place}'
        : item.at == null
        ? tr('When? Say a time or tap ✎')
        : describeWhen(
            at: item.at,
            allDay: item.allDay,
            rrule: null,
            now: now,
            zone: zone,
          );
    final lines = [
      when,
      if (rule != null && item.at != null)
        describeRule(rule, toWall(item.at!, zone)),
      if (item.amount != null) formatRupees(item.amount!),
      if (item.priority.name != 'normal') item.priority.label,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AriaTokens.s4,
          AriaTokens.s3,
          AriaTokens.s1,
          AriaTokens.s3,
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Text(
                item.category.emoji,
                style: const TextStyle(fontSize: 26),
              ),
            ),
            const SizedBox(width: AriaTokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: text.titleMedium),
                  Text(
                    lines.join(' · '),
                    style: text.bodyMedium?.copyWith(
                      color: !item.hasTrigger ? p.danger : p.muted,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: tr('Edit'),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_rounded),
            ),
            IconButton(
              tooltip: tr('Remove'),
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
