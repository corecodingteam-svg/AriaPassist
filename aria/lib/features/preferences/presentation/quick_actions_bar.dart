import 'dart:async';

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/features/assistant/presentation/talk_sheet.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/preferences/domain/app_prefs.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Today's one-tap shortcuts (Settings › Simplify › Quick actions).
/// Each opens the editor pre-filled for the next whole hour — two taps total.
class QuickActionsBar extends ConsumerWidget {
  const QuickActionsBar({required this.actions, super.key});
  final List<QuickAction> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Wrap(
    spacing: AriaTokens.s2,
    runSpacing: AriaTokens.s2,
    children: [
      for (final a in actions)
        ActionChip(
          avatar: ExcludeSemantics(child: Text(a.emoji)),
          label: Text(a.label),
          onPressed: () => unawaited(_run(context, ref, a)),
        ),
    ],
  );

  Future<void> _run(BuildContext context, WidgetRef ref, QuickAction a) async {
    unawaited(ref.read(hapticsProvider).light());
    if (a == QuickAction.talk) {
      await showTalkSheet(context);
      return;
    }
    // Next whole hour on the *local* clock (IST is UTC+5:30, so UTC hours
    // would land on :30).
    final zone = ref.read(deviceTimeZoneProvider);
    final w = toWall(ref.read(clockProvider)().toUtc(), zone);
    final nextHour = fromWall(
      DateTime.utc(w.year, w.month, w.day, w.hour + 1),
      zone,
    );
    // Only the content fields matter; the editor assigns ids/circle on save.
    final draft = Reminder(
      id: '',
      circleId: '',
      createdBy: '',
      title: a.title,
      category: a.category,
      startAt: nextHour,
      timezone: zone,
    );
    if (context.mounted) await context.push('/reminder/new', extra: draft);
  }
}

/// A dismissible first-run hint (Settings › Interactive tips).
class TipCard extends ConsumerWidget {
  const TipCard({required this.id, required this.text, super.key});
  final String id;
  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(top: AriaTokens.s2),
      padding: const EdgeInsets.fromLTRB(
        AriaTokens.s4,
        AriaTokens.s2,
        AriaTokens.s1,
        AriaTokens.s2,
      ),
      decoration: BoxDecoration(
        color: p.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AriaTokens.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline_rounded, color: p.primary),
          const SizedBox(width: AriaTokens.s3),
          Expanded(child: Text(text)),
          IconButton(
            tooltip: tr('Got it'),
            onPressed: () => ref.read(appPrefsProvider.notifier).dismissTip(id),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}
