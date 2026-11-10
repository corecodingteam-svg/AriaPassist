import 'package:aria/features/reminders/domain/recurrence.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:flutter/foundation.dart';

enum ParseIntent {
  createReminder('create_reminder'),
  createListItem('create_list_item'),
  createNote('create_note'),
  query('query'),
  update('update'),
  delete('delete'),
  snooze('snooze'),
  complete('complete'),
  // On-device only (not part of the LLM schema):
  startRoutine('start_routine'),
  forgetNote('forget_note');

  ParseIntent(this.wire);
  final String wire;
  static ParseIntent? parse(Object? s) =>
      values.where((v) => v.wire == s).firstOrNull;
}

enum QueryKind { today, missed, lookup, none }

enum ParseSource { llm, rules }

@immutable
class ParsedItem {
  const ParsedItem({
    required this.title,
    this.category = ReminderCategory.personal,
    this.at,
    this.allDay = false,
    this.rrule,
    this.priority = Priority.normal,
    this.amount,
    this.contact,
    this.notes,
    this.targetId,
    this.snoozeMinutes,
    this.listName,
    this.place,
    this.placeOn = PlaceTransition.arrive,
  });

  final String title;
  final ReminderCategory category;

  /// UTC instant (for all-day: local midnight of that day).
  final DateTime? at;
  final bool allDay;
  final String? rrule;
  final Priority priority;
  final double? amount;
  final String? contact;
  final String? notes;
  final String? targetId;
  final int? snoozeMinutes;
  final String? listName;

  /// Spoken place name ("home", "work") for location reminders.
  final String? place;
  final PlaceTransition placeOn;

  ParsedItem copyWith({
    String? title,
    DateTime? Function()? at,
    bool? allDay,
    String? Function()? rrule,
    ReminderCategory? category,
  }) => ParsedItem(
    title: title ?? this.title,
    category: category ?? this.category,
    at: at != null ? at() : this.at,
    allDay: allDay ?? this.allDay,
    rrule: rrule != null ? rrule() : this.rrule,
    priority: priority,
    amount: amount,
    contact: contact,
    notes: notes,
    targetId: targetId,
    snoozeMinutes: snoozeMinutes,
    listName: listName,
    place: place,
    placeOn: placeOn,
  );

  @override
  String toString() =>
      'ParsedItem($title, $category, at: $at, allDay: $allDay, rrule: $rrule, '
      '$priority, amount: $amount, target: $targetId, snooze: $snoozeMinutes, '
      'list: $listName, place: $place ${placeOn.name})';

  /// Ready to save: has a time or a place.
  bool get hasTrigger => at != null || place != null;
}

@immutable
class ParsedCommand {
  const ParsedCommand({
    required this.intent,
    required this.items,
    required this.source,
    this.query = QueryKind.none,
    this.clarification,
    this.spokenReply,
  });

  final ParseIntent intent;
  final List<ParsedItem> items;
  final QueryKind query;
  final String? clarification;
  final String? spokenReply;
  final ParseSource source;

  /// Strict validation of the Edge Function's JSON (never trust it blindly).
  /// Returns null if anything is off, so the caller falls back on-device.
  static ParsedCommand? fromJson(
    Map<String, dynamic> j, {
    Set<String>? knownIds,
  }) {
    try {
      final intent = ParseIntent.parse(j['intent']);
      final rawItems = j['items'];
      if (intent == null || rawItems is! List || rawItems.length > 10) {
        return null;
      }
      final items = <ParsedItem>[];
      for (final raw in rawItems) {
        if (raw is! Map) return null;
        final title = (raw['title'] as String? ?? '').trim();
        if (title.isEmpty && intent.wire.startsWith('create')) return null;
        final dt = raw['datetime'] as String?;
        final at = dt == null ? null : DateTime.parse(dt).toUtc();
        final rrule = raw['recurrence'] as String?;
        if (rrule != null && RecurrenceRule.tryParse(rrule) == null) {
          return null;
        }
        final cat = ReminderCategory.values.asNameMap()[raw['category']];
        final pri = Priority.values.asNameMap()[raw['priority']];
        if (cat == null || pri == null) return null;
        final target = raw['target_id'] as String?;
        items.add(
          ParsedItem(
            title: title.length > 200 ? title.substring(0, 200) : title,
            category: cat,
            at: at,
            allDay: raw['all_day'] as bool? ?? false,
            rrule: rrule,
            priority: pri,
            amount: (raw['amount'] as num?)?.toDouble(),
            contact: raw['contact'] as String?,
            notes: raw['notes'] as String?,
            targetId: knownIds == null || knownIds.contains(target)
                ? target
                : null,
            snoozeMinutes: (raw['snooze_minutes'] as num?)?.toInt(),
            listName: raw['list_name'] as String?,
            place: switch (raw['place']) {
              {'name': final String n} when n.trim().isNotEmpty => n.trim(),
              _ => null,
            },
            placeOn: switch (raw['place']) {
              {'on': 'leave'} => PlaceTransition.leave,
              _ => PlaceTransition.arrive,
            },
          ),
        );
      }
      return ParsedCommand(
        intent: intent,
        items: items,
        source: ParseSource.llm,
        query: QueryKind.values.asNameMap()[j['query']] ?? QueryKind.none,
        clarification: j['clarification_needed'] as String?,
        spokenReply: j['spoken_reply'] as String?,
      );
    } on Object {
      return null;
    }
  }

  @override
  String toString() =>
      'ParsedCommand(${intent.wire}, $items, query: $query, '
      'clarify: $clarification, $source)';
}

/// Context the parsers can match commands against.
typedef ReminderRef = ({String id, String title});
