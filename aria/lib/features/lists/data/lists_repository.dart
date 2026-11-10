import 'package:aria/data/local/app_database.dart';
import 'package:aria/data/sync/local_store.dart';
import 'package:aria/features/lists/domain/lists.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Lists and their items, offline-first. Items merge per item on sync (each
/// item is its own row), so two people adding to Grocery never collide.
class ListsRepository {
  ListsRepository(this.db, this.store, {required this.userId});
  final AppDatabase db;
  final LocalStore store;
  final String userId;
  static const _uuid = Uuid();

  Expression<bool> _visible($ListsTable l) =>
      l.deletedAt.isNull() &
      (l.visibility.equals('shared') | l.createdBy.equals(userId));

  /// Lists with open/done counts and a preview, newest activity first.
  Stream<List<AriaList>> watchLists({String? circleId}) {
    final lists =
        (db.select(db.lists)
              ..where(
                (l) =>
                    _visible(l) &
                    (circleId == null
                        ? const Constant(true)
                        : l.circleId.equals(circleId)),
              )
              ..orderBy([(l) => OrderingTerm.asc(l.createdAt)]))
            .watch();
    final items = (db.select(
      db.listItems,
    )..where((i) => i.deletedAt.isNull())).watch();
    return lists.asyncExpand(
      (ls) => items.map((its) {
        return [
          for (final l in ls)
            () {
              final mine = its.where((i) => i.listId == l.id).toList()
                ..sort((a, b) => a.position.compareTo(b.position));
              final open = mine.where((i) => !i.done).toList();
              return AriaList(
                id: l.id,
                circleId: l.circleId,
                createdBy: l.createdBy,
                name: l.name,
                type: ListType.parse(l.type),
                visibility: l.visibility,
                openCount: open.length,
                doneCount: mine.length - open.length,
                preview: open.take(3).map((i) => i.content).toList(),
              );
            }(),
        ];
      }),
    );
  }

  Stream<AriaList?> watchList(String id) =>
      watchLists().map((ls) => ls.where((l) => l.id == id).firstOrNull);

  /// Items: open first (by position), then done.
  Stream<List<ListEntry>> watchItems(String listId) {
    final q =
        db.select(db.listItems).join([
            leftOuterJoin(
              db.users,
              db.users.id.equalsExp(db.listItems.addedBy),
            ),
          ])
          ..where(
            db.listItems.listId.equals(listId) &
                db.listItems.deletedAt.isNull(),
          )
          ..orderBy([
            OrderingTerm.asc(db.listItems.done),
            OrderingTerm.asc(db.listItems.position),
          ]);
    return q.watch().map(
      (rows) => [
        for (final r in rows)
          () {
            final i = r.readTable(db.listItems);
            final by = r.readTableOrNull(db.users);
            return ListEntry(
              id: i.id,
              listId: i.listId,
              text: i.content,
              qty: i.qty,
              done: i.done,
              addedBy: i.addedBy,
              addedByName: i.addedBy != null && i.addedBy != userId
                  ? by?.name
                  : null,
              position: i.position,
            );
          }(),
      ],
    );
  }

