import 'package:aria/data/local/tables.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Tables mirrored from Supabase, in dependency order (parents first).
const kSyncedTables = <String>[
  'users',
  'circles',
  'memberships',
  'reminders',
  'reminder_events',
  'lists',
  'list_items',
  'notes',
  'routines',
  'people',
];

/// Tables the client may write to. circles/memberships are changed through
/// server functions (invites etc., Phase 6), so they're pull-only.
const kPushableTables = <String>{
  'reminders',
  'reminder_events',
  'lists',
  'list_items',
  'notes',
  'routines',
  'people',
};

@DriftDatabase(
  tables: [
    Circles,
    Memberships,
    Reminders,
    ReminderEvents,
    Lists,
    ListItems,
    Notes,
    Routines,
    People,
    Users,
    SyncOutbox,
    SyncCursors,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// `shareAcrossIsolates` lets the notification-action background isolate
  /// use the same database safely while the app is running.
  AppDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'aria',
              native: const DriftNativeOptions(shareAcrossIsolates: true),
            ),
      );

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes();
      await _createEventIndex();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(reminders, reminders.snoozedUntil);
        await m.addColumn(reminders, reminders.lastDoneAt);
        await m.createTable(reminderEvents);
        await _createEventIndex();
        // Re-pull reminders so the new columns fill in from the server.
        await customStatement(
          "DELETE FROM sync_cursors WHERE entity = 'reminders'",
        );
      }
      if (from < 3) {
        await m.createTable(people);
        await m.createTable(users);
      }
      if (from < 4) {
        await m.addColumn(circles, circles.settingsJson);
        await m.addColumn(memberships, memberships.settingsJson);
        // Re-pull so the new columns fill in.
        await customStatement(
          "DELETE FROM sync_cursors WHERE entity IN ('circles', 'memberships')",
        );
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE INDEX idx_reminders_circle_start '
      'ON reminders (circle_id, start_at)',
    );
    await customStatement(
      'CREATE INDEX idx_reminders_assignee_status '
      'ON reminders (assigned_to, status)',
    );
    await customStatement(
      'CREATE INDEX idx_outbox_due ON sync_outbox (next_attempt_at)',
    );
  }

  Future<void> _createEventIndex() => customStatement(
    'CREATE INDEX IF NOT EXISTS idx_events_reminder '
    'ON reminder_events (reminder_id, type)',
  );

  /// Removes every row (sign-out / account deletion): the next person to
  /// sign in on this device must never see the previous user's data.
  Future<void> wipe() => transaction(() async {
    for (final t in allTables) {
      await delete(t).go();
    }
  });

  /// Column names for a mirrored table, used to drop server-only fields.
  Set<String> columnsOf(String table) => allTables
      .firstWhere((t) => t.actualTableName == table)
      .$columns
      .map((c) => c.name)
      .toSet();
}
