import 'dart:async';

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/prompts.dart';
import 'package:aria/core/widgets/state_views.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/lists/domain/lists.dart';
import 'package:aria/features/lists/organize_providers.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// One list: add, check off, quantity, reorder (drag), swipe to delete.
class ListDetailScreen extends ConsumerStatefulWidget {
  const ListDetailScreen({required this.listId, super.key});
  final String listId;

  @override
  ConsumerState<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends ConsumerState<ListDetailScreen> {
  final _add = TextEditingController();

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  Future<void> _addItems() async {
    // "milk, eggs and bread" → three items.
    final parts = _add.text
        .split(RegExp(',| and | aur '))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return;
    _add.clear();
    await ref.read(listsRepositoryProvider)?.addItems(widget.listId, parts);
  }

  @override
  Widget build(BuildContext context) {
    final list = ref
        .watch(listsProvider)
        .value
        ?.where((l) => l.id == widget.listId)
        .firstOrNull;
    final items = ref.watch(listItemsProvider(widget.listId));
    final repo = ref.read(listsRepositoryProvider);
    final p = context.palette;
    final circle = ref.watch(activeCircleProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(list == null ? 'List' : '${list.type.emoji} ${list.name}'),
        actions: [
          PopupMenuButton<String>(
            tooltip: tr('List options'),
            onSelected: (v) async {
              switch (v) {
                case 'clear':
                  await repo?.clearDone(widget.listId);
                case 'rename':
                  final name = await _ask(
                    context,
                    tr('Rename list'),
                    list?.name ?? '',
                  );
                  if (name != null && name.isNotEmpty) {
                    await repo?.renameList(widget.listId, name);
                  }
                case 'share':
                  await repo?.setShared(
                    widget.listId,
                    shared: !(list?.shared ?? false),
                  );
                case 'delete':
                  await repo?.deleteList(widget.listId);
                  if (context.mounted) context.pop();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'clear',
                child: Text(tr('Clear checked items')),
              ),
              PopupMenuItem(value: 'rename', child: Text(tr('Rename'))),
              if (circle != null && !circle.isPersonal && list != null)
                PopupMenuItem(
                  value: 'share',
                  child: Text(
                    list.shared
                        ? tr('Make private')
                        : tr('Share with {0}', [circle.name]),
                  ),
                ),
              PopupMenuItem(value: 'delete', child: Text(tr('Delete list'))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AriaTokens.s4,
              AriaTokens.s2,
              AriaTokens.s4,
              AriaTokens.s2,
            ),
            child: TextField(
              key: const Key('add-item'),
              controller: _add,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: tr('Add items (e.g. milk, eggs and bread)'),
                suffixIcon: IconButton(
                  tooltip: tr('Add'),
                  onPressed: _addItems,
                  icon: const Icon(Icons.add_rounded),
                ),
              ),
              onSubmitted: (_) => _addItems(),
            ),
          ),
          Expanded(
            child: items.when(
              loading: () => const LoadingState(),
              error: (e, _) => ErrorState(message: '$e'),
              data: (all) {
                if (all.isEmpty) {
                  return EmptyState(
                    emoji: '🧺',
                    title: tr('Nothing here yet'),
                    message: tr(
                      'Add items above, or say “add milk to this list”.',
                    ),
                  );
                }
                final open = all.where((i) => !i.done).toList();
                final done = all.where((i) => i.done).toList();
                return CustomScrollView(
                  slivers: [
                    SliverReorderableList(
                      itemCount: open.length,
                      // onReorderItem already adjusts `to` for the removed item.
                      onReorderItem: (from, to) {
                        final ids = open.map((i) => i.id).toList();
                        final moved = ids.removeAt(from);
                        ids.insert(to, moved);
                        unawaited(repo?.reorder(ids));
                      },
                      itemBuilder: (_, i) => _ItemTile(
                        key: ValueKey(open[i].id),
                        item: open[i],
                        index: i,
                      ),
                    ),
                    if (done.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AriaTokens.s4,
                            AriaTokens.s4,
                            AriaTokens.s4,
                            AriaTokens.s1,
                          ),
                          child: Text(
                            tr('Checked · {0}', [done.length]),
                            style: TextStyle(
                              color: p.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      SliverList.list(
                        children: [
                          for (final d in done)
                            _ItemTile(key: ValueKey(d.id), item: d),
                        ],
                      ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 120)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<String?> _ask(BuildContext context, String title, String initial) =>
    promptText(context, title: title, initial: initial);

class _ItemTile extends ConsumerWidget {
  const _ItemTile({required this.item, this.index, super.key});
  final ListEntry item;

  /// Set for open items (drag handle).
  final int? index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(listsRepositoryProvider);
    final p = context.palette;
    final tile = Dismissible(
      key: ValueKey('dismiss-${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: p.danger,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AriaTokens.s5),
        child: Icon(Icons.delete_outline_rounded, color: p.onDanger),
      ),
      onDismissed: (_) async {
        await repo?.deleteItem(item.id);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(tr('Removed {0}', [item.text])),
              action: SnackBarAction(
                label: tr('Undo'),
                onPressed: () => unawaited(repo?.restoreItem(item.id)),
              ),
            ),
          );
      },
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          leading: Checkbox(
            value: item.done,
            onChanged: (_) {
              unawaited(ref.read(hapticsProvider).selection());
              unawaited(repo?.toggle(item.id));
            },
          ),
          title: Text(
            item.text,
            style: TextStyle(
              decoration: item.done ? TextDecoration.lineThrough : null,
              color: item.done ? p.muted : null,
            ),
          ),
          subtitle: item.addedByName == null
              ? null
              : Text(tr('added by {0}', [item.addedByName])),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!item.done) _Qty(item: item),
              if (index != null)
                ReorderableDragStartListener(
                  index: index!,
                  child: Padding(
                    padding: const EdgeInsets.all(AriaTokens.s2),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      color: p.muted,
                      semanticLabel: tr('Reorder'),
                    ),
                  ),
                ),
            ],
          ),
          onTap: () => unawaited(repo?.toggle(item.id)),
        ),
      ),
    );
    return tile;
  }
}

class _Qty extends ConsumerWidget {
  const _Qty({required this.item});
  final ListEntry item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(listsRepositoryProvider);
    final q = item.qty ?? 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: tr('Less {0}', [item.text]),
          visualDensity: VisualDensity.compact,
          onPressed: q <= 1
              ? null
              : () => repo?.setQty(item.id, q - 1 == 1 ? null : q - 1),
          icon: const Icon(Icons.remove_rounded, size: 18),
        ),
        Text(
          q == q.roundToDouble() ? '${q.toInt()}' : '$q',
          semanticsLabel: tr('Quantity {0}', [q.toInt()]),
        ),
        IconButton(
          tooltip: tr('More {0}', [item.text]),
          visualDensity: VisualDensity.compact,
          onPressed: () => repo?.setQty(item.id, q + 1),
          icon: const Icon(Icons.add_rounded, size: 18),
        ),
      ],
    );
  }
}
