import 'package:intl/intl.dart';

final _inr = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);
final _num = NumberFormat.decimalPattern('en_IN');

String rupees(Object? v) =>
    v == null ? '—' : _inr.format(num.tryParse('$v') ?? 0);
String count(Object? v) =>
    v == null ? '—' : _num.format(num.tryParse('$v') ?? 0);

DateTime? parseDate(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

String date(Object? v) {
  final d = parseDate(v);
  return d == null ? '—' : DateFormat('d MMM yyyy').format(d);
}

String dateTime(Object? v) {
  final d = parseDate(v);
  return d == null ? '—' : DateFormat('d MMM yyyy, HH:mm').format(d);
}

/// "in 3 days" / "2 days ago" / "today".
String relative(Object? v, {DateTime? now}) {
  final d = parseDate(v);
  if (d == null) return '—';
  final days = d.difference(now ?? DateTime.now()).inHours / 24;
  if (days.abs() < 1) return 'today';
  final n = days.abs().round();
  return days > 0
      ? 'in $n day${n == 1 ? '' : 's'}'
      : '$n day${n == 1 ? '' : 's'} ago';
}

/// Server error → readable text (uses the function's message/hint).
String friendlyError(Object e) {
  final s = e.toString();
  final m = RegExp('message: ([^,]+)').firstMatch(s);
  final msg = m?.group(1) ?? s;
  if (s.contains('mfa_required') || s.contains('two-factor')) {
    return 'Two-factor sign-in is required.';
  }
  if (s.contains('42501')) return 'You don’t have permission for this.';
  return msg.length > 160 ? '${msg.substring(0, 160)}…' : msg;
}
