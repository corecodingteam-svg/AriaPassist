import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/state_views.dart';
import 'package:aria/features/lists/domain/lists.dart';
import 'package:aria/features/lists/organize_providers.dart';
import 'package:aria/features/notes/data/notes_repository.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/today_sections.dart';
import 'package:aria/features/reminders/presentation/reminder_tile.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

typedef _Results = ({
  List<Reminder> reminders,
  List<QuickNote> notes,
  List<ListEntry> items,
});

/// Global search (spec 5.10): reminders, notes and list items.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String _q = '';
  Future<_Results>? _results;

  Future<_Results> _run(String q) async {
    final (reminders, notes, items) = await (
      ref.read(reminderRepositoryProvider)?.search(q) ??
          Future.value(<Reminder>[]),
      ref.read(notesRepositoryProvider)?.localSearch(q) ??
          Future.value(<QuickNote>[]),
      ref.read(listsRepositoryProvider)?.searchItems(q) ??
          Future.value(<ListEntry>[]),
    ).wait;
    return (reminders: reminders, notes: notes, items: items);
  }

  void _search(String q) => setState(() {
    _q = q;
    _results = q.trim().length < 2 ? null : _run(q.trim());
  });

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.muted;
    Widget header(String t) => Padding(
      padding: const EdgeInsets.only(top: AriaTokens.s4, bottom: AriaTokens.s2),
      child: Text(
        t,
        style: TextStyle(color: muted, fontWeight: FontWeight.w800),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: InputDecoration(
            hintText: tr('Search reminders, notes, lists'),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
          onChanged: _search,
        ),
      ),
      body: _results == null
          ? EmptyState(
              emoji: '🔎',
              title: tr('Find anything'),
              message: tr('Type at least two letters.'),
            )
          : FutureBuilder<_Results>(
              future: _results,
              builder: (context, snap) {
                if (!snap.hasData) return const LoadingState();
                final r = snap.data!;
                if (r.reminders.isEmpty && r.notes.isEmpty && r.items.isEmpty) {
                  return EmptyState(
                    emoji: '🤷',
                    title: tr('No matches for “{0}”', [_q]),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AriaTokens.s4,
                    0,
                    AriaTokens.s4,
                    AriaTokens.s6,
                  ),
                  children: [
                    if (r.reminders.isNotEmpty) header(tr('Reminders')),
                    for (final x in r.reminders)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AriaTokens.s2),
                        child: ReminderTile(
                          entry: TodayEntry(x, x.dueAt),
                          section: TodaySection.upcoming,
                          swipeable: false,
                        ),
                      ),
                    if (r.notes.isNotEmpty) header(tr('Notes')),
                    for (final n in r.notes)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.sticky_note_2_outlined),
                        title: Text(n.text),
                        onTap: () => context.push('/notes'),
                      ),
                    if (r.items.isNotEmpty) header(tr('In your lists')),
                    for (final i in r.items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          i.done
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                        ),
                        title: Text(i.text),
                        onTap: () => context.push('/lists/${i.listId}'),
                      ),
                  ],
                );
              },
            ),
    );
  }
}
