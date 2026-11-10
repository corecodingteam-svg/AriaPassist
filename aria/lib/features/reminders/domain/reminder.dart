import 'package:aria/features/reminders/domain/recurrence.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/foundation.dart';

enum ReminderCategory {
  health('💊', 'Health'),
  bills('💰', 'Bills'),
  people('👪', 'People'),
  home('🏠', 'Home'),
  work('💼', 'Work'),
  personal('🎯', 'Personal');

  ReminderCategory(this.emoji, this._label);
  final String emoji;
  final String _label;
  String get label => tr(_label);

  static ReminderCategory parse(String? s) =>
      values.asNameMap()[s] ?? ReminderCategory.personal;
}

enum Priority {
  low('Low'),
  normal('Normal'),
  high('High'),
  urgent('Urgent');

  Priority(this._label);
  final String _label;
  String get label => tr(_label);

  static Priority parse(String? s) => values.asNameMap()[s] ?? Priority.normal;
}

enum ReminderStatus {
  active,
  done,
  missed,
  archived;

  static ReminderStatus parse(String? s) =>
      values.asNameMap()[s] ?? ReminderStatus.active;
}

/// How a reminder alerts. Voice arrives in Phase 3; until then voice/both
/// deliver as a text notification.
enum NotifyMode {
  voice,
  text,
  both,
  vibrate,
  silent;

  static NotifyMode? parse(String? s) => values.asNameMap()[s];
}

@immutable
class FollowUp {
  const FollowUp({
    this.enabled = true,
    this.everyMin = 10,
    this.maxAttempts = 3,
  });

  factory FollowUp.fromJson(Map<String, dynamic>? j) => j == null
      ? const FollowUp()
      : FollowUp(
          enabled: j['enabled'] as bool? ?? true,
          everyMin: (j['every_min'] as num?)?.toInt() ?? 10,
          maxAttempts: (j['max_attempts'] as num?)?.toInt() ?? 3,
        );

  static const off = FollowUp(enabled: false);

  final bool enabled;
  final int everyMin;
  final int maxAttempts;

  FollowUp copyWithEnabled() =>
      FollowUp(everyMin: everyMin, maxAttempts: maxAttempts);

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'every_min': everyMin,
    'max_attempts': maxAttempts,
  };

  /// How long after the due time a reminder counts as missed.
  Duration get missedAfter => enabled
      ? Duration(minutes: everyMin * (maxAttempts + 1))
      : const Duration(hours: 1);

  @override
  bool operator ==(Object other) =>
      other is FollowUp &&
      other.enabled == enabled &&
      other.everyMin == everyMin &&
      other.maxAttempts == maxAttempts;
  @override
  int get hashCode => Object.hash(enabled, everyMin, maxAttempts);
}

enum PlaceTransition {
  arrive('when I arrive at'),
  leave('when I leave');

  PlaceTransition(this._phrase);
  final String _phrase;
  String get phrase => tr(_phrase);
}

/// "Remind me when I get home": a geofence around a saved place.
@immutable
class LocationTrigger {
  const LocationTrigger({
    required this.placeName,
    required this.lat,
    required this.lng,
    this.placeId,
    this.radiusM = 150,
    this.on = PlaceTransition.arrive,
  });

  static LocationTrigger? fromJson(Map<String, dynamic>? j) {
    if (j == null || j['lat'] is! num || j['lng'] is! num) return null;
    return LocationTrigger(
      placeId: j['place_id'] as String?,
      placeName: j['place'] as String? ?? tr('a place'),
      lat: (j['lat'] as num).toDouble(),
      lng: (j['lng'] as num).toDouble(),
      radiusM: (j['radius_m'] as num?)?.toInt() ?? 150,
      on: j['on'] == 'leave' ? PlaceTransition.leave : PlaceTransition.arrive,
    );
  }

  final String? placeId;
  final String placeName;
  final double lat;
  final double lng;
  final int radiusM;
  final PlaceTransition on;

  /// "When I arrive at Home".
  String describe() => on == PlaceTransition.arrive
      ? tr('When I arrive at {0}', [placeName])
      : tr('When I leave {0}', [placeName]);

  Map<String, dynamic> toJson() => {
    'place_id': placeId,
    'place': placeName,
    'lat': lat,
    'lng': lng,
    'radius_m': radiusM,
    'on': on.name,
  };

  @override
  bool operator ==(Object other) =>
      other is LocationTrigger &&
      other.lat == lat &&
      other.lng == lng &&
      other.radiusM == radiusM &&
      other.on == on &&
      other.placeName == placeName;
  @override
  int get hashCode => Object.hash(lat, lng, radiusM, on, placeName);
}

