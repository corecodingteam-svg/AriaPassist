import 'package:flutter/foundation.dart';

/// Supported RFC 5545 subset:
///   FREQ=DAILY|WEEKLY|MONTHLY|YEARLY; INTERVAL; BYDAY (weekly, plain days);
///   BYMONTHDAY (monthly, 1..31 or -1..-31); COUNT; UNTIL.
///
/// Everything else (BYSETPOS, ordinal BYDAY like 2MO, BYHOUR…) is rejected
/// by [RecurrenceRule.tryParse] so the LLM parser (Phase 3) and the editor
/// can only produce rules this engine computes correctly.
///
/// All maths is in **wall-clock** time: callers pass naive DateTimes whose
/// fields are local to the reminder's timezone (we use `DateTime.utc` as a
/// DST-free container). Conversion to instants happens in `tz_utils.dart`.
enum Freq { daily, weekly, monthly, yearly }

@immutable
class RecurrenceRule {
  const RecurrenceRule({
    required this.freq,
    this.interval = 1,
    this.byDay = const {},
    this.byMonthDay = const [],
    this.count,
    this.until,
  });

  static const daily = RecurrenceRule(freq: Freq.daily);
  static const weekdays = RecurrenceRule(
    freq: Freq.weekly,
    byDay: {
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    },
  );
  static const weekly = RecurrenceRule(freq: Freq.weekly);
  static const monthly = RecurrenceRule(freq: Freq.monthly);
  static const yearly = RecurrenceRule(freq: Freq.yearly);

  final Freq freq;
  final int interval;

  /// ISO weekdays (DateTime.monday = 1 … sunday = 7). Weekly only.
  final Set<int> byDay;

  /// Days of month; negative counts from the end (-1 = last day).
  final List<int> byMonthDay;

  /// Remaining occurrences *including* the anchor. Decremented as the
  /// reminder advances, so the anchor is always the next pending one.
  final int? count;

  /// Inclusive end, wall-clock.
  final DateTime? until;

  static const _days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

  static RecurrenceRule? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final s = raw.trim().toUpperCase().replaceFirst(RegExp('^RRULE:'), '');
    final parts = <String, String>{};
    for (final p in s.split(';')) {
      if (p.isEmpty) continue;
      final kv = p.split('=');
      if (kv.length != 2) return null;
      parts[kv[0]] = kv[1];
    }
    const allowed = {
      'FREQ',
      'INTERVAL',
      'BYDAY',
      'BYMONTHDAY',
      'COUNT',
      'UNTIL',
      'WKST',
    };
    if (parts.keys.any((k) => !allowed.contains(k))) return null;
    if (parts['WKST'] != null && parts['WKST'] != 'MO') return null;

    final freq = switch (parts['FREQ']) {
      'DAILY' => Freq.daily,
      'WEEKLY' => Freq.weekly,
      'MONTHLY' => Freq.monthly,
      'YEARLY' => Freq.yearly,
      _ => null,
    };
    if (freq == null) return null;

    final interval = int.tryParse(parts['INTERVAL'] ?? '1');
    if (interval == null || interval < 1 || interval > 999) return null;

    final byDay = <int>{};
    if (parts['BYDAY'] != null) {
      if (freq != Freq.weekly) return null;
      for (final d in parts['BYDAY']!.split(',')) {
        final i = _days.indexOf(d);
        if (i < 0) return null; // ordinals like 2MO unsupported
        byDay.add(i + 1);
      }
    }

    final byMonthDay = <int>[];
    if (parts['BYMONTHDAY'] != null) {
      if (freq != Freq.monthly) return null;
      for (final d in parts['BYMONTHDAY']!.split(',')) {
        final n = int.tryParse(d);
        if (n == null || n == 0 || n.abs() > 31) return null;
        byMonthDay.add(n);
      }
      byMonthDay.sort();
    }

    int? count;
    if (parts['COUNT'] != null) {
      count = int.tryParse(parts['COUNT']!);
      if (count == null || count < 1) return null;
    }
    DateTime? until;
    if (parts['UNTIL'] != null) {
      until = _parseUntil(parts['UNTIL']!);
      if (until == null) return null;
    }
    if (count != null && until != null) return null; // RFC: mutually exclusive

