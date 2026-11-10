import 'package:aria/features/reminders/domain/recurrence.dart';
import 'package:aria/l10n/tr.dart';
import 'package:intl/intl.dart';

const _dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String ordinal(int n) {
  if (n < 0) return n == -1 ? 'last day' : tr('{0}-last day', [ordinal(-n)]);
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

/// Plain-language description: "Every day", "Weekdays", "Every 2 weeks on
/// Mon, Thu", "Every month on the 5th", "Every year on 5 Dec".
String describeRule(RecurrenceRule r, DateTime anchor) {
  final every = r.interval == 1
      ? null
      : '${r.interval} ${switch (r.freq) {
          Freq.daily => 'days',
          Freq.weekly => 'weeks',
          Freq.monthly => 'months',
          Freq.yearly => 'years',
        }}';
  final base = switch (r.freq) {
    Freq.daily => every == null ? 'Every day' : tr('Every {0}', [every]),
    Freq.weekly => () {
      final days = (r.byDay.isEmpty ? {anchor.weekday} : r.byDay).toList()
        ..sort();
      if (every == null && days.length == 5 && days.last == 5) {
        return tr('Weekdays');
      }
      if (every == null && days.length == 7) return tr('Every day');
      final names = days.map((d) => _dayShort[d - 1]).join(', ');
      return every == null
          ? 'Every $names'
          : tr('Every {0} on {1}', [every, names]);
    }(),
    Freq.monthly => () {
      final days = r.byMonthDay.isEmpty ? [anchor.day] : r.byMonthDay;
      final names = days.map(ordinal).join(' & ');
      return every == null
          ? tr('Every month on the {0}', [names])
          : tr('Every {0} on the {1}', [every, names]);
    }(),
    Freq.yearly =>
      every == null
          ? tr('Every year on {0}', [DateFormat('d MMM').format(anchor)])
          : tr('Every {0} on {1}', [every, DateFormat('d MMM').format(anchor)]),
  };
  if (r.count != null) {
    return tr('{0} · {1} more time{2}', [
      base,
      r.count,
      r.count == 1 ? '' : 's',
    ]);
  }
  if (r.until != null) {
    return tr('{0} · until {1}', [
      base,
      DateFormat('d MMM y').format(r.until!),
    ]);
  }
  return base;
}
