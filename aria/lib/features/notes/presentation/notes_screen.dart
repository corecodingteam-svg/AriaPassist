import 'dart:async';

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/core/widgets/prompts.dart';
import 'package:aria/core/widgets/state_views.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/lists/organize_providers.dart';
import 'package:aria/features/notes/data/notes_repository.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Quick notes: ask a question to find one; add; edit; "forget" (delete).
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final _ask = TextEditingController();
  Future<List<QuickNote>>? _answers;

  @override
  void dispose() {
    _ask.dispose();
    super.dispose();
  }

  Future<void> _addNote() async {
    final text = await promptText(
      context,
      title: tr('New note'),
      hint: tr('e.g. Wifi password is sunflower42'),
      maxLines: 4,
      fieldKey: const Key('note-text'),
    );
    if (text == null || text.isEmpty) return;
    final circle = await ref.read(activeCircleIdProvider.future);
    if (circle != null) {
      await ref.read(notesRepositoryProvider)?.add(text, circleId: circle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesProvider);
    final repo = ref.read(notesRepositoryProvider);
    final inCircle = !(ref.watch(activeCircleProvider)?.isPersonal ?? true);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Notes'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-note',
        onPressed: _addNote,
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('Note')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AriaTokens.s4,
          AriaTokens.s2,
          AriaTokens.s4,
          120,
        ),
        children: [
          TextField(
            key: const Key('ask-notes'),
            controller: _ask,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: tr('Ask: “what’s the wifi password?”'),
              prefixIcon: const Icon(Icons.search_rounded),
            ),
            onSubmitted: (q) => setState(
              () => _answers = q.trim().isEmpty ? null : repo?.search(q),
            ),
          ),
          if (_answers != null)
            FutureBuilder<List<QuickNote>>(
              future: _answers,
              builder: (_, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(AriaTokens.s4),
                    child: LoadingState(),
                  );
                }
                final hits = snap.data!;
                return Padding(
                  padding: const EdgeInsets.only(top: AriaTokens.s3),
                  child: AriaCard(
                    child: Text(
                      hits.isEmpty
                          ? tr('I couldn’t find a note about that.')
                          : hits.first.text,
                      key: const Key('note-answer'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: AriaTokens.s4),
          ...notes.when(
            loading: () => [const LoadingState()],
            error: (e, _) => [ErrorState(message: '$e')],
            data: (all) => all.isEmpty
                ? [
                    EmptyState(
                      emoji: '📝',
                      title: tr('No notes yet'),
                      message: tr(
                        'Say “note that the wifi password is …” or tap + Note.',
                      ),
                    ),
                  ]
                : [
                    for (final n in all)
                      Dismissible(
                        key: ValueKey(n.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: AriaTokens.s5),
                          color: context.palette.danger,
                          child: Icon(
                            Icons.delete_outline_rounded,
                            color: context.palette.onDanger,
                          ),
                        ),
                        onDismissed: (_) {
                          unawaited(repo?.forget(n.id));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                tr('Forgotten. Deleted from all your devices.'),
                              ),
                            ),
                          );
                        },
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.sticky_note_2_outlined),
                          title: Text(n.text),
                          trailing: inCircle && n.mine
                              ? IconButton(
                                  tooltip: n.shared
                                      ? tr(
                                          'Shared with Circle — tap to make private',
                                        )
                                      : tr('Share with Circle'),
                                  isSelected: n.shared,
                                  onPressed: () =>
                                      repo?.setShared(n.id, shared: !n.shared),
                                  icon: const Icon(Icons.group_outlined),
                                  selectedIcon: const Icon(Icons.group_rounded),
                                )
                              : n.shared
                              ? Icon(
                                  Icons.group_rounded,
                                  semanticLabel: tr('Shared'),
                                )
                              : null,
                        ),
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}
