import 'dart:async';

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/core/widgets/state_views.dart';
import 'package:aria/data/providers.dart';
import 'package:aria/features/account/presentation/privacy_screen.dart';
import 'package:aria/features/assistant/presentation/talk_sheet.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/calendar/calendar.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/preferences/presentation/quick_actions_bar.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/alert_plan.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/today_sections.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/reminders/presentation/permission_banner.dart';
import 'package:aria/features/reminders/presentation/reminder_tile.dart';
import 'package:aria/features/subscription/presentation/renewal_banner.dart';
import 'package:aria/features/suggestions/suggestions.dart';
import 'package:aria/features/voice/application/voice_engine.dart';
import 'package:aria/features/voice/application/voice_providers.dart';
import 'package:aria/features/voice/domain/phrases.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

final todayFilterProvider = NotifierProvider<_Filter, ReminderCategory?>(
  _Filter.new,
);

class _Filter extends Notifier<ReminderCategory?> {
  @override
  ReminderCategory? build() => null;
  // ignore: use_setters_to_change_properties -- reads better at call sites
  void set(ReminderCategory? c) => state = c;
}

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({this.openTalk = false, super.key});

  /// Open "Talk to Aria" on arrival (aria:///talk).
  final bool openTalk;

  static String greetingFor(DateTime wall) => _TodayBody.greetingFor(wall);

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.openTalk) _openTalk();
  }

  // Today usually already exists (shell branch), so a later aria:///talk
  // arrives as a property change, not a new screen.
  @override
  void didUpdateWidget(TodayScreen old) {
    super.didUpdateWidget(old);
    if (widget.openTalk && !old.openTalk) _openTalk();
  }

  void _openTalk() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Clear ?talk=1 so the next link opens the sheet again.
      context.go('/today');
      unawaited(showTalkSheet(context));
    });
  }

  @override
  Widget build(BuildContext context) => const _TodayBody();
}

class _TodayBody extends ConsumerWidget {
  const _TodayBody();

  static String greetingFor(DateTime wall) => switch (wall.hour) {
    < 5 => tr('Good night'),
    < 12 => tr('Good morning'),
    < 17 => tr('Good afternoon'),
    _ => tr('Good evening'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zone = ref.watch(deviceTimeZoneProvider);
    final now = (ref.watch(nowProvider).value ?? ref.read(clockProvider)())
        .toUtc();
    final wall = toWall(now, zone);
    final filter = ref.watch(todayFilterProvider);
    final reminders = ref.watch(myRemindersProvider);
    final missed = ref.watch(missedProvider).value ?? const [];
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final prefs = ref.watch(appPrefsProvider);
    final simple = ref.watch(simpleModeProvider);
    final actions = <Widget>[
      if (!simple)
        IconButton(
          tooltip: tr('Search'),
          onPressed: () => context.push('/search'),
          icon: const Icon(Icons.search_rounded),
        ),
      IconButton(
        tooltip: tr('New reminder'),
        onPressed: () => context.push('/reminder/new'),
        icon: const Icon(Icons.add_circle_outline_rounded),
      ),
      ProfileAvatarButton(onPressed: () => context.push('/me')),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          prefs.userName == null
              ? greetingFor(wall)
              : '${greetingFor(wall)}, ${prefs.userName}',
        ),
        // One-handed mode moves these to the bottom of the screen.
        actions: prefs.oneHanded ? null : actions,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: prefs.oneHanded
          ? Padding(
              padding: const EdgeInsets.only(bottom: 88),
              child: Material(
                color: p.surface,
                elevation: 3,
                shape: const StadiumBorder(),
                child: Row(mainAxisSize: MainAxisSize.min, children: actions),
              ),
            )
          : null,
      body: reminders.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(myRemindersProvider),
        ),
        data: (all) {
          final sections = buildToday(
            all,
            now: now,
            zone: zone,
            filter: filter,
          );
          return RefreshIndicator(
            onRefresh: () async {
              await ref.read(syncEngineProvider)?.syncNow();
              await ref.read(reminderServiceProvider)?.refresh();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AriaTokens.s4,
                0,
                AriaTokens.s4,
                120,
              ),
              children: [
                Text(
                  DateFormat('EEEE, d MMMM').format(wall),
                  style: text.bodyLarge?.copyWith(color: p.muted),
                ),
                const SizedBox(height: AriaTokens.s4),
                const PermissionBanner(),
                const PendingDeletionBanner(),
                const RenewalBanner(),
                if (missed.isNotEmpty) ...[
                  AriaCard(
                    onTap: () => context.push('/notifications'),
                    child: Row(
                      children: [
                        Icon(Icons.history_rounded, color: p.danger),
                        const SizedBox(width: AriaTokens.s3),
                        Expanded(
                          child: Text(
                            tr('You missed {0} reminder{1}', [
                              missed.length,
                              missed.length == 1 ? '' : 's',
                            ]),
                            style: text.titleMedium,
                          ),
                        ),
                        Text(tr('Review')),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                  const SizedBox(height: AriaTokens.s3),
                ],
                _BriefingCard(sections: sections),
                const SizedBox(height: AriaTokens.s3),
                if (filter == null) const CalendarSection(),
                if (filter == null && !simple) const SuggestionCard(),
                if (prefs.quickActions.isNotEmpty) ...[
                  QuickActionsBar(actions: prefs.quickActions),
                  const SizedBox(height: AriaTokens.s2),
                ],
                if (!simple) _CategoryChips(selected: filter),
                if (prefs.interactiveTips &&
                    !prefs.dismissedTips.contains('swipe') &&
                    prefs.swipeEnabled &&
                    sections.isNotEmpty)
                  TipCard(
                    id: 'swipe',
                    text: tr(
                      'Swipe right on a reminder to mark it done, left to snooze. Long-press to edit.',
                    ),
                  ),
                const SizedBox(height: AriaTokens.s2),
                if (sections.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AriaTokens.s5),
                    child: EmptyState(
                      emoji: filter?.emoji ?? '🌤️',
                      title: filter == null
                          ? tr('Nothing planned yet')
                          : tr('No {0} reminders', [
                              filter.label.toLowerCase(),
                            ]),
                      message: tr('Tap the mic and tell me anything.'),
                      action: FilledButton.tonalIcon(
                        onPressed: () => context.push('/reminder/new'),
                        icon: const Icon(Icons.edit_rounded),
                        label: Text(tr('Type a reminder')),
                      ),
                    ),
                  )
                else
                  for (final MapEntry(key: section, value: entries)
                      in sections.entries) ...[
                    _SectionHeader(section: section, count: entries.length),
                    for (final e in entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AriaTokens.s2),
                        child: ReminderTile(entry: e, section: section),
                      ),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section, required this.count});
  final TodaySection section;
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = section == TodaySection.overdue ? p.danger : p.muted;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AriaTokens.s1,
          AriaTokens.s4,
          0,
          AriaTokens.s2,
        ),
        child: Text(
          '${section.label} · $count',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

class _CategoryChips extends ConsumerWidget {
  const _CategoryChips({required this.selected});
  final ReminderCategory? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(todayFilterProvider.notifier);
    return SizedBox(
      height: AriaTokens.minTap,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AriaTokens.s2),
            child: ChoiceChip(
              label: Text(tr('All')),
              selected: selected == null,
              onSelected: (_) => ctl.set(null),
            ),
          ),
          for (final c in ReminderCategory.values)
            Padding(
              padding: const EdgeInsets.only(right: AriaTokens.s2),
              child: ChoiceChip(
                label: Text('${c.emoji} ${c.label}'),
                selected: selected == c,
                onSelected: (on) => ctl.set(on ? c : null),
              ),
            ),
        ],
      ),
    );
  }
}

