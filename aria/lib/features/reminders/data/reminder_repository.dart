import 'dart:convert';

import 'package:aria/data/local/app_database.dart';
import 'package:aria/data/sync/local_store.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/reminder_logic.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

/// A missed occurrence shown on the Missed screen.
@immutable
class MissedItem {
  const MissedItem({required this.event, required this.reminder});
  final ReminderEvent event;
  final Reminder reminder;
}

/// Offline-first reminders: reads from SQLite, writes via [LocalStore]
/// (local + outbox in one transaction). The UI never waits on the network.
class ReminderRepository {
  ReminderRepository(this.db, this.store, {required this.userId});

  final AppDatabase db;
  final LocalStore store;
  final String userId;

  // ------------------------------------------------------------------ reads

  /// Reminders that alert on *this* user's phone.
  Expression<bool> _mine($RemindersTable t) =>
      t.deletedAt.isNull() &
      (t.assignedTo.equals(userId) |
          (t.assignedTo.isNull() & t.createdBy.equals(userId)));

  Stream<List<Reminder>> watchMine() =>
      (db.select(db.reminders)
            ..where(_mine)
            ..orderBy([(t) => OrderingTerm.asc(t.startAt)]))
          .watch()
          .map((rows) => rows.map(fromRow).toList());

  Future<List<Reminder>> activeMine() =>
      (db.select(db.reminders)
            ..where((t) => _mine(t) & t.status.equals('active')))
          .get()
          .then((rows) => rows.map(fromRow).toList());

  Stream<Reminder?> watch(String id) =>
      (db.select(db.reminders)..where((t) => t.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r == null ? null : fromRow(r));

  Future<Reminder?> get(String id) =>
      (db.select(db.reminders)..where((t) => t.id.equals(id)))
          .getSingleOrNull()
          .then((r) => r == null ? null : fromRow(r));

  JoinedSelectStatement<HasResultSet, dynamic> _missedQuery() =>
      db.select(db.reminderEvents).join([
          innerJoin(
            db.reminders,
            db.reminders.id.equalsExp(db.reminderEvents.reminderId),
          ),
        ])
        ..where(
          db.reminderEvents.type.equals('missed') &
              db.reminderEvents.deletedAt.isNull() &
              db.reminderEvents.userId.equals(userId) &
              db.reminders.deletedAt.isNull(),
        )
        ..orderBy([OrderingTerm.desc(db.reminderEvents.occurrenceAt)]);

  List<MissedItem> _toMissed(List<TypedResult> rows) => rows
      .map(
        (row) => MissedItem(
          event: eventFromRow(row.readTable(db.reminderEvents)),
          reminder: fromRow(row.readTable(db.reminders)),
        ),
      )
      .where((m) => !m.event.resolved)
      .toList();

  Stream<List<MissedItem>> watchMissed() =>
      _missedQuery().watch().map(_toMissed);

  /// Reminders I assigned to others in a circle (dependent monitoring).
  Stream<List<Reminder>> watchAssignedByMe(String circleId) =>
      (db.select(db.reminders)
            ..where(
              (t) =>
                  t.circleId.equals(circleId) &
                  t.createdBy.equals(userId) &
                  t.assignedTo.isNotNull() &
                  t.assignedTo.equals(userId).not() &
                  t.deletedAt.isNull(),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.startAt)]))
          .watch()
          .map((rows) => rows.map(fromRow).toList());

  /// One-shot read (use instead of `watch…().first`).
  Future<List<MissedItem>> missed() => _missedQuery().get().then(_toMissed);

  Future<List<ReminderEvent>> events() =>
      (db.select(db.reminderEvents)
            ..where((e) => e.deletedAt.isNull() & e.userId.equals(userId)))
          .get()
          .then((rows) => rows.map(eventFromRow).toList());

  /// All of this user's events (streaks, weekly report).
  Stream<List<ReminderEvent>> watchEvents() =>
      (db.select(db.reminderEvents)
            ..where((e) => e.deletedAt.isNull() & e.userId.equals(userId)))
          .watch()
          .map((rows) => rows.map(eventFromRow).toList());

  Future<List<Reminder>> allMine() => (db.select(
    db.reminders,
  )..where(_mine)).get().then((rows) => rows.map(fromRow).toList());

  Future<List<Reminder>> search(String query) {
    final q = '%${query.trim().toLowerCase()}%';
    return (db.select(db.reminders)
          ..where(
            (t) =>
                _mine(t) & (t.title.lower().like(q) | t.notes.lower().like(q)),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.startAt)])
          ..limit(50))
        .get()
        .then((rows) => rows.map(fromRow).toList());
  }

  // ----------------------------------------------------------------- writes

  Future<void> save(Reminder r) =>
      store.write('reminders', ReminderLogic.normalize(r).toRow());

  Future<void> apply(Transition t) => db.transaction(() async {
    await store.write('reminders', t.reminder.toRow());
    for (final e in t.events) {
      await store.write('reminder_events', e.toRow());
    }
  });

  /// Undo of [t]: restore [before] and retract the events it logged.
  Future<void> undo(Transition t, Reminder before) => db.transaction(() async {
    await store.write('reminders', before.toRow());
    for (final e in t.events) {
      await store.softDelete('reminder_events', e.id);
    }
  });

  Future<void> delete(Reminder r) =>
      store.write('reminders', r.copyWith(deletedAt: DateTime.now).toRow());

  Future<void> restore(Reminder r) =>
      store.write('reminders', r.copyWith(deletedAt: () => null).toRow());

  Future<void> resolveMissed(ReminderEvent e) =>
      store.write('reminder_events', {
        ...e.toRow(),
        'meta_json': {'resolved': true},
      });

  // ---------------------------------------------------------------- mapping

  static Reminder fromRow(ReminderRow r) => Reminder(
    id: r.id,
    circleId: r.circleId,
    createdBy: r.createdBy,
    assignedTo: r.assignedTo,
    title: r.title,
    category: ReminderCategory.parse(r.category),
    priority: Priority.parse(r.priority),
    startAt: r.startAt?.toUtc(),
    allDay: r.allDay,
    rrule: r.rrule,
    timezone: r.timezone,
    notifyMode: NotifyMode.parse(r.notifyMode),
    followUp: FollowUp.fromJson(_json(r.followUpJson)),
    amount: r.amount,
    notes: r.notes,
    contact: _json(r.contactJson),
    location: LocationTrigger.fromJson(_json(r.locationJson)),
    visibility: r.visibility,
    status: ReminderStatus.parse(r.status),
    snoozedUntil: r.snoozedUntil?.toUtc(),
    lastDoneAt: r.lastDoneAt?.toUtc(),
    createdAt: r.createdAt?.toUtc(),
    updatedAt: r.updatedAt?.toUtc(),
    deletedAt: r.deletedAt?.toUtc(),
  );

  static ReminderEvent eventFromRow(ReminderEventRow e) => ReminderEvent(
    id: e.id,
    reminderId: e.reminderId,
    userId: e.userId,
    type:
        ReminderEventType.values.asNameMap()[e.type] ?? ReminderEventType.fired,
    at: e.at.toUtc(),
    occurrenceAt: e.occurrenceAt?.toUtc(),
    resolved: _json(e.metaJson)?['resolved'] == true,
  );

  static Map<String, dynamic>? _json(String? s) {
    if (s == null) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>?;
    } on Object {
      return null;
    }
  }
}
