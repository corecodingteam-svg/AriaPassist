import 'package:aria/features/reminders/domain/describe.dart';
import 'package:aria/features/reminders/domain/recurrence.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:intl/intl.dart';

/// Plain "when" for speech and cards: "tomorrow at 8:00 AM",
/// "every day at 8:30 AM", "on Fri 13 Nov", "today".
String describeWhen({
  required DateTime? at,
  required bool allDay,
  required String? rrule,
  required DateTime now,
  required String zone,
}) {
  if (at == null) return 'no time yet';
  final w = toWall(at, zone);
  final time = DateFormat.jm().format(w);
  final rule = RecurrenceRule.tryParse(rrule);
  if (rule != null) {
    final base = describeRule(rule, w);
    final lower = '${base[0].toLowerCase()}${base.substring(1)}';
    return allDay ? lower : '$lower at $time';
  }
  final today = toWall(now, zone);
  final d0 = DateTime.utc(today.year, today.month, today.day);
  final d1 = DateTime.utc(w.year, w.month, w.day);
  final day = switch (d1.difference(d0).inDays) {
    0 => 'today',
    1 => 'tomorrow',
    final n when n > 1 && n < 7 => 'on ${DateFormat('EEEE').format(w)}',
    _ => 'on ${DateFormat('EEE d MMM').format(w)}',
  };
  return allDay ? day : '$day at $time';
}
