import 'package:aria/features/reminders/domain/describe.dart';
import 'package:aria/features/reminders/domain/recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime w(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min);

List<DateTime> take(String rule, DateTime anchor, int n, [DateTime? from]) =>
    RecurrenceRule.tryParse(rule)!.occurrencesFrom(anchor, from ?? anchor, n);

void main() {
  group('parse / format', () {
    test('round-trips supported rules', () {
      for (final s in [
        'FREQ=DAILY',
        'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
        'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH',
        'FREQ=MONTHLY;BYMONTHDAY=5',
        'FREQ=MONTHLY;BYMONTHDAY=-1',
        'FREQ=YEARLY',
        'FREQ=DAILY;COUNT=10',
        'FREQ=DAILY;UNTIL=20261231T235959Z',
      ]) {
        expect(RecurrenceRule.tryParse(s).toString(), s, reason: s);
      }
    });

    test('accepts RRULE: prefix, lowercase, any order', () {
      expect(
        RecurrenceRule.tryParse('rrule:bymonthday=1;freq=monthly').toString(),
        'FREQ=MONTHLY;BYMONTHDAY=1',
      );
    });

    test('rejects unsupported or invalid rules', () {
      for (final s in [
        '',
        'FREQ=HOURLY',
        'FREQ=MONTHLY;BYDAY=2MO', // ordinal weekday
        'FREQ=WEEKLY;BYDAY=XX',
        'FREQ=DAILY;BYSETPOS=1',
        'FREQ=DAILY;INTERVAL=0',
        'FREQ=DAILY;COUNT=2;UNTIL=20270101',
        'FREQ=DAILY;BYMONTHDAY=3', // BYMONTHDAY only with MONTHLY
        'garbage',
      ]) {
        expect(RecurrenceRule.tryParse(s), isNull, reason: s);
      }
    });
  });

  group('expansion', () {
    test('daily keeps wall-clock time', () {
      expect(take('FREQ=DAILY', w(2026, 11, 8, 8, 30), 3), [
        w(2026, 11, 8, 8, 30),
        w(2026, 11, 9, 8, 30),
        w(2026, 11, 10, 8, 30),
      ]);
    });

    test('every 3 days', () {
      expect(take('FREQ=DAILY;INTERVAL=3', w(2026, 11, 8, 7), 3), [
        w(2026, 11, 8, 7),
        w(2026, 11, 11, 7),
        w(2026, 11, 14, 7),
      ]);
    });

    test('weekdays from a Friday skip the weekend', () {
      // 13 Nov 2026 is a Friday.
      expect(take('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR', w(2026, 11, 13, 9), 3), [
        w(2026, 11, 13, 9),
        w(2026, 11, 16, 9),
        w(2026, 11, 17, 9),
      ]);
    });

    test('every 2 weeks on Mon & Thu', () {
      // Anchor Monday 9 Nov 2026.
      expect(take('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH', w(2026, 11, 9, 9), 4), [
        w(2026, 11, 9, 9),
        w(2026, 11, 12, 9),
        w(2026, 11, 23, 9),
        w(2026, 11, 26, 9),
      ]);
    });

    test('weekly without BYDAY uses the anchor weekday', () {
      expect(take('FREQ=WEEKLY', w(2026, 11, 11, 18), 2), [
        w(2026, 11, 11, 18),
        w(2026, 11, 18, 18),
      ]);
    });

    test('monthly on the 31st skips short months (RFC 5545)', () {
      expect(take('FREQ=MONTHLY', w(2027, 1, 31, 10), 3), [
        w(2027, 1, 31, 10),
        w(2027, 3, 31, 10),
        w(2027, 5, 31, 10),
      ]);
    });

    test('monthly on the last day', () {
      expect(take('FREQ=MONTHLY;BYMONTHDAY=-1', w(2027, 1, 31, 10), 3), [
        w(2027, 1, 31, 10),
        w(2027, 2, 28, 10),
        w(2027, 3, 31, 10),
      ]);
    });

    test('monthly bill on the 5th across a year boundary', () {
      expect(take('FREQ=MONTHLY;BYMONTHDAY=5', w(2026, 12, 5, 10), 2), [
        w(2026, 12, 5, 10),
        w(2027, 1, 5, 10),
      ]);
    });

    test('yearly birthday on 29 Feb only in leap years', () {
      expect(take('FREQ=YEARLY', w(2028, 2, 29, 9), 2), [
        w(2028, 2, 29, 9),
        w(2032, 2, 29, 9),
      ]);
    });

    test('COUNT limits occurrences, counting from the anchor', () {
      expect(take('FREQ=DAILY;COUNT=2', w(2026, 11, 8, 8), 5), hasLength(2));
    });

    test('UNTIL is inclusive', () {
      expect(
        take('FREQ=DAILY;UNTIL=20261110T080000Z', w(2026, 11, 8, 8), 9),
        hasLength(3),
      );
    });

    test('nextAfter fast-forwards years ahead without iterating', () {
      final r = RecurrenceRule.tryParse('FREQ=DAILY')!;
      final sw = Stopwatch()..start();
      final next = r.nextAfter(w(2020, 1, 1, 8), w(2030, 6, 15, 9));
      expect(next, w(2030, 6, 16, 8));
      expect(sw.elapsedMilliseconds, lessThan(50));
    });

    test('afterConsumingOne decrements COUNT and ends at 1', () {
      final r = RecurrenceRule.tryParse('FREQ=DAILY;COUNT=2')!;
      expect(r.afterConsumingOne()!.count, 1);
      expect(r.afterConsumingOne()!.afterConsumingOne(), isNull);
      expect(RecurrenceRule.daily.afterConsumingOne(), RecurrenceRule.daily);
    });
  });

  group('describe', () {
    String d(String r, [DateTime? a]) =>
        describeRule(RecurrenceRule.tryParse(r)!, a ?? w(2026, 12, 5, 10));

    test('plain language', () {
      expect(d('FREQ=DAILY'), 'Every day');
      expect(d('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR'), 'Weekdays');
      expect(
        d('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH'),
        'Every 2 weeks on Mon, Thu',
      );
      expect(d('FREQ=MONTHLY;BYMONTHDAY=5'), 'Every month on the 5th');
      expect(d('FREQ=MONTHLY;BYMONTHDAY=-1'), 'Every month on the last day');
      expect(d('FREQ=YEARLY'), 'Every year on 5 Dec');
      expect(d('FREQ=DAILY;COUNT=3'), 'Every day · 3 more times');
    });

    test('ordinals', () {
      expect(
        [1, 2, 3, 4, 11, 12, 13, 21, 22, 23].map(ordinal).join(' '),
        '1st 2nd 3rd 4th 11th 12th 13th 21st 22nd 23rd',
      );
    });
  });
}