    return RecurrenceRule(
      freq: freq,
      interval: interval,
      byDay: byDay,
      byMonthDay: byMonthDay,
      count: count,
      until: until,
    );
  }

  static DateTime? _parseUntil(String v) {
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})Z?)?$')
        .firstMatch(v);
    if (m == null) return null;
    int g(int i) => int.parse(m.group(i) ?? '0');
    return m.group(4) == null
        ? DateTime.utc(g(1), g(2), g(3), 23, 59, 59)
        : DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6));
  }

  @override
  String toString() {
    final b = StringBuffer('FREQ=${freq.name.toUpperCase()}');
    if (interval != 1) b.write(';INTERVAL=$interval');
    if (byDay.isNotEmpty) {
      final days = byDay.toList()..sort();
      b.write(';BYDAY=${days.map((d) => _days[d - 1]).join(',')}');
    }
    if (byMonthDay.isNotEmpty) b.write(';BYMONTHDAY=${byMonthDay.join(',')}');
    if (count != null) b.write(';COUNT=$count');
    if (until != null) {
      final u = until!;
      String p(int n, [int w = 2]) => n.toString().padLeft(w, '0');
      b.write(
        ';UNTIL=${p(u.year, 4)}${p(u.month)}${p(u.day)}'
        'T${p(u.hour)}${p(u.minute)}${p(u.second)}Z',
      );
    }
    return b.toString();
  }

  RecurrenceRule copyWith({int? Function()? count}) => RecurrenceRule(
    freq: freq,
    interval: interval,
    byDay: byDay,
    byMonthDay: byMonthDay,
    count: count != null ? count() : this.count,
    until: until,
  );

  // ------------------------------------------------------------- expansion

  /// First occurrence strictly after [after], for a series anchored at
  /// [anchor] (the anchor itself is occurrence #1). Null when finished.
  DateTime? nextAfter(DateTime anchor, DateTime after) {
    var remaining = count;
    // Without COUNT we can fast-forward to the period containing [after].
    final start = remaining == null ? _periodIndexNear(anchor, after) : 0;
    for (var period = start; period < start + 5000; period++) {
      for (final occ in _occurrencesInPeriod(anchor, period)) {
        if (occ.isBefore(anchor)) continue;
        if (until != null && occ.isAfter(until!)) return null;
        if (remaining != null) {
          if (remaining == 0) return null;
          remaining--;
        }
        if (occ.isAfter(after)) return occ;
      }
    }
    return null;
  }

  /// Up to [limit] occurrences ≥ [from] (inclusive), anchored at [anchor].
  List<DateTime> occurrencesFrom(DateTime anchor, DateTime from, int limit) {
    final out = <DateTime>[];
    var cursor = from.subtract(const Duration(microseconds: 1));
    while (out.length < limit) {
      final n = nextAfter(anchor, cursor);
      if (n == null) break;
      out.add(n);
      cursor = n;
    }
    return out;
  }

  /// The rule for the series after the anchor occurrence is consumed.
  /// Returns null when no occurrences remain (COUNT exhausted).
  RecurrenceRule? afterConsumingOne() {
    if (count == null) return this;
    if (count! <= 1) return null;
    return copyWith(count: () => count! - 1);
  }

  int _periodIndexNear(DateTime anchor, DateTime after) {
    if (!after.isAfter(anchor)) return 0;
    final raw = switch (freq) {
      Freq.daily => _daysBetween(anchor, after),
      Freq.weekly => _daysBetween(_weekStart(anchor), after) ~/ 7,
      Freq.monthly =>
        (after.year - anchor.year) * 12 + after.month - anchor.month,
      Freq.yearly => after.year - anchor.year,
    };
    // Step back one period for safety; iteration skips the rest.
    return raw ~/ interval > 0 ? raw ~/ interval - 1 : 0;
  }

  Iterable<DateTime> _occurrencesInPeriod(DateTime a, int period) sync* {
    final n = period * interval;
    switch (freq) {
      case Freq.daily:
        yield _at(a.year, a.month, a.day + n, a);
      case Freq.weekly:
        final ws = _weekStart(a);
        final days = byDay.isEmpty ? {a.weekday} : byDay;
        for (final d in days.toList()..sort()) {
          yield _at(ws.year, ws.month, ws.day + n * 7 + d - 1, a);
        }
      case Freq.monthly:
        final y = a.year + (a.month - 1 + n) ~/ 12;
        final m = (a.month - 1 + n) % 12 + 1;
        final dim = _daysInMonth(y, m);
        final days =
            (byMonthDay.isEmpty ? [a.day] : byMonthDay)
                .map((d) => d < 0 ? dim + d + 1 : d)
                .where((d) => d >= 1 && d <= dim) // RFC: skip invalid dates
                .toSet()
                .toList()
              ..sort();
        for (final d in days) {
          yield _at(y, m, d, a);
        }
      case Freq.yearly:
        final y = a.year + n;
        if (a.day <= _daysInMonth(y, a.month)) yield _at(y, a.month, a.day, a);
    }
  }

  static DateTime _at(int y, int m, int d, DateTime time) =>
      DateTime.utc(y, m, d, time.hour, time.minute, time.second);

  static DateTime _weekStart(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day - (d.weekday - 1));

  static int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  static int _daysInMonth(int y, int m) => DateTime.utc(y, m + 1, 0).day;

  @override
  bool operator ==(Object other) =>
      other is RecurrenceRule && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;
}
