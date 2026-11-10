import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/reminder_logic.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/reminders/presentation/formatting.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Smart snooze picker. Returns the chosen instant (UTC) or null.
Future<DateTime?> showSnoozeSheet(BuildContext context, WidgetRef ref) {
  final zone = ref.read(deviceTimeZoneProvider);
  final now = ref.read(clockProvider)().toUtc();
  final options = [
    for (final o in SnoozeOption.values)
      if (o != SnoozeOption.min15) // 15 min is the swipe default
        if (o.resolve(now, zone) case final at?) (o, at),
  ];
  return showModalBottomSheet<DateTime>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AriaTokens.s4,
          0,
          AriaTokens.s4,
          AriaTokens.s4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Snooze until…'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AriaTokens.s3),
            Wrap(
              spacing: AriaTokens.s2,
              runSpacing: AriaTokens.s2,
              children: [
                for (final (o, at) in options)
                  ActionChip(
                    label: Text(
                      o.index <= SnoozeOption.hour1.index
                          ? o.label
                          : '${o.label} · ${formatTime(context, at, zone)}',
                    ),
                    onPressed: () => Navigator.pop(context, at),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(tr('Pick a time')),
                  onPressed: () async {
                    final picked = await pickDateTime(context, now, zone);
                    if (picked != null && context.mounted) {
                      Navigator.pop(context, picked);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Date then time picker, in [zone]. Returns a UTC instant.
Future<DateTime?> pickDateTime(
  BuildContext context,
  DateTime now,
  String zone, {
  DateTime? initial,
}) async {
  final w = toWall(initial ?? now.add(const Duration(hours: 1)), zone);
  final today = toWall(now, zone);
  final date = await showDatePicker(
    context: context,
    initialDate: DateTime(w.year, w.month, w.day),
    firstDate: DateTime(today.year, today.month, today.day),
    lastDate: DateTime(today.year + 5),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: w.hour, minute: w.minute),
  );
  if (time == null) return null;
  return fromWall(
    DateTime.utc(date.year, date.month, date.day, time.hour, time.minute),
    zone,
  );
}
