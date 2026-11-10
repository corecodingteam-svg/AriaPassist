import 'dart:async';

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/core/widgets/state_views.dart';
import 'package:aria/features/lists/organize_providers.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/progress/presentation/celebration.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/routines/domain/routine.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:aria/features/voice/application/voice_engine.dart';
import 'package:aria/features/voice/application/voice_providers.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _dayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _fmt(BuildContext c, int m) =>
    TimeOfDay(hour: m ~/ 60, minute: m % 60).format(c);

/// Manage routines + one-tap templates.
class RoutinesScreen extends ConsumerWidget {
  const RoutinesScreen({super.key});

  Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    (String, String, List<RoutineStep>)? t,
  ) async {
    if (!requireFeature(context, ref, Feature.routines)) return;
    final repo = ref.read(routinesRepositoryProvider);
    final circle = await ref.read(activeCircleIdProvider.future);
    if (repo == null || circle == null) return;
    final r = repo.create(
      t?.$1 ?? tr('My routine'),
      circleId: circle,
      emoji: t?.$2 ?? '✨',
      steps: t?.$3 ?? const [],
    );
    await repo.save(
      t?.$1 == 'Morning mode' ? r.copyWith(atMinute: () => 7 * 60) : r,
    );
    if (context.mounted) unawaited(context.push('/routines/${r.id}/edit'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(routinesProvider);
    final today = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: Text(tr('Routines'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-routine',
        onPressed: () => _create(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('Routine')),
      ),
      body: routines.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(message: '$e'),
        data: (all) => ListView(
          padding: const EdgeInsets.fromLTRB(
            AriaTokens.s4,
            AriaTokens.s2,
            AriaTokens.s4,
            120,
          ),
          children: [
            for (final r in all)
              Padding(
                padding: const EdgeInsets.only(bottom: AriaTokens.s2),
                child: AriaCard(
                  onTap: () => context.push('/routines/${r.id}/edit'),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: Text(
                          r.emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                      const SizedBox(width: AriaTokens.s3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              [
                                tr('{0} steps', [r.steps.length]),
                                if (r.atMinute != null)
                                  tr('at {0}', [_fmt(context, r.atMinute!)]),
                                if (r.streak(today) > 1)
                                  tr('🔥 {0} days', [r.streak(today)]),
                              ].join(' · '),
                              style: TextStyle(color: context.palette.muted),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filled(
                        tooltip: tr('Start {0}', [r.name]),
                        onPressed: () {
                          if (requireFeature(context, ref, Feature.routines)) {
                            unawaited(context.push('/routine/${r.id}'));
                          }
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AriaTokens.s4),
            Text(
              tr('Start from a template'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AriaTokens.s2),
            Wrap(
              spacing: AriaTokens.s2,
              runSpacing: AriaTokens.s2,
              children: [
                for (final t in Routine.templates)
                  if (!all.any((r) => r.name == t.$1))
                    ActionChip(
                      key: Key('template-${t.$1}'),
                      avatar: Text(t.$2),
                      label: Text(t.$1),
                      onPressed: () => _create(context, ref, t),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RoutineEditorScreen extends ConsumerStatefulWidget {
  const RoutineEditorScreen({required this.routineId, super.key});
  final String routineId;

  @override
  ConsumerState<RoutineEditorScreen> createState() =>
      _RoutineEditorScreenState();
}

class _RoutineEditorScreenState extends ConsumerState<RoutineEditorScreen> {
  Routine? _r;
  final _name = TextEditingController();
  final _step = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      final r = await ref
          .read(routinesRepositoryProvider)
          ?.get(widget.routineId);
      if (!mounted) return;
      setState(() {
        _r = r;
        _name.text = r?.name ?? '';
      });
    }());
  }

  @override
  void dispose() {
    _name.dispose();
    _step.dispose();
    super.dispose();
  }

  void _set(Routine r) => setState(() => _r = r);

  Future<void> _save() async {
    final r = _r;
    if (r == null) return;
    await ref
        .read(routinesRepositoryProvider)
        ?.save(
          r.copyWith(
            name: _name.text.trim().isEmpty ? r.name : _name.text.trim(),
          ),
        );
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (r == null) return const Scaffold(body: LoadingState());
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('{0} Edit routine', [r.emoji])),
        actions: [
          IconButton(
            tooltip: tr('Delete routine'),
            onPressed: () async {
              await ref.read(routinesRepositoryProvider)?.delete(r.id);
              if (context.mounted) context.pop();
            },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          TextButton(
            key: const Key('save-routine'),
            onPressed: _save,
            child: Text(tr('Save')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AriaTokens.s4),
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: tr('Name')),
          ),
          const SizedBox(height: AriaTokens.s4),
          Text(tr('Steps'), style: Theme.of(context).textTheme.titleMedium),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorderItem: (from, to) {
              final steps = [...r.steps];
              final s = steps.removeAt(from);
              steps.insert(to, s);
              _set(r.copyWith(steps: steps));
            },
            children: [
              for (final (i, s) in r.steps.indexed)
                ListTile(
                  key: ValueKey('$i-${s.title}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Text(s.emoji, style: const TextStyle(fontSize: 22)),
                  title: Text(s.title),
                  trailing: IconButton(
                    tooltip: tr('Remove step'),
                    onPressed: () =>
                        _set(r.copyWith(steps: [...r.steps]..removeAt(i))),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
            ],
          ),
          TextField(
            key: const Key('add-step'),
            controller: _step,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: tr('Add a step'),
              suffixIcon: IconButton(
                tooltip: tr('Add step'),
                icon: const Icon(Icons.add_rounded),
                onPressed: () {
                  if (_step.text.trim().isEmpty) return;
                  _set(
                    r.copyWith(
                      steps: [...r.steps, RoutineStep(_step.text.trim())],
                    ),
                  );
                  _step.clear();
                },
              ),
            ),
            onSubmitted: (v) {
              if (v.trim().isEmpty) return;
              _set(r.copyWith(steps: [...r.steps, RoutineStep(v.trim())]));
              _step.clear();
            },
          ),
          const SizedBox(height: AriaTokens.s5),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Start at a set time')),
            subtitle: Text(
              r.atMinute == null
                  ? tr('Start by voice (“start {0}”) or tap', [
                      r.name.toLowerCase(),
                    ])
                  : tr('At {0}', [_fmt(context, r.atMinute!)]),
            ),
            value: r.atMinute != null,
            onChanged: (v) =>
                _set(r.copyWith(atMinute: () => v ? 7 * 60 : null)),
          ),
          if (r.atMinute != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                      hour: r.atMinute! ~/ 60,
                      minute: r.atMinute! % 60,
                    ),
                  );
                  if (t != null) {
                    _set(r.copyWith(atMinute: () => t.hour * 60 + t.minute));
                  }
                },
                child: Text(tr('Change time')),
              ),
            ),
            Wrap(
              spacing: AriaTokens.s1,
              children: [
                for (var d = 1; d <= 7; d++)
                  Semantics(
                    label: _dayNames[d - 1],
                    child: FilterChip(
                      showCheckmark: false,
                      label: Text(_dayLetters[d - 1]),
                      selected: r.days.contains(d),
                      onSelected: (on) => _set(
                        r.copyWith(
                          days: on ? {...r.days, d} : ({...r.days}..remove(d)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Step-by-step runner with spoken guidance; each step tickable.
class RoutineRunnerScreen extends ConsumerStatefulWidget {
  const RoutineRunnerScreen({required this.routineId, super.key});
  final String routineId;

  @override
  ConsumerState<RoutineRunnerScreen> createState() =>
      _RoutineRunnerScreenState();
}

class _RoutineRunnerScreenState extends ConsumerState<RoutineRunnerScreen> {
  Routine? _r;
  final _done = <int>{};
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      final r = await ref
          .read(routinesRepositoryProvider)
          ?.get(widget.routineId);
      if (!mounted) return;
      setState(() => _r = r);
      if (r != null && r.steps.isNotEmpty) {
        await _say(
          tr("Let's start {0}. First: {1}.", [r.name, r.steps.first.title]),
        );
      }
    }());
  }

  Future<void> _say(String text) async {
    final s = ref.read(voiceSettingsProvider);
    try {
      await ref.read(speakerProvider).speak(text, VoiceProfile.of(s));
    } on Object {
      // Guidance is a nicety; the screen works silently too.
    }
  }

  Future<void> _tick(int i) async {
    final r = _r!;
    unawaited(ref.read(hapticsProvider).selection());
    setState(() => _done.add(i));
    final next = [
      for (var j = 0; j < r.steps.length; j++)
        if (!_done.contains(j)) j,
    ].firstOrNull;
    if (next != null) {
      await _say(tr('Next: {0}.', [r.steps[next].title]));
      return;
    }
    final zone = ref.read(deviceTimeZoneProvider);
    final updated = await ref
        .read(routinesRepositoryProvider)
        ?.markRun(r.id, toWall(ref.read(clockProvider)().toUtc(), zone));
    if (!mounted) return;
    setState(() => _finished = true);
    final streak = updated?.streak(DateTime.now()) ?? 1;
    if (ref.read(appPrefsProvider).celebrations) showConfetti(context);
    await _say(
      streak > 1
          ? tr('All done! That’s {0} days in a row.', [streak])
          : tr('All done! Great start to the day.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (r == null) return const Scaffold(body: LoadingState());
    final text = Theme.of(context).textTheme;
    final current = [
      for (var j = 0; j < r.steps.length; j++)
        if (!_done.contains(j)) j,
    ].firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text('${r.emoji} ${r.name}')),
      body: ListView(
        padding: const EdgeInsets.all(AriaTokens.s4),
        children: [
          LinearProgressIndicator(
            value: r.steps.isEmpty ? 1 : _done.length / r.steps.length,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            semanticsLabel: tr('{0} of {1} steps done', [
              _done.length,
              r.steps.length,
            ]),
          ),
          const SizedBox(height: AriaTokens.s4),
          if (_finished)
            AriaCard(
              child: Column(
                children: [
                  const Text('🎉', style: TextStyle(fontSize: 48)),
                  Text(
                    tr('All done!'),
                    key: const Key('routine-done'),
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: AriaTokens.s3),
                  FilledButton(
                    onPressed: () => context.pop(),
                    child: Text(tr('Close')),
                  ),
                ],
              ),
            ),
          for (final (i, s) in r.steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: AriaTokens.s2),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AriaTokens.radiusLg),
                  side: i == current
                      ? BorderSide(color: context.palette.primary, width: 2)
                      : BorderSide.none,
                ),
                child: CheckboxListTile(
                  value: _done.contains(i),
                  onChanged: _done.contains(i) ? null : (_) => _tick(i),
                  secondary: Text(
                    s.emoji,
                    style: const TextStyle(fontSize: 26),
                  ),
                  title: Text(
                    s.title,
                    style: text.titleMedium?.copyWith(
                      decoration: _done.contains(i)
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          if (r.steps.isEmpty)
            EmptyState(
              emoji: '✨',
              title: tr('No steps yet'),
              message: tr('Add steps in the routine’s settings.'),
            ),
        ],
      ),
    );
  }
}