/// Text briefing for now; Phase 3 adds the spoken ▶ version.
class _BriefingCard extends ConsumerWidget {
  const _BriefingCard({required this.sections});
  final Map<TodaySection, List<TodayEntry>> sections;

  /// Speaks today's briefing now (same text as the morning briefing).
  Future<void> _play(WidgetRef ref) async {
    final settings = ref.read(voiceSettingsProvider);
    final zone = ref.read(deviceTimeZoneProvider);
    final now = ref.read(clockProvider)().toUtc();
    final uid = ref.read(currentUserIdProvider) ?? '';
    final active =
        await ref.read(reminderRepositoryProvider)?.activeMine() ?? [];
    final agenda = agendaFor(active, userId: uid, day: now, zone: zone);
    final phrases = Phrases(settings);
    final w = toWall(now, zone);
    final part = w.hour < 12
        ? 'morning'
        : (w.hour < 17 ? 'afternoon' : 'evening');
    final text =
        '${phrases.greeting(part)} ${phrases.daySummary(dayWord: 'today', items: [
          for (final e in agenda.entries) e.allDay ? e.title : tr('{0} at {1}', [e.title, DateFormat.jm().format(toWall(e.at, zone))]),
        ], bills: agenda.bills, birthdays: agenda.birthdays)}';
    await ref.read(speakerProvider).speak(text, VoiceProfile.of(settings));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int n(TodaySection s) => sections[s]?.length ?? 0;
    final pending =
        n(TodaySection.overdue) +
        n(TodaySection.now) +
        n(TodaySection.later) +
        n(TodaySection.anytime);
    final done = n(TodaySection.done);
    final bills = [
      for (final s in [
        TodaySection.overdue,
        TodaySection.now,
        TodaySection.later,
      ])
        ...?sections[s],
    ].where((e) => e.reminder.category == ReminderCategory.bills).length;
    final text = Theme.of(context).textTheme;
    final line = pending == 0 && done == 0
        ? tr('A clear day so far.')
        : [
            tr('{0} to do', [pending]),
            if (done > 0) tr('{0} done', [done]),
            if (bills > 0)
              tr('{0} bill{1} due', [bills, bills == 1 ? '' : 's']),
          ].join(' · ');
    return AriaCard(
      child: Row(
        children: [
          const ExcludeSemantics(
            child: Text('☀️', style: TextStyle(fontSize: 28)),
          ),
          const SizedBox(width: AriaTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Today at a glance'), style: text.titleMedium),
                Text(
                  line,
                  style: text.bodyMedium?.copyWith(
                    color: context.palette.muted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: tr('Play briefing'),
            onPressed: () => unawaited(_play(ref)),
            icon: const Icon(Icons.play_circle_fill_rounded),
            iconSize: 36,
            color: context.palette.primary,
          ),
        ],
      ),
    );
  }
}
