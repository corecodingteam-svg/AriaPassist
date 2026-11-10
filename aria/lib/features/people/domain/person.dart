import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

@immutable
class Person {
  const Person({
    required this.id,
    required this.circleId,
    required this.createdBy,
    required this.name,
    this.relation,
    this.phone,
    this.birthday,
    this.anniversary,
    this.callEveryDays,
    this.lastContactAt,
    this.visibility = 'private',
  });

  factory Person.fromFields({
    required String id,
    required String circleId,
    required String createdBy,
    required String name,
    String? relation,
    String? phone,
    String? birthday,
    String? anniversary,
    int? callEveryDays,
    DateTime? lastContactAt,
    String visibility = 'private',
  }) => Person(
    id: id,
    circleId: circleId,
    createdBy: createdBy,
    name: name,
    relation: relation,
    phone: phone,
    birthday: _p(birthday),
    anniversary: _p(anniversary),
    callEveryDays: callEveryDays,
    lastContactAt: lastContactAt,
    visibility: visibility,
  );

  final String id;
  final String circleId;
  final String createdBy;
  final String name;
  final String? relation;

  /// Digits with country code if known (e.g. 919876543210).
  final String? phone;

  /// Month/day matter; the year may be a placeholder (2000) when unknown.
  final DateTime? birthday;
  final DateTime? anniversary;

  /// "Call Dad every 14 days" (null = no nudges).
  final int? callEveryDays;
  final DateTime? lastContactAt;
  final String visibility;

  static String _d(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  static DateTime? _p(String? s) => s == null ? null : DateTime.tryParse(s);

  Map<String, dynamic> toRow() => {
    'id': id,
    'circle_id': circleId,
    'created_by': createdBy,
    'name': name,
    'relation': relation,
    'phone': phone,
    'birthday': birthday == null ? null : _d(birthday!),
    'anniversary': anniversary == null ? null : _d(anniversary!),
    'call_every_days': callEveryDays,
    'last_contact_at': lastContactAt?.toUtc().toIso8601String(),
    'visibility': visibility,
  };

  Person copyWith({
    String? name,
    String? Function()? relation,
    String? Function()? phone,
    DateTime? Function()? birthday,
    DateTime? Function()? anniversary,
    int? Function()? callEveryDays,
    DateTime? Function()? lastContactAt,
    String? visibility,
  }) => Person(
    id: id,
    circleId: circleId,
    createdBy: createdBy,
    name: name ?? this.name,
    relation: relation != null ? relation() : this.relation,
    phone: phone != null ? phone() : this.phone,
    birthday: birthday != null ? birthday() : this.birthday,
    anniversary: anniversary != null ? anniversary() : this.anniversary,
    callEveryDays: callEveryDays != null ? callEveryDays() : this.callEveryDays,
    lastContactAt: lastContactAt != null ? lastContactAt() : this.lastContactAt,
    visibility: visibility ?? this.visibility,
  );

  /// Days since you last called (null if never recorded).
  int? daysSinceContact(DateTime now) =>
      lastContactAt == null ? null : now.difference(lastContactAt!).inDays;

  /// Overdue for a call?
  bool dueForCall(DateTime now) {
    if (callEveryDays == null) return false;
    final since = daysSinceContact(now);
    return since == null || since >= callEveryDays!;
  }

  /// Next birthday/anniversary on or after [today] (date-only, local).
  static DateTime? nextOccurrence(DateTime? date, DateTime today) {
    if (date == null) return null;
    var d = DateTime(today.year, date.month, date.day);
    if (d.month != date.month) d = DateTime(today.year, 3); // 29 Feb → 1 Mar
    if (d.isBefore(DateTime(today.year, today.month, today.day))) {
      d = DateTime(today.year + 1, date.month, date.day);
    }
    return d;
  }

  // -------------------------------------------------------- one-tap actions

  String? get _intl {
    final p = phone?.replaceAll(RegExp(r'[^\d]'), '');
    if (p == null || p.isEmpty) return null;
    return p.length == 10 ? '91$p' : p; // Indian mobile without country code
  }

  Uri? get callUri =>
      _intl == null ? null : Uri(scheme: 'tel', path: '+$_intl');
  Uri? smsUri(String text) => _intl == null
      ? null
      : Uri(scheme: 'sms', path: '+$_intl', queryParameters: {'body': text});
  Uri? whatsappUri(String text) =>
      _intl == null ? null : Uri.https('wa.me', '/$_intl', {'text': text});

  /// Pre-filled wish for today's occasion.
  String wish({required bool birthday}) => birthday
      ? 'Happy birthday, $name! 🎂 Wishing you a wonderful year ahead.'
      : 'Happy anniversary! 💐 Wishing you both lots of love.';
}
