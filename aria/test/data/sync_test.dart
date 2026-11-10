import 'dart:math' as math;

import 'package:aria/data/local/app_database.dart';
import 'package:aria/data/sync/backoff.dart';
import 'package:aria/data/sync/local_store.dart';
import 'package:aria/data/sync/sync_engine.dart';
import 'package:aria/data/sync/sync_remote.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

RemoteRow reminder(String id, String title) => {
  'id': id,
  'circle_id': 'circle-1',
  'created_by': 'user-1',
  'title': title,
  'category': 'health',
  'all_day': false,
  'follow_up_json': {'enabled': true, 'every_min': 10},
};

void main() {
  late AppDatabase db;
  late LocalStore store;
  late FakeSyncRemote remote;
  late SyncEngine engine;
  var now = DateTime.utc(2026, 11, 8, 9);

  setUp(() {
    now = DateTime.utc(2026, 11, 8, 9);
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    store = LocalStore(db, clock: () => now);
    remote = FakeSyncRemote();
    engine = SyncEngine(store: store, remote: remote, pageSize: 2);
  });

  tearDown(() async {
    engine.dispose();
    await db.close();
  });

  group('backoff', () {
    test('grows exponentially and is capped', () {
      final maxRandom = _FixedRandom(1);
      expect(backoffFor(1, random: maxRandom).inSeconds, 2);
      expect(backoffFor(2, random: maxRandom).inSeconds, 4);
      expect(backoffFor(5, random: maxRandom).inSeconds, 32);
      expect(backoffFor(30, random: maxRandom), const Duration(minutes: 10));
    });

    test('jitter stays within 50–100%', () {
      final minRandom = _FixedRandom(0);
      expect(backoffFor(3, random: minRandom).inSeconds, 4); // 8s * 0.5
    });
  });

  group('cursorFilter', () {
    test('quotes timestamps and tie-breaks on id', () {
      expect(
        cursorFilter('2026-11-08T10:00:00+00:00', 'abc'),
        'updated_at.gt."2026-11-08T10:00:00+00:00",'
        'and(updated_at.eq."2026-11-08T10:00:00+00:00",id.gt.abc)',
      );
      expect(cursorFilter('t', null), 'updated_at.gt."t"');
    });
  });

  group('LocalStore', () {
    test('write updates the local table and queues one outbox entry', () async {
      await store.write('reminders', reminder('r1', 'Vitamin D'));
      await store.write('reminders', reminder('r1', 'Vitamin D3'));

      final rows = await db.select(db.reminders).get();
      expect(rows.single.title, 'Vitamin D3');
      expect(rows.single.followUpJson, contains('every_min'));
      expect(await store.pendingCount(), 1, reason: 'edits collapse');
    });

    test('softDelete sets deleted_at and syncs it', () async {
      await store.write('reminders', reminder('r1', 'Old'));
      await store.softDelete('reminders', 'r1');
      final row = await db.select(db.reminders).getSingle();
      expect(row.deletedAt, isNotNull);
      final queued = await store.dueOutbox();
      expect(queued.single.payload, contains('"deleted_at"'));
      expect(
        queued.single.payload,
        contains('"all_day":false'),
        reason: 'booleans round-trip as JSON booleans',
      );
    });

    test('pull-only tables cannot be written', () {
      expect(
        () => store.write('circles', {'id': 'c'}),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('SyncEngine', () {
    test('pushes the outbox and pulls the server copy back', () async {
      await store.write('reminders', reminder('r1', 'Water'));
      final result = await engine.syncNow();

      expect(result.pushed, 1);
      expect(await store.pendingCount(), 0);
      expect(remote.tables['reminders']!['r1']!['title'], 'Water');
      final cursor = await store.cursorFor('reminders');
      expect(cursor!.lastId, 'r1');
    });

    test('failed push stays queued with exponential backoff', () async {
      remote.failFor.add('r1');
      await store.write('reminders', reminder('r1', 'Water'));

      final first = await engine.syncNow();
      expect(first.failed, 1);
      final entry = (await db.select(db.syncOutbox).get()).single;
      expect(entry.attempts, 1);
      expect(entry.nextAttemptAt.isAfter(now), isTrue);
      expect(entry.lastError, contains('network down'));

      // Not due yet → not retried.
      remote.failFor.clear();
      expect((await engine.syncNow()).pushed, 0);

      // After the backoff elapses it goes through.
      now = now.add(const Duration(minutes: 11));
      expect((await engine.syncNow()).pushed, 1);
      expect(await store.pendingCount(), 0);
    });

    test(
      'pages through server changes using the (updated_at, id) cursor',
      () async {
        for (var i = 0; i < 5; i++) {
          remote.serverWrite('reminders', reminder('s$i', 'Server $i'));
        }
        final result = await engine.syncNow();
        expect(result.pulled, 5, reason: 'pageSize 2 → 3 pages');
        expect(await db.select(db.reminders).get(), hasLength(5));

        // Incremental: nothing new → nothing pulled.
        expect((await engine.syncNow()).pulled, 0);
        remote.serverWrite('reminders', reminder('s1', 'Edited elsewhere'));
        expect((await engine.syncNow()).pulled, 1);
        final s1 = await (db.select(
          db.reminders,
        )..where((r) => r.id.equals('s1'))).getSingle();
        expect(s1.title, 'Edited elsewhere');
      },
    );

    test('a pending local edit is not overwritten by a pull', () async {
      remote
        ..serverWrite('reminders', reminder('r1', 'Server title'))
        ..failFor.add('r1');
      await store.write('reminders', reminder('r1', 'My offline edit'));

      await engine.syncNow(); // push fails, pull runs
      final row = await db.select(db.reminders).getSingle();
      expect(row.title, 'My offline edit');
    });

    test('server-only columns are ignored locally', () async {
      remote.serverWrite('notes', {
        'id': 'n1',
        'circle_id': 'circle-1',
        'created_by': 'user-1',
        'text': 'Wi-Fi password is on the router',
        'embedding': [0.1, 0.2],
        'visibility': 'private',
      });
      await engine.syncNow();
      final note = await db.select(db.notes).getSingle();
      expect(note.content, startsWith('Wi-Fi'));
    });

    test('concurrent sync requests coalesce into one running pass', () async {
      await store.write('reminders', reminder('r1', 'Water'));
      final a = engine.syncNow();
      final b = engine.syncNow();
      expect(identical(a, b), isTrue);
      final result = await a;
      expect(remote.pushCalls, 1, reason: 'follow-up pass finds nothing new');
      expect(result.pushed, 1);
    });
  });
}

class _FixedRandom implements math.Random {
  _FixedRandom(this.value);
  final double value;
  @override
  double nextDouble() => value;
  @override
  bool nextBool() => value >= 0.5;
  @override
  int nextInt(int max) => (value * max).floor();
}
