import 'dart:async';

import 'package:aria/features/assistant/domain/parse_result.dart';
import 'package:aria/features/assistant/domain/rule_parser.dart';
import 'package:aria/features/preferences/domain/app_prefs.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Calls the `parse` Edge Function; returns null on any failure.
typedef RemoteParse = Future<Map<String, dynamic>?> Function(
  Map<String, dynamic> body,
);

RemoteParse supabaseRemoteParse(SupabaseClient client) => (body) async {
  final res = await client.functions.invoke('parse', body: body);
  return res.status == 200 && res.data is Map
      ? Map<String, dynamic>.from(res.data as Map)
      : null;
};

/// Hybrid parsing (spec §11):
/// 1. Clear commands ("snooze 20 minutes", "what's on today", "add milk to
///    grocery list") are handled on-device: instant, free, private.
/// 2. Everything else goes to the LLM with a 4 s budget.
/// 3. Timeout / offline / invalid output → the on-device rule parser.
class ParserService {
  ParserService({
    this.remote,
    bool Function()? online,
    this.timeout = const Duration(seconds: 4),
  }) : _online = online ?? (() => true);

  final RemoteParse? remote;
  final bool Function() _online;
  final Duration timeout;

  Future<ParsedCommand> parse(
    String text, {
    required DateTime now,
    required String zone,
    List<ReminderRef> refs = const [],
    DayParts dayParts = const DayParts(),
  }) async {
    final rules = RuleParser(
      now: now,
      zone: zone,
      reminders: refs,
      dayParts: dayParts,
    ).parse(text);
    if (_handledLocally(rules) || remote == null || !_online()) return rules;

    try {
      final json = await remote!({
        'text': text,
        'now': _isoWithOffset(now, zone),
        'timezone': zone,
        'reminders': [
          for (final r in refs.take(50)) {'id': r.id, 'title': r.title},
        ],
      }).timeout(timeout);
      final llm = json == null
          ? null
          : ParsedCommand.fromJson(
              json,
              knownIds: {for (final r in refs) r.id},
            );
      return llm ?? rules;
    } on Object catch (e) {
      debugPrint('remote parse failed, using on-device parser: $e');
      return rules;
    }
  }

  static bool _handledLocally(ParsedCommand c) =>
      c.clarification == null &&
      switch (c.intent) {
        ParseIntent.query ||
        ParseIntent.complete ||
        ParseIntent.snooze ||
        ParseIntent.delete ||
        ParseIntent.createListItem ||
        ParseIntent.createNote ||
        ParseIntent.startRoutine ||
        ParseIntent.forgetNote => true,
        // Simple single reminders with a clear time are fine locally too.
        ParseIntent.createReminder =>
          c.items.length == 1 && c.items.single.at != null,
        ParseIntent.update => c.items.isNotEmpty && c.items.single.at != null,
      };

  static String _isoWithOffset(DateTime now, String zone) {
    // e.g. 2026-11-09T10:00:00+05:30 — the model reasons in local time.
    final wall = DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(_toWall(now, zone));
    final offset = _toWall(now, zone).difference(now.toUtc());
    final sign = offset.isNegative ? '-' : '+';
    final m = offset.inMinutes.abs();
    return '$wall$sign${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  static DateTime _toWall(DateTime instant, String zone) =>
      toWall(instant, zone);
}
