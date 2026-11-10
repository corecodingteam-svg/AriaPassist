import 'dart:convert';

import 'package:aria/data/local/app_database.dart';
import 'package:aria/data/sync/local_store.dart';
import 'package:aria/features/routines/domain/routine.dart';
import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class RoutinesRepository {
  RoutinesRepository(this.db, this.store, {required this.userId});
  final AppDatabase db;
  final LocalStore store;
  final String userId;

  Stream<List<Routine>> watchRoutines() =>
      (db.select(db.routines)
            ..where((r) => r.deletedAt.isNull() & r.userId.equals(userId))
            ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
          .watch()
          .map((rows) => rows.map(_from).toList());

  Future<List<Routine>> all() =>
      (db.select(db.routines)
            ..where((r) => r.deletedAt.isNull() & r.userId.equals(userId))
            ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
          .get()
          .then((rows) => rows.map(_from).toList());

  Future<Routine?> get(String id) async {
    final r = await (db.select(
      db.routines,
    )..where((x) => x.id.equals(id))).getSingleOrNull();
    return r == null || r.deletedAt != null ? null : _from(r);
  }

  static Routine _from(RoutineRow r) => Routine.fromJson(
    id: r.id,
    circleId: r.circleId,
    userId: r.userId,
    name: r.name,
    trigger: r.triggerJson == null
        ? null
        : jsonDecode(r.triggerJson!) as Map<String, dynamic>,
    steps: r.stepsJson == null
        ? null
        : jsonDecode(r.stepsJson!) as List<dynamic>,
  );

  Routine create(
    String name, {
    required String circleId,
    String emoji = '☀️',
    List<RoutineStep> steps = const [],
  }) => Routine(
    id: const Uuid().v4(),
    circleId: circleId,
    userId: userId,
    name: name.trim(),
    emoji: emoji,
    steps: steps,
  );

  Future<void> save(Routine r) => store.write('routines', {
    'id': r.id,
    'circle_id': r.circleId,
    'user_id': r.userId,
    'name': r.name,
    'trigger_json': r.triggerJson(),
    'steps_json': [for (final s in r.steps) s.toJson()],
  });

  Future<void> delete(String id) => store.softDelete('routines', id);

  /// Records a completed run for today (local date).
  Future<Routine?> markRun(String id, DateTime localNow) async {
    final r = await get(id);
    if (r == null) return null;
    final day = DateFormat('yyyy-MM-dd').format(localNow);
    if (r.runs.contains(day)) return r;
    final updated = r.copyWith(runs: [...r.runs, day]);
    await save(updated);
    return updated;
  }

  /// "start morning mode" → best name match.
  Future<Routine?> findByName(String spoken) async {
    final words = spoken
        .toLowerCase()
        .replaceAll(RegExp(r'\b(mode|routine|my|the)\b'), ' ')
        .trim();
    if (words.isEmpty) return null;
    final routines = await all();
    return routines
            .where((r) => r.name.toLowerCase().contains(words))
            .firstOrNull ??
        routines
            .where(
              (r) => words
                  .split(RegExp(r'\s+'))
                  .any((w) => w.length > 2 && r.name.toLowerCase().contains(w)),
            )
            .firstOrNull;
  }
}
