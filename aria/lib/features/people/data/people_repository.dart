import 'package:aria/data/local/app_database.dart';
import 'package:aria/data/sync/local_store.dart';
import 'package:aria/features/people/domain/person.dart';
import 'package:aria/features/reminders/data/reminder_repository.dart';
import 'package:aria/features/reminders/domain/recurrence.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/reminder_logic.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/l10n/tr.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// People + the reminders they imply. Each person owns up to three linked
/// reminders with deterministic ids, so editing a person updates them in
/// place: 🎂 birthday (yearly), 💍 anniversary (yearly), 📞 keep in touch.
class PeopleRepository {
  PeopleRepository(
    this.db,
    this.store,
    this.reminders, {
    required this.userId,
    required this.zone,
    this.occasionHour = 9,
    this.callHour = 18,
  });

  final AppDatabase db;
  final LocalStore store;
  final ReminderRepository reminders;
  final String userId;
  final String zone;
  final int occasionHour;
  final int callHour;
  static const _uuid = Uuid();
  static const _ns = 'a5c1e0f4-3d2b-4c8e-9f17-0b6d2e8a4c31';

  static String linkedId(String personId, String kind) =>
      _uuid.v5(_ns, '$personId|$kind');

  Stream<List<Person>> watchPeople({String? circleId}) =>
      (db.select(db.people)
            ..where(
              (p) => circleId == null
                  ? const Constant(true)
                  : p.circleId.equals(circleId),
            )
            ..where(
              (p) =>
                  p.deletedAt.isNull() &
                  (p.visibility.equals('shared') | p.createdBy.equals(userId)),
            )
            ..orderBy([(p) => OrderingTerm.asc(p.name)]))
          .watch()
          .map((rows) => rows.map(_from).toList());

  Future<Person?> get(String id) async {
    final r = await (db.select(
      db.people,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
    return r == null ? null : _from(r);
  }

  static Person _from(PersonRow r) => Person.fromFields(
    id: r.id,
    circleId: r.circleId,
    createdBy: r.createdBy,
    name: r.name,
    relation: r.relation,
    phone: r.phone,
    birthday: r.birthday,
    anniversary: r.anniversary,
    callEveryDays: r.callEveryDays,
    lastContactAt: r.lastContactAt?.toUtc(),
    visibility: r.visibility,
  );

  Person newPerson(String name, {required String circleId}) => Person(
    id: _uuid.v4(),
    circleId: circleId,
    createdBy: userId,
    name: name.trim(),
  );

  Future<void> save(Person p, {DateTime? now}) async {
    await store.write('people', p.toRow());
    await _syncLinkedReminders(p, now ?? DateTime.now().toUtc());
  }

  Future<void> delete(Person p) async {
    await store.softDelete('people', p.id);
    for (final kind in ['birthday', 'anniversary', 'call']) {
      await store.softDelete('reminders', linkedId(p.id, kind));
    }
  }

  /// "I called Dad": resets the keep-in-touch clock.
  Future<void> markContacted(String personId, DateTime now) async {
    final p = await get(personId);
    if (p == null) return;
    await store.write('people', p.copyWith(lastContactAt: () => now).toRow());
    final call = await reminders.get(linkedId(personId, 'call'));
    if (call != null && call.isActive) {
      await reminders.apply(ReminderLogic.complete(call, userId, now));
    }
  }

  Future<void> _syncLinkedReminders(Person p, DateTime now) async {
    final contact = {'person_id': p.id, 'name': p.name, 'phone': p.phone};
    final today = toWall(now, zone);
    final todayDate = DateTime(today.year, today.month, today.day);

    Future<void> occasion(String kind, DateTime? date, String title) async {
      final id = linkedId(p.id, kind);
      final existing = await reminders.get(id);
      if (date == null) {
        if (existing != null && existing.deletedAt == null) {
          await store.softDelete('reminders', id);
        }
        return;
      }
      final next = Person.nextOccurrence(date, todayDate)!;
      await reminders.save(
        Reminder(
          id: id,
          circleId: p.circleId,
          createdBy: userId,
          title: title,
          category: ReminderCategory.people,
          startAt: fromWall(
            DateTime.utc(next.year, next.month, next.day, occasionHour),
            zone,
          ),
          rrule: RecurrenceRule.yearly.toString(),
          timezone: zone,
          followUp: FollowUp.off,
          contact: {...contact, 'occasion': kind},
          createdAt: existing?.createdAt ?? now,
        ),
      );
    }

    await occasion('birthday', p.birthday, '🎂 ${p.name}’s birthday');
    await occasion('anniversary', p.anniversary, '💍 ${p.name}’s anniversary');

    final callId = linkedId(p.id, 'call');
    final existingCall = await reminders.get(callId);
    if (p.callEveryDays == null) {
      if (existingCall != null && existingCall.deletedAt == null) {
        await store.softDelete('reminders', callId);
      }
      return;
    }
    final last = p.lastContactAt == null
        ? today
        : toWall(p.lastContactAt!, zone);
    var due = DateTime.utc(
      last.year,
      last.month,
      last.day + (p.lastContactAt == null ? 0 : p.callEveryDays!),
      callHour,
    );
    if (!fromWall(due, zone).isAfter(now)) {
      due = DateTime.utc(
        today.year,
        today.month,
        today.day + (today.hour >= callHour ? 1 : 0),
        callHour,
      );
    }
    await reminders.save(
      Reminder(
        id: callId,
        circleId: p.circleId,
        createdBy: userId,
        title: tr('Call {0}', [p.name]),
        category: ReminderCategory.people,
        startAt: fromWall(due, zone),
        rrule: RecurrenceRule(
          freq: Freq.daily,
          interval: p.callEveryDays!,
        ).toString(),
        timezone: zone,
        followUp: FollowUp.off,
        contact: {...contact, 'keep_in_touch': true},
        notes: p.relation,
        createdAt: existingCall?.createdAt ?? now,
      ),
    );
  }
}
