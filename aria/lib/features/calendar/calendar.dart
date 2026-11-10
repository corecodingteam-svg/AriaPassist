import 'dart:async';

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/reminders/presentation/formatting.dart';
import 'package:aria/l10n/tr.dart';
import 'package:aria_device/aria_device.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as w;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A device calendar event (read-only; never uploaded).
@immutable
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.calendar = '',
  });

  factory CalendarEvent.fromMap(Map<String, dynamic> m) => CalendarEvent(
    id: m['id'] as String,
    title: (m['title'] as String?)?.trim().isNotEmpty == true
        ? m['title'] as String
        : tr('Busy'),
    start: DateTime.fromMillisecondsSinceEpoch(
      (m['start'] as num).toInt(),
      isUtc: true,
    ),
    end: DateTime.fromMillisecondsSinceEpoch(
      (m['end'] as num).toInt(),
      isUtc: true,
    ),
    allDay: m['allDay'] as bool? ?? false,
    calendar: m['calendar'] as String? ?? '',
  );

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String calendar;
}

abstract interface class CalendarBridge {
  Future<String> permission();
  Future<String> requestPermission();
  Future<List<CalendarEvent>> events(DateTime from, DateTime to);
}

class DeviceCalendarBridge implements CalendarBridge {
  const DeviceCalendarBridge();
  @override
  Future<String> permission() => AriaDevice.calendarPermission();
  @override
  Future<String> requestPermission() => AriaDevice.requestCalendarPermission();
  @override
  Future<List<CalendarEvent>> events(DateTime from, DateTime to) async =>
      (await AriaDevice.calendarEvents(
        from,
        to,
      )).map(CalendarEvent.fromMap).toList();
}

final calendarBridgeProvider = Provider<CalendarBridge>(
  (_) => const DeviceCalendarBridge(),
);

/// Events for one local day (00:00–24:00 in the device zone), oldest first.
/// Empty when calendar sync is off or permission is missing.
Future<List<CalendarEvent>> eventsOn(
  CalendarBridge bridge,
  DateTime dayWall,
  String zone,
) async {
  final from = fromWall(
    DateTime.utc(dayWall.year, dayWall.month, dayWall.day),
    zone,
  );
  final to = from.add(const Duration(days: 1));
  if (await bridge.permission() != 'granted') return const [];
  final list = await bridge.events(from, to);
  return list..sort((a, b) => a.start.compareTo(b.start));
}

/// Today's events for the Today screen (refreshes when the day changes or
/// the app resumes).
final todayEventsProvider = FutureProvider<List<CalendarEvent>>((ref) async {
  if (!ref.watch(appPrefsProvider.select((p) => p.calendarSync))) {
    return const [];
  }
  final zone = ref.watch(deviceTimeZoneProvider);
  // Re-run when the local day changes.
  ref.watch(
    nowProvider.select(
      (v) => v.value == null ? null : toWall(v.value!, zone).day,
    ),
  );
  final listener = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(listener.dispose);
  final wall = toWall(ref.read(clockProvider)(), zone);
  return await eventsOn(ref.watch(calendarBridgeProvider), wall, zone);
});

/// "Standup at 10 AM and Dentist at 4 PM" for the morning briefing.
String? eventsLine(List<CalendarEvent> events, String Function(DateTime) time) {
  if (events.isEmpty) return null;
  final parts = [
    for (final e in events.take(3))
      e.allDay ? e.title : tr('{0} at {1}', [e.title, time(e.start)]),
  ];
  final more = events.length > 3 ? ' and ${events.length - 3} more' : '';
  final list = parts.length == 1
      ? parts.first
      : tr('{0} and {1}', [
          parts.sublist(0, parts.length - 1).join(', '),
          parts.last,
        ]);
  return tr('On your calendar: {0}{1}.', [list, more]);
}

/// Compact read-only list on Today.
class CalendarSection extends ConsumerWidget {
  const CalendarSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events =
        ref.watch(todayEventsProvider).value ?? const <CalendarEvent>[];
    if (events.isEmpty) return const SizedBox.shrink();
    final zone = ref.watch(deviceTimeZoneProvider);
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AriaTokens.s2),
      child: AriaCard(
        key: const Key('calendar-section'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            w.Semantics(
              header: true,
              child: Text(
                tr('📅 Calendar · {0}', [events.length]),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: AriaTokens.s1),
            for (final e in events.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        e.allDay
                            ? tr('All day')
                            : formatTime(context, e.start, zone),
                        style: TextStyle(color: p.muted),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        e.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            if (events.length > 5)
              Text(
                tr('+{0} more', [events.length - 5]),
                style: TextStyle(color: p.muted),
              ),
          ],
        ),
      ),
    );
  }
}

/// Turns calendar sync on (asking permission in context) or off.
Future<bool> setCalendarSync(WidgetRef ref, {required bool on}) async {
  if (on) {
    final bridge = ref.read(calendarBridgeProvider);
    var perm = await bridge.permission();
    if (perm != 'granted') perm = await bridge.requestPermission();
    if (perm != 'granted') return false;
  }
  ref
      .read(appPrefsProvider.notifier)
      .update((x) => x.copyWith(calendarSync: on));
  ref.invalidate(todayEventsProvider);
  unawaited(ref.read(reminderServiceProvider)?.refresh());
  return true;
}
