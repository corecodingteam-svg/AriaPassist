import 'dart:async';

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/features/calendar/calendar.dart';
import 'package:aria/features/connected/whatsapp_api.dart';
import 'package:aria/features/places/application/places_providers.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Settings › Connected apps: device calendar, WhatsApp, places.
class ConnectedAppsScreen extends ConsumerWidget {
  const ConnectedAppsScreen({super.key});

  void _say(BuildContext context, String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(appPrefsProvider);
    final wa = ref.watch(whatsAppStatusProvider);
    final plan = ref.watch(entitlementProvider).plan;
    final muted = context.palette.muted;
    final places = ref.watch(placesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Connected apps'))),
      body: ListView(
        padding: const EdgeInsets.all(AriaTokens.s4),
        children: [
          SwitchListTile(
            key: const Key('calendar-sync'),
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.calendar_month_rounded),
            title: Text(tr('Phone calendar')),
            subtitle: Text(
              tr(
                'Show today’s events on Today and in your morning briefing. Events stay on your phone.',
              ),
            ),
            value: prefs.calendarSync,
            onChanged: (on) async {
              final ok = await setCalendarSync(ref, on: on);
              if (!ok && context.mounted) {
                _say(
                  context,
                  tr(
                    'Allow calendar access for Aria in your phone’s settings.',
                  ),
                );
              }
            },
          ),
          const Divider(),
          SwitchListTile(
            key: const Key('whatsapp'),
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.chat_rounded),
            title: Text(
              plan.has(Feature.whatsapp)
                  ? tr('WhatsApp reminders')
                  : tr('WhatsApp reminders 🔒'),
            ),
            subtitle: Text(
              wa.value != null
                  ? tr(
                      'Also sent to {0} on WhatsApp. Reply DONE to tick it off.',
                      [wa.value],
                    )
                  : tr(
                      'Get each reminder on WhatsApp too — handy for parents. Family plan.',
                    ),
            ),
            value: wa.value != null,
            onChanged: wa.isLoading
                ? null
                : (on) async {
                    if (on && !requireFeature(context, ref, Feature.whatsapp)) {
                      return;
                    }
                    try {
                      await ref
                          .read(whatsAppApiProvider)
                          ?.setEnabled(enabled: on);
                      ref.invalidate(whatsAppStatusProvider);
                    } on Object catch (e) {
                      if (context.mounted) {
                        _say(context, whatsAppErrorMessage(e));
                      }
                    }
                  },
          ),
          Padding(
            padding: const EdgeInsets.only(left: 56),
            child: Text(
              tr(
                'By turning this on you agree to receive reminder messages from Aria on WhatsApp. Turn it off any time.',
              ),
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_rounded),
            title: Text(tr('Places')),
            subtitle: Text(
              places.isEmpty
                  ? tr('Save Home or Work for location reminders')
                  : places.map((p) => p.name).join(', '),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => unawaited(context.push('/settings/places')),
          ),
        ],
      ),
    );
  }
}
