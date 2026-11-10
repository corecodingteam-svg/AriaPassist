import 'package:aria/features/assistant/domain/parse_result.dart';
import 'package:aria/features/assistant/domain/rule_parser.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:flutter_test/flutter_test.dart';

const ist = 'Asia/Kolkata';
DateTime at(int m, int d, int h, [int min = 0]) =>
    fromWall(DateTime.utc(2026, m, d, h, min), ist);

/// Monday 9 Nov 2026, 10:00 IST.
final DateTime now = at(11, 9, 10);

const refs = <ReminderRef>[
  (id: 'r-vit', title: 'Vitamin D'),
  (id: 'r-rent', title: 'Pay rent'),
  (id: 'r-meet', title: 'Team meeting'),
];

ParsedCommand p(String s) =>
    RuleParser(now: now, zone: ist, reminders: refs).parse(s);
ParsedItem one(String s) {
  final c = p(s);
  expect(c.items, hasLength(1), reason: '$s → $c');
  return c.items.single;
}

void main() {
  setUpAll(ensureTimeZones);

  group('times', () {
    final cases = <String, DateTime>{
      'remind me to drink water at 11 am': at(11, 9, 11),
      'remind me to call mom at 6': at(11, 9, 18), // bare 6 → PM
      'remind me to stretch at 8:30': at(11, 9, 20, 30), // 8:30 AM passed → PM
      'take medicine at 9.15 pm': at(11, 9, 21, 15),
      'remind me to drink water at 11 AM.': at(11, 9, 11),
      'call the bank tomorrow at 10': at(11, 10, 10),
      'kal subah 8 baje dawai lene ki yaad dilana': at(11, 10, 8),
      'shaam 7 baje gym': at(11, 9, 19),
      'raat ko 10 baje doodh': at(11, 9, 22),
      'parso dopahar 2 baje doctor': at(11, 11, 14),
      'remind me after lunch to call plumber': at(11, 9, 14),
      'this evening water the plants': at(11, 9, 18),
      'in 20 minutes check the oven': at(11, 9, 10, 20),
      'check the oven in 2 hours': at(11, 9, 12),
      '20 minute baad chai': at(11, 9, 10, 20),
      'remind me to submit report on friday at 5 pm': at(11, 13, 17),
      'next monday 9 am standup': at(11, 16, 9),
      'pay rent on 5 december at 10': at(12, 5, 10),
      'december 25 at 8 am wish everyone': at(12, 25, 8),
      'renew licence on 15/1 at 11 am': fromWall(
        DateTime.utc(2027, 1, 15, 11),
        ist,
      ),
      'कल सुबह 7 बजे योग': at(11, 10, 7),
    };
    for (final MapEntry(key: input, value: expected) in cases.entries) {
      test(input, () {
        final i = one(input);
        expect(i.at, expected, reason: '$i');
        expect(i.allDay, isFalse);
      });
    }

    test('a passed time with no date rolls to tomorrow', () {
      expect(one('remind me to meditate at 9 am').at, at(11, 10, 9));
    });

    test('a date without a time is all-day', () {
      final i = one('renew car insurance tomorrow');
      expect(i.allDay, isTrue);
      expect(toWall(i.at!, ist), DateTime.utc(2026, 11, 10));
    });
  });

  group('titles and categories', () {
    test('strips filler, keeps the task', () {
      expect(
        one('remind me to pay the electricity bill at 10 pm').title,
        'Pay the electricity bill',
      );
      expect(
        one('kal subah 8 baje dawai lene ki yaad dilana').title,
        'Dawai lene',
      );
      expect(
        one('Hey Aria, please remind me to call Dad tomorrow at 7 pm').title,
        'Call dad',
      );
    });

    test('categorises by keywords', () {
      expect(one('take vitamin d at 8 pm').category, ReminderCategory.health);
      expect(
        one('pay rent on the 1st of every month').category,
        ReminderCategory.bills,
      );
      expect(one('call mom at 7 pm').category, ReminderCategory.people);
      expect(
        one('send report to client at 4 pm').category,
        ReminderCategory.work,
      );
      expect(
        one('call plumber at 4 pm').category,
        ReminderCategory.people,
        reason: '"call" wins — people first is fine',
      );
      expect(
        one('water the plants at 6 pm').category,
        ReminderCategory.health,
        reason: 'known ambiguity: "water"',
      );
      expect(one('clean the fridge at 6 pm').category, ReminderCategory.home);
    });
  });

  group('recurrence', () {
    test('daily / roz', () {
      final i = one('take vitamin d every day at 8 pm');
      expect(i.rrule, 'FREQ=DAILY');
      expect(i.at, at(11, 9, 20));
      expect(one('roz subah 7 baje paani peena').rrule, 'FREQ=DAILY');
    });

    test('daily time already passed today → starts tomorrow', () {
      expect(one('every day at 8 am vitamins').at, at(11, 10, 8));
    });

    test('every morning keeps the morning time', () {
      final i = one('remind me every morning to meditate');
      expect(i.rrule, 'FREQ=DAILY');
      expect(toWall(i.at!, ist).hour, 8);
    });

    test('weekdays', () {
      final i = one('standup every weekday at 9:30 am');
      expect(i.rrule, 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR');
      expect(i.at, at(11, 10, 9, 30));
    });

    test('specific weekdays', () {
      final i = one('gym every monday and thursday at 7 am');
      expect(i.rrule, 'FREQ=WEEKLY;BYDAY=MO,TH');
      expect(i.at, at(11, 12, 7), reason: 'Mon 7 AM has passed → Thu');
    });

    test('1st of every month', () {
      final i = one('pay rent on the 1st of every month at 10 am');
      expect(i.rrule, 'FREQ=MONTHLY;BYMONTHDAY=1');
      expect(i.at, at(12, 1, 10));
      expect(i.category, ReminderCategory.bills);
    });

    test('every month on the 5th / last day / every 2 weeks / yearly', () {
      expect(
        one('electricity bill every month on the 5th').rrule,
        'FREQ=MONTHLY;BYMONTHDAY=5',
      );
      expect(
        one('pay salary on last day of every month').rrule,
        'FREQ=MONTHLY;BYMONTHDAY=-1',
      );
      expect(
        one('water plants every 2 days at 6 pm').rrule,
        'FREQ=DAILY;INTERVAL=2',
      );
      expect(one('car service every year on 3 march').rrule, 'FREQ=YEARLY');
    });

    test('recurring without a time is all-day', () {
      final i = one('har mahine 10 tarikh ko sip');
      expect(i.rrule, 'FREQ=MONTHLY;BYMONTHDAY=10');
      expect(i.title, 'Sip');
      expect(i.allDay, isTrue);
      expect(toWall(i.at!, ist), DateTime.utc(2026, 11, 10));
    });
  });

  group('amounts and priority', () {
    test('rupees in several forms', () {
      expect(one('pay electricity bill ₹1,840 on the 5th').amount, 1840);
      expect(one('pay rs. 500 to the maid tomorrow').amount, 500);
      expect(one('pay 2500 rupees rent tomorrow').amount, 2500);
      expect(one('pay rs. 500 to the maid tomorrow').title, 'Pay to the maid');
    });

    test('priority', () {
      expect(one('urgent: call the bank at 4 pm').priority, Priority.urgent);
      expect(one('important meeting at 3 pm').priority, Priority.high);
      expect(one('buy bread at 6 pm').priority, Priority.normal);
    });
  });

  group('multiple reminders in one sentence', () {
    test('split on "and" when both halves have a time', () {
      final c = p('remind me to take medicine at 8 pm and call mom at 9 pm');
      expect(c.items.map((i) => i.title), ['Take medicine', 'Call mom']);
      expect(c.items.map((i) => i.at), [at(11, 9, 20), at(11, 9, 21)]);
    });

    test('"also" splits', () {
      expect(
        p('water plants at 6 pm, also pay rent tomorrow').items,
        hasLength(2),
      );
    });

    test('"and" inside a title is kept', () {
      expect(one('call mom and dad at 6 pm').title, 'Call mom and dad');
    });
  });

  group('clarification', () {
    test('no time at all asks when', () {
      final c = p('remind me to buy a gift');
      expect(c.items.single.at, isNull);
      expect(c.clarification, 'When should I remind you?');
    });

    test('empty input', () {
      expect(p('   ').clarification, isNotNull);
    });
  });

  group('commands', () {
    test('queries', () {
      expect(p("What's on today?").query, QueryKind.today);
      expect(p('aaj kya hai').query, QueryKind.today);
      expect(p('what did I miss').query, QueryKind.missed);
      final l = p("what was the plumber's number");
      expect(l.query, QueryKind.lookup);
      expect(l.items.single.title, "Plumber's number");
    });

    test('complete by name', () {
      final c = p('mark vitamin d done');
      expect(c.intent, ParseIntent.complete);
      expect(c.items.single.targetId, 'r-vit');
      expect(
        p('rent paid').intent,
        ParseIntent.createReminder,
        reason: 'not a completion phrase',
      );
      expect(p('I paid the rent').items.single.targetId, 'r-rent');
      expect(p('vitamin d le li').items.single.targetId, 'r-vit');
    });

    test('snooze the current one or a named one', () {
      final c = p('snooze 20 minutes');
      expect(c.intent, ParseIntent.snooze);
      expect(c.items.single.targetId, 'r-vit');
      expect(c.items.single.snoozeMinutes, 20);
      final n = p('snooze team meeting for 1 hour');
      expect(n.items.single.targetId, 'r-meet');
      expect(n.items.single.snoozeMinutes, 60);
    });

    test('delete and update', () {
      final d = p("cancel tomorrow's team meeting reminder");
      expect(d.intent, ParseIntent.delete);
      expect(d.items.single.targetId, 'r-meet');
      final u = p('move team meeting to 4 pm');
      expect(u.intent, ParseIntent.update);
      expect(u.items.single.targetId, 'r-meet');
      expect(u.items.single.at, at(11, 9, 16));
    });

    test('unknown target asks which one', () {
      final c = p('mark yoga done');
      expect(c.items, isEmpty);
      expect(c.clarification, contains('Yoga'));
    });

    test('list items and notes', () {
      final l = p('add milk, eggs and bread to grocery list');
      expect(l.intent, ParseIntent.createListItem);
      expect(l.items.map((i) => i.title), ['Milk', 'Eggs', 'Bread']);
      expect(l.items.first.listName, 'Grocery');
      final n = p('note that the wifi password is sunflower42');
      expect(n.intent, ParseIntent.createNote);
      expect(n.items.single.title, 'The wifi password is sunflower42');
    });
  });

  group('LLM JSON validation', () {
    Map<String, dynamic> item([Map<String, dynamic> over = const {}]) => {
      'title': 'Pay electricity bill',
      'category': 'bills',
      'datetime': '2026-12-05T10:00:00+05:30',
      'all_day': false,
      'recurrence': 'FREQ=MONTHLY;BYMONTHDAY=5',
      'priority': 'normal',
      'amount': 1840,
      'contact': null,
      'notes': null,
      'target_id': null,
      'snooze_minutes': null,
      'list_name': null,
      ...over,
    };
    Map<String, dynamic> body(
      List<Map<String, dynamic>> items, [
      String intent = 'create_reminder',
    ]) => {
      'intent': intent,
      'items': items,
      'query': 'none',
      'clarification_needed': null,
      'spoken_reply': 'Done!',
    };

    test('the spec example parses', () {
      final c = ParsedCommand.fromJson(body([item()]))!;
      expect(c.items.single.at, at(12, 5, 10));
      expect(c.items.single.amount, 1840);
      expect(c.source, ParseSource.llm);
    });

    test('rejects bad output (→ on-device fallback)', () {
      expect(
        ParsedCommand.fromJson(
          body([
            item({'datetime': 'tomorrow'}),
          ]),
        ),
        isNull,
      );
      expect(
        ParsedCommand.fromJson(
          body([
            item({'recurrence': 'FREQ=HOURLY'}),
          ]),
        ),
        isNull,
      );
      expect(
        ParsedCommand.fromJson(
          body([
            item({'category': 'food'}),
          ]),
        ),
        isNull,
      );
      expect(ParsedCommand.fromJson(body([item()], 'launch_rocket')), isNull);
      expect(
        ParsedCommand.fromJson(
          body([
            item({'title': ' '}),
          ]),
        ),
        isNull,
      );
      expect(ParsedCommand.fromJson({'nonsense': true}), isNull);
    });

    test('drops target ids we did not send', () {
      final c = ParsedCommand.fromJson(
        body([
          item({'target_id': 'someone-elses'}),
        ], 'complete'),
        knownIds: {'r-vit'},
      )!;
      expect(c.items.single.targetId, isNull);
    });
  });

  group('places', () {
    test('arrive and leave, English', () {
      for (final (said, title, place, on) in [
        (
          'remind me to buy milk when i leave work',
          'Buy milk',
          'work',
          PlaceTransition.leave,
        ),
        (
          'remind me to call mum when i get home',
          'Call mum',
          'home',
          PlaceTransition.arrive,
        ),
        (
          'remind me to take umbrella when I leave home',
          'Take umbrella',
          'home',
          PlaceTransition.leave,
        ),
        (
          'remind me to buy medicines when I reach the pharmacy',
          'Buy medicines',
          'pharmacy',
          PlaceTransition.arrive,
        ),
        (
          "remind me to switch off the geyser when i'm at the office",
          'Switch off the geyser',
          'office',
          PlaceTransition.arrive,
        ),
        (
          'remind me to pick up dry cleaning when i get to the market',
          'Pick up dry cleaning',
          'market',
          PlaceTransition.arrive,
        ),
      ]) {
        final c = p(said);
        final i = c.items.single;
        expect(
          [i.title, i.place, i.placeOn, i.at],
          [title, place, on, null],
          reason: said,
        );
        expect(c.clarification, isNull, reason: 'a place is enough: $said');
      }
    });

    test('Hinglish', () {
      final a = one('ghar pahunch kar mummy ko call karna yaad dilana');
      expect([a.place, a.placeOn], ['home', PlaceTransition.arrive]);
      final b = one('mujhe office se nikalte hi doodh lena hai');
      expect([b.place, b.placeOn], ['office', PlaceTransition.leave]);
    });

    test('a time without a place is unaffected', () {
      final i = one('remind me to call mum at 6 pm');
      expect([i.place, i.at], [null, at(11, 9, 18)]);
    });
  });
}
