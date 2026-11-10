import 'dart:async';

import 'package:aria/core/connectivity.dart';
import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/mic_button.dart';
import 'package:aria/core/widgets/state_views.dart';
import 'package:aria/features/assistant/presentation/talk_sheet.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Bottom navigation: Today · (Mic) · Lists.
class HomeShell extends ConsumerWidget {
  const HomeShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _openTalkSheet(BuildContext context) =>
      unawaited(showTalkSheet(context));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider).value ?? true;
    final simple = ref.watch(simpleModeProvider);
    final p = context.palette;
    return Scaffold(
      body: Column(
        children: [
          if (!online) const SafeArea(bottom: false, child: OfflineBanner()),
          Expanded(child: navigationShell),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(top: AriaTokens.s5),
        child: MicButton(onPressed: () => _openTalkSheet(context)),
      ),
      bottomNavigationBar: BottomAppBar(
        color: p.surface,
        height: 72,
        padding: EdgeInsets.zero,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: Row(
          children: [
            _NavItem(
              icon: Icons.today_rounded,
              label: tr('Today'),
              selected: navigationShell.currentIndex == 0,
              onTap: () => navigationShell.goBranch(0, initialLocation: true),
            ),
            const SizedBox(width: AriaTokens.micSize + AriaTokens.s5),
            // Simple Mode: only Today + the mic (spec 6.4).
            if (simple)
              const Expanded(child: SizedBox())
            else
              _NavItem(
                icon: Icons.checklist_rounded,
                label: tr('Lists'),
                selected: navigationShell.currentIndex == 1,
                onTap: () => navigationShell.goBranch(1, initialLocation: true),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = selected ? p.primary : p.muted;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          // Grows with large text; label scaling is capped like Material's
          // own navigation bar so four tabs still fit.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: MediaQuery.textScalerOf(context)
                      .clamp(maxScaleFactor: 1.3),
                  style: TextStyle(
                    color: color,
                    // Weight + colour: selection isn't conveyed by colour alone.
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
