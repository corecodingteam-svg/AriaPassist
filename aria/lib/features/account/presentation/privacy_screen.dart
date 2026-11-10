import 'dart:async';
import 'dart:io' show Platform;

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/features/account/application/app_lock.dart';
import 'package:aria/features/account/application/session_service.dart';
import 'package:aria/features/help/presentation/help_screens.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/reminders/application/notification_gateway.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings › Privacy & security (spec 6.9).
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(appPrefsProvider);
    final ctl = ref.read(appPrefsProvider.notifier);
    final text = Theme.of(context).textTheme;
    final muted = context.palette.muted;
    final ios = !kIsWeb && Platform.isIOS;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Privacy & security'))),
      body: ListView(
        padding: const EdgeInsets.all(AriaTokens.s4),
        children: [
          AriaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('In plain words'), style: text.titleMedium),
                const SizedBox(height: AriaTokens.s2),
                Text(
                  tr(
                    '• Your reminders are stored on your phone and in your private, encrypted account.\n• Your voice is turned into text on your phone. Audio is never stored.\n• Nobody else sees your reminders unless you share them.\n• You can export or delete everything at any time.',
                  ),
                ),
                TextButton(
                  onPressed: () => launchUrl(Uri.parse(kPrivacyPolicyUrl)),
                  child: Text(tr('Read the full privacy policy')),
                ),
              ],
            ),
          ),
          const SizedBox(height: AriaTokens.s3),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Store voice recordings')),
            subtitle: Text(
              tr('Off. Aria never keeps audio — only the reminder text.'),
            ),
            value: false,
            onChanged: null,
          ),
          SwitchListTile(
            key: const Key('analytics-consent'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Share anonymous usage data')),
            subtitle: Text(
              tr(
                'Which features get used — never your reminders, names or notes',
              ),
            ),
            value: p.analytics,
            onChanged: (v) => ctl.update((x) => x.copyWith(analytics: v)),
          ),
          SwitchListTile(
            key: const Key('crash-reports'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Send crash reports')),
            subtitle: Text(tr('Helps fix bugs. Contains no reminder content.')),
            value: p.crashReports,
            onChanged: (v) => ctl.update((x) => x.copyWith(crashReports: v)),
          ),
          SwitchListTile(
            key: const Key('app-lock'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('App lock')),
            subtitle: Text(
              tr('Unlock with your fingerprint, face or phone PIN'),
            ),
            value: p.appLock,
            onChanged: (v) async {
              final auth = ref.read(authenticatorProvider);
              if (v) {
                if (!await auth.isAvailable()) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          tr('Set up a screen lock on your phone first.'),
                        ),
                      ),
                    );
                  }
                  return;
                }
                if (!await auth.authenticate(tr('Turn on App lock'))) return;
              }
              ctl.update((x) => x.copyWith(appLock: v));
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Hide reminder content on lock screen')),
            subtitle: Text(
              ios
                  ? tr('iOS: set Show Previews to “When Unlocked” for Aria')
                  : tr(
                      'Lock screen shows “Contents hidden” instead of the reminder',
                    ),
            ),
            value: p.hideOnLockScreen,
            onChanged: (v) async {
              ctl.update((x) => x.copyWith(hideOnLockScreen: v));
              final gw = ref.read(notificationGatewayProvider);
              if (v && ios && gw is LocalNotificationGateway) {
                await gw.openNotificationSettings();
              }
            },
          ),
          const Divider(height: AriaTokens.s6),
          Text(tr('Your data'), style: text.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_rounded),
            title: Text(tr('Export my data')),
            subtitle: Text(tr('All reminders and settings as JSON + CSV')),
            onTap: () => unawaited(ref.read(dataExporterProvider).share()),
          ),
          ListTile(
            key: const Key('delete-account'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.delete_forever_rounded,
              color: context.palette.danger,
            ),
            title: Text(
              tr('Delete account'),
              style: TextStyle(color: context.palette.danger),
            ),
            subtitle: Text(
              tr(
                'Everything is deleted after 7 days. Sign back in before then to cancel.',
              ),
              style: TextStyle(color: muted),
            ),
            onTap: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Delete your account?')),
        content: Text(
          tr(
            'Your reminders, settings and account will be permanently deleted in 7 days. You’ll be signed out now. Sign in again within 7 days to cancel.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.danger,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (ok ?? false) await ref.read(sessionServiceProvider).requestDeletion();
  }
}

/// Shown on Today when the account is scheduled for deletion.
class PendingDeletionBanner extends ConsumerWidget {
  const PendingDeletionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final when = ref.watch(pendingDeletionProvider).value;
    if (when == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AriaTokens.s3),
      child: AriaCard(
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: context.palette.danger),
            const SizedBox(width: AriaTokens.s3),
            Expanded(
              child: Text(
                tr('Your account will be deleted on {0}.', [
                  DateFormat('d MMM').format(when.toLocal()),
                ]),
              ),
            ),
            TextButton(
              onPressed: () async {
                await ref.read(sessionServiceProvider).cancelDeletion();
                ref.invalidate(pendingDeletionProvider);
              },
              child: Text(tr('Keep my account')),
            ),
          ],
        ),
      ),
    );
  }
}
