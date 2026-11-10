import 'package:aria/data/local/app_database.dart';
import 'package:aria/data/sync/local_store.dart';
import 'package:aria/features/assistant/domain/parse_result.dart';
import 'package:aria/features/assistant/domain/rule_parser.dart';
import 'package:aria/features/lists/data/lists_repository.dart';
import 'package:aria/features/notes/data/notes_repository.dart';
import 'package:aria/features/people/data/people_repository.dart';
import 'package:aria/features/people/domain/person.dart';
import 'package:aria/features/progress/domain/stats.dart';
import 'package:aria/features/reminders/data/reminder_repository.dart';
import 'package:aria/features/reminders/domain/alert_plan.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/routines/data/routines_repository.dart';
import 'package:aria/features/routines/domain/routine.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

DateTime at(int d, int h, [int m = 0]) =>
    fromWall(DateTime.utc(2026, 11, d, h, m), kTestZone);

void main() {
  late AppDatabase db;
  late LocalStore store;
  setUpAll(ensureTimeZones);
  setUp(() async {
    db = memoryDb();
    store = LocalStore(db);
    await seedCircle(db, 'me');
  });
  tearDown(() => db.close());

  group('lists', () {
    test('create, add (dedupe → qty), toggle, reorder, clear done', () async {
      final repo = ListsRepository(db, store, userId: 'me');
      final id = await repo.createList('Grocery', circleId: kTestCircle);
      await repo.addItems(id, ['Milk', 'Eggs', 'Bread']);
      await repo.addItems(id, ['milk']);
      var items = await repo.watchItems(id).first;
      expect(items.map((i) => i.text), ['Milk', 'Eggs', 'Bread']);
      expect(items.first.qty, 2, reason: 'second "milk" bumps quantity');

      await repo.toggle(items[1].id); // eggs done
      await repo.reorder([items[2].id, items[0].id]); // bread, milk
      items = await repo.watchItems(id).first;
      expect(items.map((i) => '${i.text}${i.done ? '✓' : ''}'), [
        'Bread',
        'Milk',
        'Eggs✓',
      ]);

      final list = (await repo.watchLists().first).single;
      expect(list.openCount, 2);
      expect(list.doneCount, 1);
      expect(list.preview, ['Bread', 'Milk']);

      await repo.clearDone(id);
      expect((await repo.watchItems(id).first).map((i) => i.text), [
        'Bread',
        'Milk',
      ]);
    });

    test('findOrCreate matches by name or type', () async {
      final repo = ListsRepository(db, store, userId: 'me');
      final g = await repo.findOrCreate('grocery list', circleId: kTestCircle);
      expect(await repo.findOrCreate('Grocery', circleId: kTestCircle), g);
      expect(
        await repo.findOrCreate('shopping', circleId: kTestCircle),
        g,
        reason: 'same type',
      );
      final p = await repo.findOrCreate('packing', circleId: kTestCircle);
      expect(p, isNot(g));
      expect(
        (await repo.watchLists().first).map((l) => l.type.name),
        containsAll(['grocery', 'packing']),
      );
    });

    test('"added by" shows another Circle member’s name', () async {
      final repo = ListsRepository(db, store, userId: 'me');
      final id = await repo.createList('Grocery', circleId: kTestCircle);
      await db
          .into(db.users)
          .insert(UsersCompanion.insert(id: 'neha', name: const Value('Neha')));
      await store.applyRemote('list_items', [
        {
          'id': 'x1',
          'list_id': id,
          'text': 'Atta',
          'added_by': 'neha',
          'position': 1.0,
          'done': false,
          'updated_at': '2026-11-09T00:00:00Z',
        },
      ]);
      await repo.addItems(id, ['Rice']);
      final items = await repo.watchItems(id).first;
      expect(items.firstWhere((i) => i.text == 'Atta').addedByName, 'Neha');
      expect(
        items.firstWhere((i) => i.text == 'Rice').addedByName,
        isNull,
        reason: 'not for my own items',
      );
    });
  });

  group('notes', () {
    test('local search understands synonyms; forget deletes', () async {
      final repo = NotesRepository(db, store, userId: 'me');
      await repo.add('Wifi password is sunflower42', circleId: kTestCircle);
      await repo.add('Plumber Ramesh 98765 43210', circleId: kTestCircle);
      expect(
        (await repo.localSearch("what's the internet code?")).first.text,
        contains('sunflower42'),
      );
      expect(
        (await repo.localSearch("plumber's number")).first.text,
        contains('Ramesh'),
      );
      final last = await repo.latest();
      await repo.forget(last!.id);
      expect(await repo.allNotes(), hasLength(1));
    });

    test(
      'semantic results (score ≥ 0.78) come first, then keyword; deduped',
      () async {
        late NotesRepository repo;
        repo = NotesRepository(
          db,
          store,
          userId: 'me',
          remote: (_) async {
            final all = await repo.allNotes();
            return [
              QuickNote(
                id: all.firstWhere((n) => n.text.contains('B2')).id,
                text: 'Car parked on level B2',
                score: 0.85,
              ),
              QuickNote(
                id: all.firstWhere((n) => n.text.contains('wifi')).id,
                text: 'x',
                score: 0.4,
              ),
            ];
          },
        );
        await repo.add('Car parked on level B2', circleId: kTestCircle);
        await repo.add('The wifi password is tulip', circleId: kTestCircle);
        final hits = await repo.search('where did I leave the car');
        expect(hits.first.text, 'Car parked on level B2');
        expect(hits.where((h) => h.text.contains('B2')), hasLength(1));
      },
    );

    test('offline: falls back to keyword search', () async {
      final repo = NotesRepository(
        db,
        store,
        userId: 'me',
        remote: (_) async => throw Exception('offline'),
      );
      await repo.add('Car parked on level B2', circleId: kTestCircle);
      expect(
        (await repo.search('where is the car parked')).single.text,
        contains('B2'),
      );
    });
  });

  group('people', () {
    late ReminderRepository reminders;
    late PeopleRepository people;
    setUp(() {
      reminders = ReminderRepository(db, store, userId: 'me');
      people = PeopleRepository(
        db,
        store,
        reminders,
        userId: 'me',
        zone: kTestZone,
      );
    });

    test(
      'birthday → yearly reminder at 9 AM; keep-in-touch → call nudge',
      () async {
        final dad = people
            .newPerson('Dad', circleId: kTestCircle)
            .copyWith(
              phone: () => '9876543210',
              birthday: () => DateTime(1958, 3, 14),
              callEveryDays: () => 14,
            );
        await people.save(dad, now: at(9, 10));

        final bday = (await reminders.get(
          PeopleRepository.linkedId(dad.id, 'birthday'),
        ))!;
        expect(bday.title, '🎂 Dad’s birthday');
        expect(bday.rrule, 'FREQ=YEARLY');
        expect(bday.startAt, fromWall(DateTime.utc(2027, 3, 14, 9), kTestZone));
        expect(bday.contact!['phone'], '9876543210');

        final call = (await reminders.get(
          PeopleRepository.linkedId(dad.id, 'call'),
        ))!;
        expect(call.title, 'Call Dad');
        expect(call.keepInTouch, isTrue);
        expect(call.startAt, at(9, 18), reason: 'never called → this evening');

        // You call on the 9th at 7 PM → next nudge 14 days later at 6 PM.
        await people.markContacted(dad.id, at(9, 19));
        expect((await reminders.get(call.id))!.startAt, at(23, 18));
        expect((await people.get(dad.id))!.lastContactAt, at(9, 19));
      },
    );

    test('removing a date or the person removes linked reminders', () async {
      var p = people
          .newPerson('Asha', circleId: kTestCircle)
          .copyWith(birthday: () => DateTime(1990, 1, 2));
      await people.save(p, now: at(9, 10));
      p = p.copyWith(
        birthday: () => null,
        anniversary: () => DateTime(2015, 12),
      );
      await people.save(p, now: at(9, 10));
      expect(
        (await reminders.get(PeopleRepository.linkedId(p.id, 'birthday')))!
            .deletedAt,
        isNotNull,
      );
      expect(
        (await reminders.get(PeopleRepository.linkedId(p.id, 'anniversary')))!
            .deletedAt,
        isNull,
      );
      await people.delete(p);
      expect(
        (await reminders.get(PeopleRepository.linkedId(p.id, 'anniversary')))!
            .deletedAt,
        isNotNull,
      );
    });

    test('one-tap links and dates', () {
      const p = Person(
        id: 'p',
        circleId: 'c',
        createdBy: 'me',
        name: 'Dad',
        phone: '98765 43210',
      );
      expect(p.callUri.toString(), 'tel:+919876543210');
      expect(
        p.whatsappUri('Hi')!.toString(),
        'https://wa.me/919876543210?text=Hi',
      );
      expect(
        Person.nextOccurrence(DateTime(1990, 11, 9), DateTime(2026, 11, 9)),
        DateTime(2026, 11, 9),
      );
      expect(
        Person.nextOccurrence(DateTime(1990, 1, 2), DateTime(2026, 11, 9)),
        DateTime(2027, 1, 2),
      );
      expect(p.dueForCall(DateTime(2026)), isFalse, reason: 'no cadence set');
    });
  });

  group('routines', () {
    test('save/load, run history, streak, find by spoken name', () async {
      final repo = RoutinesRepository(db, store, userId: 'me');
      final t = Routine.templates.first;
      final r = repo
          .create(t.$1, circleId: kTestCircle, emoji: t.$2, steps: t.$3)
          .copyWith(atMinute: () => 7 * 60, days: {1, 2, 3, 4, 5});
      await repo.save(r);
      final loaded = (await repo.get(r.id))!;
      expect(loaded.steps, t.$3);
      expect(loaded.atMinute, 420);
      expect(loaded.days, {1, 2, 3, 4, 5});

      await repo.markRun(r.id, DateTime(2026, 11, 7));
      await repo.markRun(r.id, DateTime(2026, 11, 8));
      final after = (await repo.markRun(r.id, DateTime(2026, 11, 9)))!;
      expect(after.streak(DateTime(2026, 11, 9)), 3);
      expect(
        after.streak(DateTime(2026, 11, 10)),
        3,
        reason: 'still alive until today ends',
      );
      expect(after.streak(DateTime(2026, 11, 11)), 0);

      expect((await repo.findByName('morning mode'))!.id, r.id);
      expect(await repo.findByName('gym'), isNull);
    });

    test('time-triggered routines are scheduled on allowed days', () {
      final alerts = planRoutineAlerts(
        [
          (
            id: 'r',
            name: 'Morning mode',
            emoji: '☀️',
            atMinute: 7 * 60,
            days: {1, 2, 3, 4, 5},
            steps: ['Water'],
          ),
        ],
        now: at(9, 10), // Monday 10:00 → next is Tue 7:00
        zone: kTestZone,
        mode: NotifyMode.both,
      );
      expect(alerts.map((a) => a.fireAt), [at(10, 7), at(11, 7)]);
      expect(alerts.first.kind, AlertKind.routine);
      expect(alerts.first.reminderId, 'routine:r');
      expect(alerts.first.spoken, 'Time for Morning mode. First: Water.');
    });
  });

  group('stats', () {
    ReminderEvent ev(
      String id,
      ReminderEventType t,
      DateTime occ, {
      DateTime? at,
    }) => ReminderEvent(
      id: '$id-${occ.toIso8601String()}-${t.name}',
      reminderId: id,
      userId: 'me',
      type: t,
      at: at ?? occ,
      occurrenceAt: occ,
    );

    test('streak counts consecutive done occurrences until a miss', () {
      final e = [
        ev('pill', ReminderEventType.done, at(5, 8)),
        ev('pill', ReminderEventType.missed, at(6, 8)),
        ev('pill', ReminderEventType.done, at(7, 8)),
        ev('pill', ReminderEventType.done, at(8, 8)),
        ev('pill', ReminderEventType.done, at(9, 8)),
      ];
      expect(streakFor('pill', e), 3);
      expect(kStreakMilestones.contains(3), isTrue);
    });

    test('weekly report: on-time %, bills, per day', () {
      final reminders = [
        Reminder(
          id: 'pill',
          circleId: 'c',
          createdBy: 'me',
          title: 'Vitamin D',
          rrule: 'FREQ=DAILY',
          startAt: at(10, 8),
          timezone: kTestZone,
        ),
        Reminder(
          id: 'rent',
          circleId: 'c',
          createdBy: 'me',
          title: 'Rent',
          category: ReminderCategory.bills,
          startAt: at(5, 10),
          timezone: kTestZone,
        ),
      ];
      final events = [
        ev('pill', ReminderEventType.done, at(8, 8), at: at(8, 8, 10)),
        ev('pill', ReminderEventType.done, at(9, 8), at: at(9, 9, 30)), // late
        ev('pill', ReminderEventType.missed, at(7, 8)),
        ev('rent', ReminderEventType.done, at(5, 10), at: at(5, 10, 5)),
      ];
      final r = WeeklyReport.build(
        events: events,
        reminders: reminders,
        now: at(9, 12),
        zone: kTestZone,
      );
      expect(r.done, 3);
      expect(r.onTime, 2);
      expect(r.missed, 1);
      expect(r.onTimePercent, 50);
      expect((r.billsPaid, r.billsOnTime), (1, 1));
      expect(r.longestStreak, 2);
      expect(r.perDay.last, 1, reason: 'one done today');
    });
  });

  group('voice commands (rules)', () {
    ParsedCommand p(String s) =>
        RuleParser(now: at(9, 10), zone: kTestZone).parse(s);
    test('start a routine; forget that note', () {
      expect(p('start morning mode').intent, ParseIntent.startRoutine);
      expect(p('start morning mode').items.single.title, 'morning mode');
      expect(p('forget that note').intent, ParseIntent.forgetNote);
      expect(
        p('start the washing machine at 9 pm').intent,
        ParseIntent.createReminder,
        reason: 'not a routine phrase',
      );
    });
  });
}
