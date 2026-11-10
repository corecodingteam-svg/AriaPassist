import 'package:aria/features/preferences/application/prefs_scope.dart';
import 'package:aria/features/preferences/domain/app_prefs.dart';
import 'package:aria/features/reminders/domain/describe.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

final rupees = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

/// Short date per Settings › Date format ("Mon 9 Nov", "Mon, Nov 9", "09/11/2026").
String formatDate(BuildContext context, DateTime wall) =>
    switch (PrefsScope.of(context).dateStyle) {
      DateStyle.dayMonth => DateFormat('EEE d MMM').format(wall),
      DateStyle.monthDay => DateFormat('EEE, MMM d').format(wall),
      DateStyle.numeric => DateFormat('dd/MM/yyyy').format(wall),
    };

/// Time of day in the device zone, honouring the 24-hour setting.
String formatTime(BuildContext context, DateTime instant, String zone) {
  final w = toWall(instant, zone);
  return MediaQuery.alwaysUse24HourFormatOf(context)
      ? DateFormat.Hm().format(w)
      : DateFormat.jm().format(w);
}

/// "Today 8:30 AM", "Tomorrow 9:00 AM", "Mon 16 Nov, 9:00 AM".
String formatWhen(
  BuildContext context,
  DateTime instant,
  String zone, {
  required DateTime now,
  bool allDay = false,
}) {
  final w = toWall(instant, zone);
  final today = toWall(now, zone);
  final d0 = DateTime.utc(today.year, today.month, today.day);
  final d1 = DateTime.utc(w.year, w.month, w.day);
  final diff = d1.difference(d0).inDays;
  final day = switch (diff) {
    0 => tr('Today'),
    1 => tr('Tomorrow'),
    -1 => tr('Yesterday'),
    _ when diff > 1 && diff < 7 => DateFormat('EEEE').format(w),
    _ => formatDate(context, w),
  };
  if (allDay) return tr('{0} · anytime', [day]);
  return '$day, ${formatTime(context, instant, zone)}';
}

/// Secondary line on a reminder tile.
String subtitleFor(
  BuildContext context,
  Reminder r,
  String zone, {
  required DateTime now,
}) {
  final rule = r.rule;
  final parts = <String>[
    if (r.location != null) r.location!.describe(),
    if (r.snoozedUntil != null)
      tr('Snoozed until {0}', [formatTime(context, r.snoozedUntil!, zone)]),
    if (rule != null && r.startAt != null)
      describeRule(rule, toWall(r.startAt!, r.timezone ?? zone)),
    if (r.amount != null) rupees.format(r.amount),
    if (r.priority == Priority.urgent) tr('Urgent'),
    if (r.priority == Priority.high) tr('High priority'),
  ];
  return parts.join(' · ');
}
