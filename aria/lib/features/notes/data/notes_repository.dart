import 'dart:async';

import 'package:aria/data/local/app_database.dart';
import 'package:aria/data/sync/local_store.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

@immutable
class QuickNote {
  const QuickNote({
    required this.id,
    required this.text,
    this.createdAt,
    this.score,
    this.shared = false,
    this.mine = true,
  });
  final String id;
  final String text;
  final DateTime? createdAt;

  /// Search relevance (0..1) when this came from a search.
  final double? score;

  /// Visible to everyone in the circle.
  final bool shared;

  /// Created by me (only the author can change sharing).
  final bool mine;
}

/// Semantic search over the server (null when offline/unavailable).
typedef RemoteNoteSearch = Future<List<QuickNote>?> Function(String query);

RemoteNoteSearch supabaseNoteSearch(SupabaseClient client) => (q) async {
  final res = await client.functions.invoke(
    'notes-search',
    body: {'query': q, 'limit': 5},
  );
  if (res.status != 200 || res.data is! Map) return null;
  return [
    for (final r in ((res.data as Map)['results'] as List? ?? const []))
      if (r is Map)
        QuickNote(
          id: r['id'] as String,
          text: r['text'] as String,
          score: (r['similarity'] as num?)?.toDouble(),
        ),
  ];
};

/// Quick notes ("the wifi password is …"), retrievable by asking.
class NotesRepository {
  NotesRepository(this.db, this.store, {required this.userId, this.remote});
  final AppDatabase db;
  final LocalStore store;
  final String userId;
  final RemoteNoteSearch? remote;

  SimpleSelectStatement<$NotesTable, NoteRow> _visibleNotes() =>
      db.select(db.notes)
        ..where(
          (n) =>
              n.deletedAt.isNull() &
              (n.visibility.equals('shared') | n.createdBy.equals(userId)),
        )
        ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]);

  Future<List<QuickNote>> allNotes() =>
      _visibleNotes().get().then((rows) => rows.map(_from).toList());

  Stream<List<QuickNote>> watchNotes({String? circleId}) =>
      (db.select(db.notes)
            ..where(
              (n) => circleId == null
                  ? const Constant(true)
                  : n.circleId.equals(circleId),
            )
            ..where(
              (n) =>
                  n.deletedAt.isNull() &
                  (n.visibility.equals('shared') | n.createdBy.equals(userId)),
            )
            ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]))
          .watch()
          .map((rows) => rows.map(_from).toList());

  QuickNote _from(NoteRow n) => QuickNote(
    id: n.id,
    text: n.content,
    createdAt: n.createdAt?.toUtc(),
    shared: n.visibility == 'shared',
    mine: n.createdBy == userId,
  );

  Future<String> add(String text, {required String circleId}) async {
    final id = const Uuid().v4();
    await store.write('notes', {
      'id': id,
      'circle_id': circleId,
      'created_by': userId,
      'text': text.trim(),
      'visibility': 'private',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    return id;
  }

  Future<void> setShared(String id, {required bool shared}) async {
    final n = await (db.select(
      db.notes,
    )..where((x) => x.id.equals(id))).getSingle();
    await store.write('notes', {
      'id': n.id,
      'circle_id': n.circleId,
      'created_by': n.createdBy,
      'text': n.content,
      'visibility': shared ? 'shared' : 'private',
      'created_at': n.createdAt?.toUtc().toIso8601String(),
    });
  }

  Future<void> update(String id, String text) async {
    final n = await (db.select(
      db.notes,
    )..where((x) => x.id.equals(id))).getSingle();
    await store.write('notes', {
      'id': n.id,
      'circle_id': n.circleId,
      'created_by': n.createdBy,
      'text': text.trim(),
      'visibility': n.visibility,
      'created_at': n.createdAt?.toUtc().toIso8601String(),
    });
  }

  /// "Forget this" — removed everywhere (soft delete syncs as a delete).
  Future<void> forget(String id) => store.softDelete('notes', id);

  Future<QuickNote?> latest() async {
    final n =
        await (db.select(db.notes)
              ..where((x) => x.deletedAt.isNull() & x.createdBy.equals(userId))
              ..orderBy([(x) => OrderingTerm.desc(x.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    return n == null ? null : _from(n);
  }

  /// Best answers for a question: semantic (server) when online, merged
  /// with on-device keyword matches so it still works offline.
  Future<List<QuickNote>> search(String query) async {
    final local = await localSearch(query);
    List<QuickNote>? semantic;
    try {
      semantic = await remote?.call(query).timeout(const Duration(seconds: 4));
    } on Object catch (e) {
      debugPrint('semantic note search unavailable: $e');
    }
    final good = (semantic ?? const <QuickNote>[]).where(
      (n) => (n.score ?? 0) >= 0.78,
    );
    final seen = <String>{};
    return [
      for (final n in [...good, ...local])
        if (seen.add(n.id)) n,
    ];
  }

  // Common question words → words people actually write in notes.
  static const _synonyms = {
    'internet': ['wifi', 'wi-fi', 'password'],
    'wifi': ['wi-fi', 'internet'],
    'code': ['password', 'pin'],
    'number': ['phone', 'mobile', 'no'],
    'phone': ['number', 'mobile'],
    'parked': ['parking', 'car'],
    'car': ['parked', 'parking'],
  };
  static const _stop = {
    'what',
    'whats',
    "what's",
    'was',
    'is',
    'the',
    'my',
    'a',
    'an',
    'of',
    'where',
    'did',
    'i',
    'who',
    'when',
    'tell',
    'me',
    'for',
    'to',
    'kya',
    'hai',
    'tha',
  };

  /// Keyword overlap with simple synonyms; offline fallback.
  Future<List<QuickNote>> localSearch(String query) async {
    final words = query
        .toLowerCase()
        .split(RegExp("[^a-z0-9ऀ-ॿ'-]+"))
        .map((w) => w.replaceAll(RegExp(r"'s$"), '')) // plumber's → plumber
        .where((w) => w.length > 1 && !_stop.contains(w))
        .toSet();
    final wantsNumber = words.any(
      (w) => const {'number', 'phone', 'mobile', 'contact'}.contains(w),
    );
    final expanded = {...words, for (final w in words) ...?_synonyms[w]};
    if (expanded.isEmpty) return const [];
    final notes = await allNotes();
    final scored = <(QuickNote, int)>[];
    for (final n in notes) {
      final t = n.text.toLowerCase();
      var hits = expanded.where(t.contains).length;
      // "What's the plumber's number?" — a phone-like number answers it.
      if (wantsNumber && RegExp(r'\d{3}[\s-]?\d{3,}').hasMatch(t)) hits++;
      if (hits > 0) scored.add((n, hits));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final (n, _) in scored.take(5)) n];
  }
}
