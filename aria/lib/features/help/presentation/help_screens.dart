import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/core/widgets/state_views.dart';
import 'package:aria/features/help/application/reliability.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const kSupportEmail = 'support@aria.app';
// Placeholders until the real pages are published (release checklist).
const kPrivacyPolicyUrl = 'https://aria.app/privacy';
const kTermsUrl = 'https://aria.app/terms';

final appVersionProvider = FutureProvider<String>((_) async {
  try {
    final i = await PackageInfo.fromPlatform();
    return '${i.version} (${i.buildNumber})';
  } on Object {
    return 'dev';
  }
});

/// Settings › Help & About (6.11).
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  static List<(String, String)> get faq => [
    (
      tr('Why didn’t my reminder ring?'),
      tr(
        'Usually a phone setting is blocking it. Open “Reminders not ringing?” below — it checks everything and fixes most problems with one tap.',
      ),
    ),
    (
      tr('Does Aria work offline?'),
      tr(
        'Yes. Reminders are stored and scheduled on your phone, so they ring without internet. Changes sync when you are back online.',
      ),
    ),
    (
      tr('Do you record my voice?'),
      tr(
        'No. Speech is turned into text on your phone and only the reminder text is kept. Audio is never stored.',
      ),
    ),
    (
      tr('Can I use Aria without voice?'),
      tr(
        'Yes. Choose “Text only” in Settings › Reminder style. Everything you can say, you can also tap.',
      ),
    ),
    (
      tr('How do I share reminders with family?'),
      tr(
        'Create a family Circle from Me › Circle and invite them. One Family plan covers up to 5 people.',
      ),
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).value ?? '…';
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Help & about'))),
      body: ListView(
        padding: const EdgeInsets.all(AriaTokens.s4),
        children: [
          AriaCard(
            onTap: () => context.push('/settings/help/troubleshooter'),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_active_rounded,
                  color: context.palette.primary,
                ),
                const SizedBox(width: AriaTokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('Reminders not ringing?'),
                        style: text.titleMedium,
                      ),
                      Text(tr('Check and fix your phone’s settings')),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
          const SizedBox(height: AriaTokens.s4),
          Text(tr('Questions'), style: text.titleMedium),
          for (final (q, a) in faq)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(q),
              childrenPadding: const EdgeInsets.only(bottom: AriaTokens.s3),
              expandedAlignment: Alignment.centerLeft,
              children: [Text(a)],
            ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.mail_outline_rounded),
            title: Text(tr('Contact support')),
            subtitle: const Text(kSupportEmail),
            onTap: () => launchUrl(
              Uri(
                scheme: 'mailto',
                path: kSupportEmail,
                queryParameters: {
                  'subject': tr('Aria {0}', [version]),
                },
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.star_outline_rounded),
            title: Text(tr('Rate Aria')),
            subtitle: Text(tr('Available once Aria is in the stores')),
            enabled: false,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.policy_outlined),
            title: Text(tr('Privacy policy')),
            onTap: () => launchUrl(Uri.parse(kPrivacyPolicyUrl)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(tr('Version')),
            subtitle: Text(version),
          ),
        ],
      ),
    );
  }
}

/// "Reminders not ringing?" — runs every check, one-tap fixes, test alert.
class TroubleshooterScreen extends ConsumerWidget {
  const TroubleshooterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checks = ref.watch(reliabilityChecksProvider);
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Reminders not ringing?'))),
      body: checks.when(
        loading: () => LoadingState(label: tr('Checking your phone')),
        error: (e, _) => ErrorState(message: '$e'),
        data: (list) {
          final problems = list
              .where((c) => c.status == CheckStatus.problem)
              .length;
          return RefreshIndicator(
            onRefresh: () => ref.refresh(reliabilityChecksProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(AriaTokens.s4),
              children: [
                Text(
                  problems == 0
                      ? tr('Everything looks good ✅')
                      : tr('{0} thing{1} to fix', [
                          problems,
                          problems == 1 ? '' : 's',
                        ]),
                  key: const Key('trouble-summary'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AriaTokens.s3),
                for (final c in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AriaTokens.s2),
                    child: AriaCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            switch (c.status) {
                              CheckStatus.ok => Icons.check_circle_rounded,
                              CheckStatus.problem => Icons.error_rounded,
                              CheckStatus.info => Icons.info_rounded,
                            },
                            color: switch (c.status) {
                              CheckStatus.ok => p.success,
                              CheckStatus.problem => p.danger,
                              CheckStatus.info => p.primary,
                            },
                            semanticLabel: c.status.name,
                          ),
                          const SizedBox(width: AriaTokens.s3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text(c.detail),
                                if (c.fix != null)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                      onPressed: () async {
                                        await c.fix!();
                                        ref
                                          ..invalidate(
                                            reliabilityChecksProvider,
                                          )
                                          ..invalidate(
                                            notificationStatusProvider,
                                          );
                                      },
                                      child: Text(c.fixLabel ?? tr('Fix')),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: AriaTokens.s3),
                FilledButton.icon(
                  key: const Key('send-test'),
                  onPressed: () async {
                    await ref
                        .read(notificationGatewayProvider)
                        .sendTest(const Duration(seconds: 10));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          tr(
                            'Test reminder in 10 seconds — you can lock your phone.',
                          ),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.send_rounded),
                  label: Text(tr('Send a test reminder')),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Settings › Connected apps (6.8) — integrations ship in Phase 8.