  Future<String> createList(
    String name, {
    required String circleId,
    ListType? type,
    bool shared = false,
  }) async {
    final id = _uuid.v4();
    await store.write('lists', {
      'id': id,
      'circle_id': circleId,
      'created_by': userId,
      'name': name.trim(),
      'type': (type ?? ListType.guess(name)).name,
      'visibility': shared ? 'shared' : 'private',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    return id;
  }

  /// Lists I can see (for the free plan's list limit).
  Future<int> count() async =>
      (await (db.select(db.lists)..where(_visible)).get()).length;

  /// Finds a list by (fuzzy) name or creates it — for "add milk to grocery".
  /// Throws [ListLimitReached] when creating would exceed [maxLists].
  Future<String> findOrCreate(
    String name, {
    required String circleId,
    int? maxLists,
  }) async {
    final wanted = name
        .toLowerCase()
        .replaceAll(RegExp(r'\s*list$'), '')
        .trim();
    final type = ListType.guess(wanted);
    final lists = await (db.select(db.lists)..where(_visible)).get();
    final match = lists.where((l) {
      final n = l.name.toLowerCase();
      return n == wanted ||
          n.contains(wanted) ||
          wanted.contains(n) ||
          (type != ListType.custom && l.type == type.name);
    }).firstOrNull;
    if (match != null) return match.id;
    if (maxLists != null && lists.length >= maxLists) {
      throw ListLimitReached(maxLists);
    }
    final display = wanted.isEmpty
        ? 'List'
        : '${wanted[0].toUpperCase()}${wanted.substring(1)}';
    return await createList(display, circleId: circleId, type: type);
  }

  Future<void> renameList(String id, String name) =>
      _updateList(id, {'name': name.trim()});
  Future<void> setShared(String id, {required bool shared}) =>
      _updateList(id, {'visibility': shared ? 'shared' : 'private'});

  Future<void> deleteList(String id) async {
    await store.softDelete('lists', id);
    final items = await (db.select(
      db.listItems,
    )..where((i) => i.listId.equals(id))).get();
    for (final i in items) {
      await store.softDelete('list_items', i.id);
    }
  }

  Future<void> _updateList(String id, Map<String, dynamic> changes) async {
    final l = await (db.select(
      db.lists,
    )..where((x) => x.id.equals(id))).getSingle();
    await store.write('lists', {
      'id': l.id,
      'circle_id': l.circleId,
      'created_by': l.createdBy,
      'name': l.name,
      'type': l.type,
      'visibility': l.visibility,
      'created_at': l.createdAt?.toUtc().toIso8601String(),
      ...changes,
    });
  }

  /// Adds items (deduplicating open ones with the same text — "milk" twice
  /// bumps the quantity instead).
  Future<void> addItems(
    String listId,
    List<String> texts, {
    double? qty,
  }) async {
    final existing = await (db.select(
      db.listItems,
    )..where((i) => i.listId.equals(listId) & i.deletedAt.isNull())).get();
    var pos = existing.fold<double>(
      0,
      (m, i) => i.position > m ? i.position : m,
    );
    for (final raw in texts) {
      final text = raw.trim();
      if (text.isEmpty) continue;
      final dup = existing
          .where(
            (i) => !i.done && i.content.toLowerCase() == text.toLowerCase(),
          )
          .firstOrNull;
      if (dup != null) {
        await _writeItem(dup, {'qty': (dup.qty ?? 1) + (qty ?? 1)});
        continue;
      }
      pos += 1;
      await store.write('list_items', {
        'id': _uuid.v4(),
        'list_id': listId,
        'text': text,
        'qty': qty,
        'done': false,
        'added_by': userId,
        'position': pos,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  Future<ListItemRow> _item(String id) =>
      (db.select(db.listItems)..where((i) => i.id.equals(id))).getSingle();

  Future<void> _writeItem(ListItemRow i, Map<String, dynamic> changes) =>
      store.write('list_items', {
        'id': i.id,
        'list_id': i.listId,
        'text': i.content,
        'qty': i.qty,
        'done': i.done,
        'added_by': i.addedBy,
        'assigned_to': i.assignedTo,
        'position': i.position,
        'created_at': i.createdAt?.toUtc().toIso8601String(),
        ...changes,
      });

  Future<void> toggle(String itemId) async {
    final i = await _item(itemId);
    await _writeItem(i, {'done': !i.done});
  }

  Future<void> setQty(String itemId, double? qty) async =>
      await _writeItem(await _item(itemId), {'qty': qty});

  Future<void> rename(String itemId, String text) async =>
      await _writeItem(await _item(itemId), {'text': text.trim()});

  Future<void> deleteItem(String itemId) =>
      store.softDelete('list_items', itemId);

  Future<void> restoreItem(String itemId) async =>
      await _writeItem(await _item(itemId), {'deleted_at': null});

  Future<void> clearDone(String listId) async {
    final done =
        await (db.select(db.listItems)..where(
              (i) =>
                  i.listId.equals(listId) &
                  i.done.equals(true) &
                  i.deletedAt.isNull(),
            ))
            .get();
    for (final i in done) {
      await store.softDelete('list_items', i.id);
    }
  }

  /// Reorder: [orderedIds] are the open items in their new order.
  Future<void> reorder(List<String> orderedIds) async {
    for (var n = 0; n < orderedIds.length; n++) {
      final i = await _item(orderedIds[n]);
      if (i.position != n + 1) {
        await _writeItem(i, {'position': (n + 1).toDouble()});
      }
    }
  }

  Future<List<ListEntry>> searchItems(String q) async {
    final like = '%${q.toLowerCase()}%';
    final rows =
        await (db.select(db.listItems)
              ..where(
                (i) => i.deletedAt.isNull() & i.content.lower().like(like),
              )
              ..limit(20))
            .get();
    return [
      for (final i in rows)
        ListEntry(
          id: i.id,
          listId: i.listId,
          text: i.content,
          qty: i.qty,
          done: i.done,
        ),
    ];
  }
}

/// Free plan list limit hit (creating would need an upgrade).
class ListLimitReached implements Exception {
  const ListLimitReached(this.max);
  final int max;
  @override
  String toString() => 'ListLimitReached($max)';
}
