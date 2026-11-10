import 'dart:async';

import 'package:aria/core/router/app_router.dart';
import 'package:aria/features/reminders/application/notification_gateway.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide Priority;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Handles notification taps/actions while the app process is alive.
Future<void> handleNotificationResponse(
  ProviderContainer container,
  NotificationResponse response,
) async {
  final ref = parsePayload(stripFireTime(response.payload));
  if (ref == null) return;
  final action = response.actionId;

  if (action == AlertAction.done ||
      action == AlertAction.snooze15 ||
      action == AlertAction.snooze60) {
    await container.read(reminderServiceProvider)?.handleAction(action, ref);
    return;
  }

  // Routines open the runner; briefings open Today.
  final router = container.read(routerProvider);
  if (ref.reminderId.startsWith('routine:')) {
    unawaited(router.push('/routine/${ref.reminderId.substring(8)}'));
    return;
  }
  if (ref.reminderId.startsWith('billing:')) {
    unawaited(router.push('/subscription'));
    return;
  }
  if (ref.reminderId.startsWith('briefing:')) {
    router.go('/today');
    return;
  }

  // Tap or "Open": deep-link to the reminder (urgent → full-screen alert).
  final reminder = await container
      .read(reminderRepositoryProvider)
      ?.get(ref.reminderId);
  final path = reminder?.priority == Priority.urgent && reminder!.isActive
      ? '/reminder/${ref.reminderId}/alert'
      : '/reminder/${ref.reminderId}';
  unawaited(router.push(path));
}
