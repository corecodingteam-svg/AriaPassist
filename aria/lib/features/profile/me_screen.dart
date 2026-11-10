import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/features/account/application/session_service.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/progress/presentation/weekly_report_card.dart';
import 'package:aria/features/subscription/presentation/renewal_banner.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final circle = ref.watch(activeCircleProvider);
    final name = ref.watch(appPrefsProvider.select((p) => p.userName));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Me'))),
      body: ListView(
        padding: const EdgeInsets.all(AriaTokens.s4),
        children: [
          AriaCard(
            onTap: () => context.push('/circle'),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: context.palette.primary.withValues(
                    alpha: 0.15,
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    size: 32,
                    color: context.palette.primary,
                  ),
                ),
                const SizedBox(width: AriaTokens.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name ?? tr('Your profile'), style: text.titleMedium),
                      Text(
                        circle == null || circle.isPersonal
                            ? tr('Personal · tap to create or join a Circle')
                            : '${circle.type.emoji} ${circle.name} · ${circle.myRole.label}',
                        style: text.bodyMedium?.copyWith(
                          color: context.palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AriaTokens.s4),
          const RenewalBanner(),
          const WeeklyReportCard(),
          const SizedBox(height: AriaTokens.s4),
          _Tile(
            icon: Icons.settings_rounded,
            label: tr('Settings'),
            onTap: () => context.push('/settings'),
          ),
          _Tile(
            key: const Key('me-circle'),
            icon: Icons.groups_rounded,
            label: tr('Circle'),
            onTap: () => context.push('/circle'),
          ),
          _Tile(
            icon: Icons.workspace_premium_rounded,
            label: tr('Subscription & plans'),
            onTap: () => context.push('/subscription'),
          ),
          _Tile(
            icon: Icons.notifications_rounded,
            label: tr('Missed & past reminders'),
            onTap: () => context.push('/notifications'),
          ),
          const SizedBox(height: AriaTokens.s4),
          OutlinedButton.icon(
            // Wipes this device's copy of the data and silences alerts.
            onPressed: () => ref.read(sessionServiceProvider).signOut(),
            icon: const Icon(Icons.logout_rounded),
            label: Text(tr('Sign out')),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: context.palette.primary),
    title: Text(label),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
    minTileHeight: AriaTokens.minTap + 8,
  );
}
