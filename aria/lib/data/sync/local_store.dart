import 'dart:convert';

import 'package:aria/data/local/app_database.dart';
import 'package:aria/data/sync/backoff.dart';
import 'package:aria/data/sync/sync_remote.dart';
import 'package:drift/drift.dart';

/// Offline-first write/read primitives shared by every feature repository.
///
/// * Writes go to SQLite **and** the outbox in one transaction, so the UI
///   updates instantly and nothing is lost if the app dies before syncing.
/// * Remote rows are applied generically by column name.
class LocalStore {
  LocalStore(this.db, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final AppDatabase db;
  final DateTime Function() _now;

  // ---------------------------------------------------------------- writes

  /// Upserts [row] locally and queues it for push. [row] uses Postgres
  /// column names and JSON-compatible values.
  Future<void> write(String table, RemoteRow row) async {
    assert(kPushableTables.contains(table), '$table is pull-only');
    final id = row['id'] as String;
    final now = _now().toUtc();
    final stamped = {...row, 'updated_at': now.toIso8601String()};
    await db.transaction(() async {
      await _upsertLocal(table, stamped);
      await _enqueue(table, id, stamped, now);
    });
  }

  /// Soft delete: sets deleted_at and syncs it like any other change.
  Future<void> softDelete(String table, String id) async {
    final existing = await _readRow(table, id);
    if (existing == null) return;
    await write(table, {
      ...existing,
      'deleted_at': _now().toUtc().toIso8601String(),
    });
  }

  Future<void> _enqueue(
    String table,
    String id,
    RemoteRow payload,
    DateTime now,
  ) async {
    // Collapse: only the newest pending change per entity is kept, which
    // keeps the queue short after many offline edits.
    await (db.delete(
      db.syncOutbox,
    )..where((o) => o.entity.equals(table) & o.entityId.equals(id))).go();
    await db
        .into(db.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            entity: table,
            entityId: id,
            payload: jsonEncode(payload),
            nextAttemptAt: now,
            createdAt: now,
          ),
        );
  }

  // ---------------------------------------------------------------- outbox

  Future<List<SyncOutboxData>> dueOutbox({int limit = 100}) =>
      (db.select(db.syncOutbox)
            ..where(
              (o) => o.nextAttemptAt.isSmallerOrEqualValue(_now().toUtc()),
            )
            ..orderBy([(o) => OrderingTerm.asc(o.seq)])
            ..limit(limit))
          .get();

  Future<int> pendingCount() async {
    final c = db.syncOutbox.seq.count();
    final r = await (db.selectOnly(db.syncOutbox)..addColumns([c])).getSingle();
    final count = r.read(c);
    return count ?? 0;
  }

  Future<DateTime?> nextRetryAt() async {
    final m = db.syncOutbox.nextAttemptAt.min();
    final r = await (db.selectOnly(db.syncOutbox)..addColumns([m])).getSingle();
    return r.read(m);
  }

  Future<void> markPushed(SyncOutboxData entry) =>
      (db.delete(db.syncOutbox)..where((o) => o.seq.equals(entry.seq))).go();

  Future<void> markFailed(SyncOutboxData entry, Object error) {
    final attempts = entry.attempts + 1;
    return (db.update(
      db.syncOutbox,
    )..where((o) => o.seq.equals(entry.seq))).write(
      SyncOutboxCompanion(
        attempts: Value(attempts),
        lastError: Value(error.toString()),
        nextAttemptAt: Value(_now().toUtc().add(backoffFor(attempts))),
      ),
    );
  }

  // ---------------------------------------------------------------- pull

  Future<SyncCursor?> cursorFor(String table) async {
    final c = await (db.select(
      db.syncCursors,
    )..where((c) => c.entity.equals(table))).getSingleOrNull();
    return c;
  }

  /// Applies a page of server rows and advances the cursor atomically.
  ///
  /// Rows with a pending local change are skipped: the local edit is newer
  /// from this device's point of view and will be pushed next (the server
  /// then stamps it, so it wins last-write-wins).
  Future<void> applyRemote(String table, List<RemoteRow> rows) async {
    if (rows.isEmpty) return;
    await db.transaction(() async {
      final pending = await (db.select(
        db.syncOutbox,
      )..where((o) => o.entity.equals(table))).map((o) => o.entityId).get();
      final skip = pending.toSet();
      for (final row in rows) {
        if (skip.contains(row['id'])) continue;
        await _upsertLocal(table, row);
      }
      final last = rows.last;
      await db
          .into(db.syncCursors)
          .insertOnConflictUpdate(
            SyncCursorsCompanion.insert(
              entity: table,
              updatedAt: last['updated_at'] as String,
              lastId: last['id'] as String,
            ),
          );
    });
  }

  // ---------------------------------------------------------------- generic

  Future<void> _upsertLocal(String table, RemoteRow row) async {
    final cols = db.columnsOf(table);
    final keys = row.keys.where(cols.contains).toList();
    final values = keys.map((k) => _toSql(row[k])).toList();
    final placeholders = List.filled(keys.length, '?').join(', ');
    final updates = keys
        .where((k) => k != 'id')
        .map((k) => '"$k" = excluded."$k"')
        .join(', ');
    await db.customInsert(
      'INSERT INTO "$table" (${keys.map((k) => '"$k"').join(', ')}) '
      'VALUES ($placeholders) '
      'ON CONFLICT(id) DO UPDATE SET $updates',
      variables: values.map(Variable.new).toList(),
      updates: {db.allTables.firstWhere((t) => t.actualTableName == table)},
    );
  }

  Future<RemoteRow?> _readRow(String table, String id) async {
    final r = await db
        .customSelect(
          'SELECT * FROM "$table" WHERE id = ?',
          variables: [Variable(id)],
        )
        .getSingleOrNull();
    if (r == null) return null;
    return {
      for (final e in r.data.entries) e.key: _fromSql(table, e.key, e.value),
    };
  }

  Object? _toSql(Object? v) => switch (v) {
    null => null,
    final bool b => b ? 1 : 0,
    final Map<String, dynamic> m => jsonEncode(m),
    final List<dynamic> l => jsonEncode(l),
    final DateTime d => d.toUtc().toIso8601String(),
    _ => v,
  };

  Object? _fromSql(String table, String column, Object? v) {
    if (v == null) return null;
    final col = db.allTables
        .firstWhere((t) => t.actualTableName == table)
        .$columns
        .firstWhere((c) => c.name == column);
    if (col.type == DriftSqlType.bool) return v == 1;
    if (column.endsWith('_json') && v is String) return jsonDecode(v);
    return v;
  }
}
