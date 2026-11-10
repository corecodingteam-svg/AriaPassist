import 'package:drift/drift.dart';

// Local mirror of the Supabase tables the device needs offline.
// Column names (snake_case after Drift's conversion) MUST match Postgres so
// the sync engine can move rows generically. Server-only columns
// (e.g. notes.embedding) are simply not mirrored.

mixin SyncedColumns on Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CircleRow')
class Circles extends Table with SyncedColumns {
  TextColumn get name => text()();
  TextColumn get type => text()(); // personal | family | team
  TextColumn get ownerId => text()();
  TextColumn get planId => text().nullable()();
  TextColumn get settingsJson => text().nullable()();
}

@DataClassName('MembershipRow')
class Memberships extends Table with SyncedColumns {
  TextColumn get circleId => text()();
  TextColumn get userId => text()();
  TextColumn get role => text()(); // owner | admin | member | dependent
  TextColumn get status => text()(); // active | invited | removed
  DateTimeColumn get joinedAt => dateTime().nullable()();
  TextColumn get settingsJson => text().nullable()();
}

@DataClassName('ReminderRow')
class Reminders extends Table with SyncedColumns {
  TextColumn get circleId => text()();
  TextColumn get createdBy => text()();
  TextColumn get assignedTo => text().nullable()();
  TextColumn get title => text()();
  TextColumn get category => text().withDefault(const Constant('personal'))();
  TextColumn get priority => text().withDefault(const Constant('normal'))();
  DateTimeColumn get startAt => dateTime().nullable()();
  BoolColumn get allDay => boolean().withDefault(const Constant(false))();
  TextColumn get rrule => text().nullable()();
  TextColumn get timezone => text().nullable()();
  TextColumn get locationJson => text().nullable()();
  TextColumn get notifyMode => text().nullable()();
  TextColumn get voiceId => text().nullable()();
  TextColumn get followUpJson => text().nullable()();
  RealColumn get amount => real().nullable()();
  IntColumn get quantityLeft => integer().nullable()();
  TextColumn get contactJson => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get visibility => text().withDefault(const Constant('private'))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get snoozedUntil => dateTime().nullable()();
  DateTimeColumn get lastDoneAt => dateTime().nullable()();
}

@DataClassName('ReminderEventRow')
class ReminderEvents extends Table with SyncedColumns {
  TextColumn get reminderId => text()();
  TextColumn get userId => text()();
  TextColumn get type => text()(); // fired | done | snoozed | missed
  DateTimeColumn get at => dateTime()();
  DateTimeColumn get occurrenceAt => dateTime().nullable()();
  TextColumn get metaJson => text().nullable()();
}

@DataClassName('ListRow')
class Lists extends Table with SyncedColumns {
  TextColumn get circleId => text()();
  TextColumn get createdBy => text()();
  TextColumn get name => text()();
  TextColumn get type => text().withDefault(const Constant('custom'))();
  TextColumn get visibility => text().withDefault(const Constant('private'))();
}

@DataClassName('ListItemRow')
class ListItems extends Table with SyncedColumns {
  TextColumn get listId => text()();
  TextColumn get content => text().named('text')();
  RealColumn get qty => real().nullable()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  TextColumn get addedBy => text().nullable()();
  TextColumn get assignedTo => text().nullable()();
  RealColumn get position => real().withDefault(const Constant(0))();
}

@DataClassName('NoteRow')
class Notes extends Table with SyncedColumns {
  TextColumn get circleId => text()();
  TextColumn get createdBy => text()();
  TextColumn get content => text().named('text')();
  TextColumn get visibility => text().withDefault(const Constant('private'))();
}

@DataClassName('RoutineRow')
class Routines extends Table with SyncedColumns {
  TextColumn get circleId => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get triggerJson => text().nullable()();
  TextColumn get stepsJson => text().nullable()();
}

// ---- Sync bookkeeping (local only) ----

/// Pending local changes waiting to be pushed (the "outbox").
class SyncOutbox extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get entity => text()(); // table name
  TextColumn get entityId => text()();
  TextColumn get payload => text()(); // JSON row as sent to Supabase
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime()();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

/// Per-table pull cursor: last (updated_at, id) seen from the server.
class SyncCursors extends Table {
  TextColumn get entity => text()();
  TextColumn get updatedAt => text()(); // server ISO timestamp, verbatim
  TextColumn get lastId => text()();

  @override
  Set<Column<Object>> get primaryKey => {entity};
}

/// People you keep in touch with (birthdays, anniversaries, call nudges).
@DataClassName('PersonRow')
class People extends Table with SyncedColumns {
  TextColumn get circleId => text()();
  TextColumn get createdBy => text()();
  TextColumn get name => text()();
  TextColumn get relation => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get birthday => text().nullable()(); // yyyy-MM-dd
  TextColumn get anniversary => text().nullable()(); // yyyy-MM-dd
  IntColumn get callEveryDays => integer().nullable()();
  DateTimeColumn get lastContactAt => dateTime().nullable()();
  TextColumn get visibility => text().withDefault(const Constant('private'))();
}

/// Names of fellow Circle members ("added by Neha"). Pull-only; other
/// profile fields (phone, email) are deliberately not mirrored.
@DataClassName('MemberRow')
class Users extends Table with SyncedColumns {
  TextColumn get name => text().nullable()();
}
