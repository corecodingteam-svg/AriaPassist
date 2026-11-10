import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/preferences/domain/app_prefs.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/today_sections.dart';
import 'package:aria/features/reminders/presentation/formatting.dart';
import 'package:aria/features/reminders/presentation/reminder_actions.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Timeline row. Swipe right = Done, swipe left = Snooze, long-press = edit.
class ReminderTile extends ConsumerWidget {
  const ReminderTile({
    required this.entry,
    this.section,
    this.swipeable = true,
    super.key,
  });

  final TodayEntry entry;
  final TodaySection? section;
  final bool swipeable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = entry.reminder;
    final p = context.palette;
    final zone = ref.watch(deviceTimeZoneProvider);
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final text = Theme.of(context).textTheme;
    final overdue = section == TodaySection.overdue;
    final done = section == TodaySection.done;
    final actions = ReminderActions(context, ref);

    final timeLabel = switch (entry.fireAt) {
      null => tr('Anytime'),
      _ when done => formatTime(context, entry.fireAt!, zone),
      _ when r.allDay && r.snoozedUntil == null => tr('All day'),
      final f when section == TodaySection.upcoming => formatWhen(
        context,
        f,
        zone,
        now: now,
        allDay: r.allDay,
      ).replaceFirst(', ', '\n'),
      final f => formatTime(context, f, zone),
    };
    final me = ref.watch(currentUserIdProvider);
    final from = r.createdBy == me
        ? null
        : ref.watch(memberNamesProvider).value?[r.createdBy];
    final base = subtitleFor(context, r, zone, now: now);
    final subtitle = [
      if (base.isNotEmpty) base,
      if (from != null) tr('from {0}', [from]),
    ].join(' · ');

    final card = Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AriaTokens.radiusLg),
        side: overdue ? BorderSide(color: p.danger, width: 2) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/reminder/${r.id}'),
        onLongPress: () => context.push('/reminder/${r.id}/edit'),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AriaTokens.s3,
            vertical: AriaTokens.s3,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 84, // fits "10:42 PM" at default text size
                child: Text(
                  timeLabel,
                  style: text.labelLarge?.copyWith(
                    color: overdue ? p.danger : p.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ExcludeSemantics(
                child: Text(
                  r.category.emoji,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              const SizedBox(width: AriaTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? p.muted : null,
                      ),
                    ),
                    if (overdue || subtitle.isNotEmpty)
                      Text(
                        [
                          if (overdue) tr('Overdue'),
                          if (subtitle.isNotEmpty) subtitle,
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: overdue ? p.danger : p.muted,
                          fontWeight: overdue ? FontWeight.w700 : null,
                        ),
                      ),
                  ],
                ),
              ),
              Semantics(
                label: done ? tr('Done') : tr('Mark {0} done', [r.title]),
                child: Checkbox(
                  value: done,
                  onChanged: done || !r.isActive
                      ? null
                      : (_) => actions.complete(r),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final prefs = ref.watch(appPrefsProvider);
    if (!swipeable || done || !r.isActive || !prefs.swipeEnabled) return card;
    final p2 = context.palette;
    _SwipeBg bg(SwipeAction a, Alignment align) => switch (a) {
      SwipeAction.done => _SwipeBg(
        color: p2.success,
        onColor: p2.onSuccess,
        icon: Icons.check_rounded,
        label: tr('Done'),
        alignment: align,
      ),
      SwipeAction.snooze => _SwipeBg(
        color: p2.warning,
        onColor: p2.onWarning,
        icon: Icons.snooze_rounded,
        label: tr('{0} min', [prefs.defaultSnoozeMin]),
        alignment: align,
      ),
      SwipeAction.delete => _SwipeBg(
        color: p2.danger,
        onColor: p2.onDanger,
        icon: Icons.delete_outline_rounded,
        label: tr('Delete'),
        alignment: align,
      ),
      SwipeAction.none => _SwipeBg(
        color: Colors.transparent,
        onColor: p2.muted,
        icon: Icons.block,
        label: '',
        alignment: align,
      ),
    };
    return Dismissible(
      key: ValueKey('tile-${r.id}-${section?.name}'),
      direction: switch ((prefs.swipeRight, prefs.swipeLeft)) {
        (SwipeAction.none, SwipeAction.none) => DismissDirection.none,
        (SwipeAction.none, _) => DismissDirection.endToStart,
        (_, SwipeAction.none) => DismissDirection.startToEnd,
        _ => DismissDirection.horizontal,
      },
      background: bg(prefs.swipeRight, Alignment.centerLeft),
      secondaryBackground: bg(prefs.swipeLeft, Alignment.centerRight),
      confirmDismiss: (dir) async {
        await actions.swipe(
          r,
          dir == DismissDirection.startToEnd
              ? prefs.swipeRight
              : prefs.swipeLeft,
        );
        // The stream re-renders the row in its new place; never remove it
        // here, or Undo would have nothing to bring back.
        return false;
      },
      child: card,
    );
  }
}

class _SwipeBg extends StatelessWidget {
  const _SwipeBg({
    required this.color,
    required this.onColor,
    required this.icon,
    required this.label,
    required this.alignment,
  });
  final Color color;
  final Color onColor;
  final IconData icon;
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(AriaTokens.radiusLg),
    ),
    alignment: alignment,
    padding: const EdgeInsets.symmetric(horizontal: AriaTokens.s5),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: onColor),
        const SizedBox(width: AriaTokens.s2),
        Text(
          label,
          style: TextStyle(color: onColor, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
