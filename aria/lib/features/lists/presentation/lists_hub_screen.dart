import 'dart:async';

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/features/lists/domain/lists.dart';
import 'package:aria/features/lists/organize_providers.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/alert_plan.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The Lists tab: lists, this month's bills, notes, people and routines.
class ListsHubScreen extends ConsumerWidget {
  const ListsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(listsProvider).value ?? const <AriaList>[];
    final notes = ref.watch(notesProvider).value ?? const [];
    final people = ref.watch(peopleProvider).value ?? const [];
    final routines = ref.watch(routinesProvider).value ?? const [];
    final bills = ref.watch(billsSummaryProvider);
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final dueCalls = people.where((p) => p.dueForCall(now)).length;
    final text = Theme.of(context).textTheme;
    final p = context.palette;

    Widget header(String title, {VoidCallback? onAdd, String? addLabel}) =>
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AriaTokens.s1,
            AriaTokens.s5,
            0,
            AriaTokens.s2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: text.titleMedium),
                ),
              ),
              if (onAdd != null)
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(addLabel ?? tr('New')),
                ),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Lists & Notes')),
        actions: [ProfileAvatarButton(onPressed: () => context.push('/me'))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AriaTokens.s4,
          0,
          AriaTokens.s4,
          120,
        ),
        children: [
          header(
            tr('Lists'),
            onAdd: () => unawaited(showNewListSheet(context, ref)),
            addLabel: tr('New list'),
          ),
          if (lists.isEmpty)
            AriaCard(
              onTap: () => unawaited(showNewListSheet(context, ref)),
              child: Text(
                tr(
                  '🛒  Say “add milk to grocery list”, or tap to create a list.',
                ),
              ),
            ),
          for (final l in lists)
            Padding(
              padding: const EdgeInsets.only(bottom: AriaTokens.s2),
              child: AriaCard(
                onTap: () => context.push('/lists/${l.id}'),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        l.type.emoji,
                        style: const TextStyle(fontSize: 26),
                      ),
                    ),
                    const SizedBox(width: AriaTokens.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.name, style: text.titleMedium),
                          Text(
                            l.openCount == 0
                                ? (l.doneCount == 0
                                      ? tr('Empty')
                                      : tr('All done ✓'))
                                : l.preview.join(', ') +
                                      (l.openCount > l.preview.length
                                          ? ' +${l.openCount - l.preview.length}'
                                          : ''),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.muted),
                          ),
                        ],
                      ),
                    ),
                    if (l.shared)
                      Icon(
                        Icons.group_rounded,
                        size: 18,
                        color: p.muted,
                        semanticLabel: tr('Shared'),
                      ),
                    const SizedBox(width: AriaTokens.s2),
                    Text(
                      '${l.openCount}',
                      style: text.titleMedium?.copyWith(color: p.primary),
                    ),
                  ],
                ),
              ),
            ),
          header(tr('Bills this month')),
          AriaCard(
            onTap: () => context.push('/bills'),
            child: Row(
              children: [
                const ExcludeSemantics(
                  child: Text('💰', style: TextStyle(fontSize: 26)),
                ),
                const SizedBox(width: AriaTokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('{0} upcoming', [formatRupees(bills.upcomingTotal)]),
                        style: text.titleMedium,
                      ),
                      Text(
                        tr('{0} paid ({1}) · {2} to pay', [
                          bills.paid.length,
                          formatRupees(bills.paidTotal),
                          bills.upcoming.length,
                        ]),
                        style: TextStyle(color: p.muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
          header(
            tr('Notes'),
            onAdd: () => context.push('/notes'),
            addLabel: tr('All notes'),
          ),
          AriaCard(
            onTap: () => context.push('/notes'),
            child: notes.isEmpty
                ? Text(
                    tr(
                      '📝  Say “note that the wifi password is …” — then just ask for it later.',
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final n in notes.take(3))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '• ${n.text}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
          ),
          header(
            tr('People'),
            onAdd: () => context.push('/people/new'),
            addLabel: tr('Add'),
          ),
          AriaCard(
            onTap: () => context.push('/people'),
            child: Row(
              children: [
                const ExcludeSemantics(
                  child: Text('👪', style: TextStyle(fontSize: 26)),
                ),
                const SizedBox(width: AriaTokens.s3),
                Expanded(
                  child: Text(
                    people.isEmpty
                        ? tr('Birthdays, anniversaries and “call Dad” nudges')
                        : tr('{0} people{1}', [
                            people.length,
                            dueCalls > 0 ? ' · $dueCalls to call' : '',
                          ]),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
          header(
            tr('Routines'),
            onAdd: () => context.push('/routines'),
            addLabel: tr('Manage'),
          ),
          if (routines.isEmpty)
            AriaCard(
              onTap: () => context.push('/routines'),
              child: Text(
                tr(
                  '☀️  Create a routine like “Morning mode” — Aria guides you step by step.',
                ),
              ),
            ),
          for (final r in routines)
            Padding(
              padding: const EdgeInsets.only(bottom: AriaTokens.s2),
              child: AriaCard(
                onTap: () => context.push('/routine/${r.id}'),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        r.emoji,
                        style: const TextStyle(fontSize: 26),
                      ),
                    ),
                    const SizedBox(width: AriaTokens.s3),
                    Expanded(child: Text(r.name, style: text.titleMedium)),
                    Text(
                      tr('{0} steps', [r.steps.length]),
                      style: TextStyle(color: p.muted),
                    ),
                    const SizedBox(width: AriaTokens.s2),
                    Icon(
                      Icons.play_circle_fill_rounded,
                      color: p.primary,
                      semanticLabel: tr('Start'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Create a list (name + type), then open it.
Future<void> showNewListSheet(BuildContext context, WidgetRef ref) async {
  final max = ref.read(entitlementProvider).plan.maxLists;
  if (max != null) {
    final n = await ref.read(listsRepositoryProvider)?.count() ?? 0;
    if (n >= max) {
      if (context.mounted) requireFeature(context, ref, Feature.unlimitedLists);
      return;
    }
  }
  if (!context.mounted) return;
  final id = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _NewListSheet(),
  );
  if (id != null && context.mounted) unawaited(context.push('/lists/$id'));
}

class _NewListSheet extends ConsumerStatefulWidget {
  const _NewListSheet();

  @override
  ConsumerState<_NewListSheet> createState() => _NewListSheetState();
}

class _NewListSheetState extends ConsumerState<_NewListSheet> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    final circle = await ref.read(activeCircleIdProvider.future);
    final repo = ref.read(listsRepositoryProvider);
    if (circle == null || repo == null) return;
    final id = await repo.createList(n, circleId: circle);
    if (mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      AriaTokens.s5,
      0,
      AriaTokens.s5,
      AriaTokens.s5 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('New list'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AriaTokens.s3),
        Wrap(
          spacing: AriaTokens.s2,
          children: [
            for (final t in [ListType.grocery, ListType.packing, ListType.work])
              ActionChip(
                label: Text('${t.emoji} ${t.label}'),
                onPressed: () => _name.text = t.label,
              ),
          ],
        ),
        const SizedBox(height: AriaTokens.s3),
        TextField(
          key: const Key('new-list-name'),
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tr('List name')),
          onSubmitted: (_) => _create(),
        ),
        const SizedBox(height: AriaTokens.s4),
        FilledButton(
          key: const Key('create-list'),
          onPressed: _create,
          child: Text(tr('Create')),
        ),
      ],
    ),
  );
}
