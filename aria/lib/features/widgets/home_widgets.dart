import 'dart:async';
import 'dart:convert';

import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/alert_plan.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/reminder_logic.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

const kAppGroupId = 'group.com.aria.pa';
const kAndroidWidgets = ['NextReminderWidget', 'TodayWidget', 'MicWidget'];

/// WidgetKit kinds in ios/AriaWidget/AriaWidget.swift.
const kIosWidgets = ['AriaWidget', 'AriaTodayWidget', 'AriaMicWidget'];

/// What the home-screen widgets show. Pure; unit-tested.
@immutable
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.nextTitle,
    required this.nextTime,
    required this.nextId,
    required this.today,
    required this.todayCount,
  });

  factory WidgetSnapshot.build(
    Iterable<Reminder> reminders, {
    required String userId,
    required DateTime now,
    required String zone,
    bool use24h = false,
  }) {
    String time(DateTime i) =>
        (use24h ? DateFormat.Hm() : DateFormat.jm()).format(toWall(i, zone));
    final upcoming = [
      for (final r in reminders)
        if (r.isActive && r.owner == userId && r.dueAt != null)
          (r: r, at: ReminderLogic.fireTimeFor(r, r.dueAt!)),
    ]..sort((a, b) => a.at.compareTo(b.at));
    final next = upcoming.where((e) => e.at.isAfter(now)).firstOrNull;
    final agenda = agendaFor(reminders, userId: userId, day: now, zone: zone);
    final pending = agenda.entries
        .where((e) => !e.at.isBefore(now) || e.allDay)
        .toList();
    return WidgetSnapshot(
      nextTitle: next == null
          ? null
          : '${next.r.category.emoji} ${next.r.title}',
      nextTime: next == null ? null : time(next.at),
      nextId: next?.r.id,
      today: [
        for (final e in pending.take(3))
          e.allDay ? 'Anytime  ${e.title}' : '${time(e.at)}  ${e.title}',
      ],
      todayCount: pending.length,
    );
  }

  /// e.g. "💊 Vitamin D" / "8:30 PM" — null when nothing is coming up.
  final String? nextTitle;
  final String? nextTime;
  final String? nextId;

  /// Up to 3 "8:30 PM  💊 Vitamin D" lines for today.
  final List<String> today;
  final int todayCount;

  Map<String, String> toData() => {
    'next_title': nextTitle ?? tr('Nothing coming up'),
    'next_time': nextTime ?? tr('Tap the mic to add one'),
    'next_link': nextId == null ? 'aria:///today' : 'aria:///reminder/$nextId',
    'today_lines': today.isEmpty ? 'A clear day 🌤️' : today.join('\n'),
    'today_count': todayCount == 0 ? 'Today' : tr('Today · {0}', [todayCount]),
    'today_json': jsonEncode(today),
  };
}

/// Pushes snapshots to the platform widgets whenever reminders change.
final homeWidgetSyncProvider = Provider<void>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null || kIsWeb) return;
  unawaited(HomeWidget.setAppGroupId(kAppGroupId).catchError((_) => null));
  WidgetSnapshot? last;

  Future<void> push(List<Reminder> rs) async {
    final snap = WidgetSnapshot.build(
      rs,
      userId: uid,
      now: ref.read(clockProvider)().toUtc(),
      zone: ref.read(deviceTimeZoneProvider),
    );
    if (last != null && mapEquals(last!.toData(), snap.toData())) return;
    last = snap;
    try {
      for (final e in snap.toData().entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }
      for (final name in kAndroidWidgets) {
        await HomeWidget.updateWidget(androidName: name);
      }
      for (final kind in kIosWidgets) {
        await HomeWidget.updateWidget(iOSName: kind);
      }
    } on Object catch (e) {
      debugPrint('widget update skipped: $e');
    }
  }

  ref
    ..listen(myRemindersProvider, (_, next) {
      if (next.value case final rs?) unawaited(push(rs));
    }, fireImmediately: true)
    // Time passes: "next" changes even without data changes.
    ..listen(nowProvider, (_, _) {
      if (ref.read(myRemindersProvider).value case final rs?) {
        unawaited(push(rs));
      }
    });
});
