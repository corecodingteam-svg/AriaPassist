import 'dart:async';

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shown on Today when reminders might not ring on time.
class PermissionBanner extends ConsumerWidget {
  const PermissionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(notificationStatusProvider).value;
    if (status == null || status.allGood) return const SizedBox.shrink();
    final gateway = ref.read(notificationGatewayProvider);
    final p = context.palette;
    final (title, body, fix) = !status.notificationsAllowed
        ? (
            tr('Notifications are off'),
            tr('I can’t remind you until you allow notifications.'),
            () async {
              await gateway.requestPermissions();
              ref.invalidate(notificationStatusProvider);
            },
          )
        : (
            tr('Reminders may be late'),
            tr('Allow “Alarms & reminders” so I ring at the exact minute.'),
            () async {
              await gateway.openExactAlarmSettings();
              ref.invalidate(notificationStatusProvider);
            },
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: AriaTokens.s4),
      child: AriaCard(
        child: Row(
          children: [
            Icon(Icons.notifications_off_rounded, color: p.danger),
            const SizedBox(width: AriaTokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(body, style: TextStyle(color: p.muted)),
                ],
              ),
            ),
            TextButton(
              onPressed: () => unawaited(fix()),
              child: Text(tr('Fix')),
            ),
          ],
        ),
      ),
    );
  }
}
