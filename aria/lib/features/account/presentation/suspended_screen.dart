import 'dart:async';

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/features/account/application/account_status.dart';
import 'package:aria/features/account/application/session_service.dart';
import 'package:aria/features/help/presentation/help_screens.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shown when an admin has suspended the account. Reminders already on this
/// phone keep ringing (nobody misses a medicine because of a suspension).
class SuspendedScreen extends ConsumerWidget {
  const SuspendedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AriaTokens.s6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ExcludeSemantics(
                  child: Text('🔒', style: TextStyle(fontSize: 56)),
                ),
                const SizedBox(height: AriaTokens.s4),
                Text(
                  tr('Your account is suspended'),
                  key: const Key('suspended-title'),
                  style: text.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AriaTokens.s2),
                Text(
                  tr(
                    'Your data is safe and reminders already on this phone keep working. Contact support to find out more or to appeal.',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AriaTokens.s5),
                FilledButton.icon(
                  onPressed: () => launchUrl(
                    Uri(
                      scheme: 'mailto',
                      path: kSupportEmail,
                      queryParameters: {'subject': 'Account suspended'},
                    ),
                  ),
                  icon: const Icon(Icons.mail_outline_rounded),
                  label: Text(tr('Contact support')),
                ),
                TextButton(
                  onPressed: () =>
                      unawaited(ref.read(suspendedProvider.notifier).check()),
                  child: Text(tr('Check again')),
                ),
                TextButton(
                  onPressed: () =>
                      unawaited(ref.read(sessionServiceProvider).signOut()),
                  child: Text(tr('Sign out')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