/// A reminder. For recurring reminders [startAt] is always the **next
/// pending occurrence** (the series anchor advances on done / missed), so
/// "when is it due" is simply `snoozedUntil ?? startAt`.
@immutable
class Reminder {
  const Reminder({
    required this.id,
    required this.circleId,
    required this.createdBy,
    required this.title,
    this.assignedTo,
    this.category = ReminderCategory.personal,
    this.priority = Priority.normal,
    this.startAt,
    this.allDay = false,
    this.rrule,
    this.timezone,
    this.notifyMode,
    this.followUp = const FollowUp(),
    this.amount,
    this.notes,
    this.contact,
    this.location,
    this.visibility = 'private',
    this.status = ReminderStatus.active,
    this.snoozedUntil,
    this.lastDoneAt,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String circleId;
  final String createdBy;
  final String? assignedTo;
  final String title;
  final ReminderCategory category;
  final Priority priority;

  /// UTC instant of the next (pending) occurrence; null = no time ("someday").
  final DateTime? startAt;
  final bool allDay;
  final String? rrule;

  /// IANA zone whose wall clock the recurrence follows (e.g. Asia/Kolkata).
  final String? timezone;
  final NotifyMode? notifyMode;
  final FollowUp followUp;
  final double? amount;
  final String? notes;

  /// Linked person: {person_id, name, phone, occasion?, keep_in_touch?}.
  final Map<String, dynamic>? contact;

  /// Fires on arriving at / leaving a place instead of (or as well as) a time.
  final LocationTrigger? location;
  final String visibility;
  final ReminderStatus status;
  final DateTime? snoozedUntil;
  final DateTime? lastDoneAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  RecurrenceRule? get rule => RecurrenceRule.tryParse(rrule);
  bool get isRecurring => rule != null;
  bool get isActive => status == ReminderStatus.active && deletedAt == null;

  /// "Call Dad every 14 days": the next nudge counts from when you called.
  bool get keepInTouch => contact?['keep_in_touch'] == true;
  String? get personId => contact?['person_id'] as String?;
  String? get contactPhone => contact?['phone'] as String?;

  /// When it should next alert.
  DateTime? get dueAt => snoozedUntil ?? startAt;

  /// Whose phone alerts: the assignee, or the creator if unassigned.
  String get owner => assignedTo ?? createdBy;

  Reminder copyWith({
    String? title,
    ReminderCategory? category,
    Priority? priority,
    DateTime? Function()? startAt,
    bool? allDay,
    String? Function()? rrule,
    String? timezone,
    NotifyMode? Function()? notifyMode,
    FollowUp? followUp,
    double? Function()? amount,
    String? Function()? notes,
    Map<String, dynamic>? Function()? contact,
    LocationTrigger? Function()? location,
    String? Function()? assignedTo,
    String? visibility,
    ReminderStatus? status,
    DateTime? Function()? snoozedUntil,
    DateTime? Function()? lastDoneAt,
    DateTime? Function()? deletedAt,
  }) => Reminder(
    id: id,
    circleId: circleId,
    createdBy: createdBy,
    assignedTo: assignedTo != null ? assignedTo() : this.assignedTo,
    title: title ?? this.title,
    category: category ?? this.category,
    priority: priority ?? this.priority,
    startAt: startAt != null ? startAt() : this.startAt,
    allDay: allDay ?? this.allDay,
    rrule: rrule != null ? rrule() : this.rrule,
    timezone: timezone ?? this.timezone,
    notifyMode: notifyMode != null ? notifyMode() : this.notifyMode,
    followUp: followUp ?? this.followUp,
    amount: amount != null ? amount() : this.amount,
    notes: notes != null ? notes() : this.notes,
    contact: contact != null ? contact() : this.contact,
    location: location != null ? location() : this.location,
    visibility: visibility ?? this.visibility,
    status: status ?? this.status,
    snoozedUntil: snoozedUntil != null ? snoozedUntil() : this.snoozedUntil,
    lastDoneAt: lastDoneAt != null ? lastDoneAt() : this.lastDoneAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
  );

  /// Row for `LocalStore.write` (Postgres column names).
  Map<String, dynamic> toRow() => {
    'id': id,
    'circle_id': circleId,
    'created_by': createdBy,
    'assigned_to': assignedTo,
    'title': title,
    'category': category.name,
    'priority': priority.name,
    'start_at': startAt?.toUtc().toIso8601String(),
    'all_day': allDay,
    'rrule': rrule,
    'timezone': timezone,
    'notify_mode': notifyMode?.name,
    'follow_up_json': followUp.toJson(),
    'amount': amount,
    'notes': notes,
    'contact_json': contact,
    'location_json': location?.toJson(),
    'visibility': visibility,
    'status': status.name,
    'snoozed_until': snoozedUntil?.toUtc().toIso8601String(),
    'last_done_at': lastDoneAt?.toUtc().toIso8601String(),
    'created_at': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.id == id &&
      other.updatedAt == updatedAt &&
      other.title == title &&
      other.status == status &&
      other.startAt == startAt &&
      other.snoozedUntil == snoozedUntil &&
      other.location == location &&
      other.deletedAt == deletedAt;
  @override
  int get hashCode => Object.hash(id, updatedAt, status, startAt, snoozedUntil);
}

enum ReminderEventType { fired, done, snoozed, missed }

@immutable
class ReminderEvent {
  const ReminderEvent({
    required this.id,
    required this.reminderId,
    required this.userId,
    required this.type,
    required this.at,
    this.occurrenceAt,
    this.resolved = false,
  });

  final String id;
  final String reminderId;
  final String userId;
  final ReminderEventType type;
  final DateTime at;

  /// The occurrence this event is about (for recurring reminders).
  final DateTime? occurrenceAt;

  /// Missed events: true once the user dealt with it from the Missed list.
  final bool resolved;

  Map<String, dynamic> toRow() => {
    'id': id,
    'reminder_id': reminderId,
    'user_id': userId,
    'type': type.name,
    'at': at.toUtc().toIso8601String(),
    'occurrence_at': occurrenceAt?.toUtc().toIso8601String(),
    'meta_json': {'resolved': resolved},
    'deleted_at': null,
  };
}
