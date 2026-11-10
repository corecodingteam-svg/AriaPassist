import 'dart:async';

import 'package:aria/core/connectivity.dart';
import 'package:aria/data/providers.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/lists/data/lists_repository.dart';
import 'package:aria/features/lists/domain/lists.dart';
import 'package:aria/features/notes/data/notes_repository.dart';
import 'package:aria/features/people/data/people_repository.dart';
import 'package:aria/features/people/domain/person.dart';
import 'package:aria/features/progress/domain/stats.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/routines/data/routines_repository.dart';
import 'package:aria/features/routines/domain/routine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ------------------------------------------------------------ repositories

final listsRepositoryProvider = Provider<ListsRepository?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  return ListsRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(localStoreProvider),
    userId: uid,
  );
});

/// Semantic note search through the Edge Function (null in tests).
final remoteNoteSearchProvider = Provider<RemoteNoteSearch?>((ref) {
  try {
    final client = ref.watch(supabaseClientProvider);
    return (q) async {
      if (!(ref.read(isOnlineProvider).value ?? true)) return null;
      return await supabaseNoteSearch(client)(q);
    };
  } on Object {
    return null;
  }
});

final notesRepositoryProvider = Provider<NotesRepository?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  return NotesRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(localStoreProvider),
    userId: uid,
    remote: ref.watch(remoteNoteSearchProvider),
  );
});

final peopleRepositoryProvider = Provider<PeopleRepository?>((ref) {
  final reminders = ref.watch(reminderRepositoryProvider);
  if (reminders == null) return null;
  return PeopleRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(localStoreProvider),
    reminders,
    userId: reminders.userId,
    zone: ref.watch(deviceTimeZoneProvider),
  );
});

final routinesRepositoryProvider = Provider<RoutinesRepository?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  return RoutinesRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(localStoreProvider),
    userId: uid,
  );
});

// ----------------------------------------------------------------- streams

final listsProvider = StreamProvider<List<AriaList>>(
  (ref) =>
      ref
          .watch(listsRepositoryProvider)
          ?.watchLists(circleId: ref.watch(activeCircleProvider)?.id) ??
      const Stream.empty(),
);

// ignore: specify_nonobvious_property_types -- family type is verbose
final listItemsProvider = StreamProvider.family<List<ListEntry>, String>(
  (ref, id) =>
      ref.watch(listsRepositoryProvider)?.watchItems(id) ??
      const Stream.empty(),
);

final notesProvider = StreamProvider<List<QuickNote>>(
  (ref) =>
      ref
          .watch(notesRepositoryProvider)
          ?.watchNotes(circleId: ref.watch(activeCircleProvider)?.id) ??
      const Stream.empty(),
);

final peopleProvider = StreamProvider<List<Person>>(
  (ref) =>
      ref
          .watch(peopleRepositoryProvider)
          ?.watchPeople(circleId: ref.watch(activeCircleProvider)?.id) ??
      const Stream.empty(),
);

final routinesProvider = StreamProvider<List<Routine>>(
  (ref) =>
      ref.watch(routinesRepositoryProvider)?.watchRoutines() ??
      const Stream.empty(),
);

final eventsProvider = StreamProvider<List<ReminderEvent>>(
  (ref) =>
      ref.watch(reminderRepositoryProvider)?.watchEvents() ??
      const Stream.empty(),
);

final weeklyReportProvider = Provider<WeeklyReport?>((ref) {
  final events = ref.watch(eventsProvider).value;
  final reminders = ref.watch(myRemindersProvider).value;
  if (events == null || reminders == null) return null;
  return WeeklyReport.build(
    events: events,
    reminders: reminders,
    now: (ref.watch(nowProvider).value ?? ref.read(clockProvider)()).toUtc(),
    zone: ref.watch(deviceTimeZoneProvider),
  );
});

/// Bills this month from bill reminders: paid vs upcoming, with totals.
@immutable
class BillsSummary {
  const BillsSummary({required this.paid, required this.upcoming});
  final List<Reminder> paid;
  final List<Reminder> upcoming;
  double get paidTotal => paid.fold(0, (s, r) => s + (r.amount ?? 0));
  double get upcomingTotal => upcoming.fold(0, (s, r) => s + (r.amount ?? 0));
}

final billsSummaryProvider = Provider<BillsSummary>((ref) {
  final all = ref.watch(myRemindersProvider).value ?? const <Reminder>[];
  final now = (ref.watch(nowProvider).value ?? ref.read(clockProvider)())
      .toLocal();
  bool thisMonth(DateTime? d) {
    final l = d?.toLocal();
    return l != null && l.year == now.year && l.month == now.month;
  }

  final bills = all.where(
    (r) => r.category == ReminderCategory.bills && r.deletedAt == null,
  );
  return BillsSummary(
    paid: [
      for (final r in bills)
        if (thisMonth(r.lastDoneAt)) r,
    ],
    upcoming: [
      for (final r in bills)
        if (r.isActive && thisMonth(r.dueAt)) r,
    ],
  );
});

// ---------------------------------------------------------------- realtime

/// Shared lists/notes/reminders update live within a Circle: any change the
/// server tells us about (RLS-filtered) triggers a pull.
final realtimeSyncProvider = Provider<void>((ref) {
  final engine = ref.watch(syncEngineProvider);
  if (engine == null) return;
  final SupabaseClient client;
  try {
    client = ref.watch(supabaseClientProvider);
  } on Object {
    return;
  }
  var channel = client.channel('aria-sync');
  for (final table in ['lists', 'list_items', 'notes', 'reminders', 'people']) {
    channel = channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      callback: (_) => engine.requestSync(),
    );
  }
  channel.subscribe();
  ref.onDispose(() => unawaited(client.removeChannel(channel)));
});
