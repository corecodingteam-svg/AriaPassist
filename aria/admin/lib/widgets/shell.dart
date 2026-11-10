import 'dart:async';

import 'package:aria_admin/core/providers.dart';
import 'package:aria_admin/data/admin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

typedef _Dest = ({String path, IconData icon, String label, bool superOnly});

const List<_Dest> _dests = [
  (
    path: '/',
    icon: Icons.dashboard_outlined,
    label: 'Overview',
    superOnly: false,
  ),
  (
    path: '/users',
    icon: Icons.people_outline,
    label: 'Users',
    superOnly: false,
  ),
  (
    path: '/subscriptions',
    icon: Icons.workspace_premium_outlined,
    label: 'Subscriptions',
    superOnly: false,
  ),
  (
    path: '/revenue',
    icon: Icons.currency_rupee,
    label: 'Revenue',
    superOnly: false,
  ),
  (
    path: '/promos',
    icon: Icons.local_offer_outlined,
    label: 'Promo codes',
    superOnly: false,
  ),
  (
    path: '/messaging',
    icon: Icons.forum_outlined,
    label: 'Messaging',
    superOnly: false,
  ),
  (
    path: '/activity',
    icon: Icons.history,
    label: 'Activity log',
    superOnly: false,
  ),
  (
    path: '/admins',
    icon: Icons.admin_panel_settings_outlined,
    label: 'Admins',
    superOnly: true,
  ),
];

/// Navigation rail (wide) or drawer (narrow) around every admin page.
class AdminShell extends ConsumerWidget {
  const AdminShell({required this.location, required this.child, super.key});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(adminRoleProvider).value;
    final auth = ref.watch(adminAuthProvider);
    final dests = [
      for (final d in _dests)
        if (!d.superOnly || (role?.isSuper ?? false)) d,
    ];
    final selected = dests.lastIndexWhere(
      (d) => d.path == '/' ? location == '/' : location.startsWith(d.path),
    );
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final header = AppBar(
      title: const Text('Aria Admin'),
      actions: [
        if (role != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(label: Text(role.label)),
          ),
        if (auth.userLabel != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(child: Text(auth.userLabel!)),
          ),
        IconButton(
          tooltip: 'Sign out',
          onPressed: () => unawaited(auth.signOut()),
          icon: const Icon(Icons.logout),
        ),
      ],
    );

    if (!wide) {
      return Scaffold(
        appBar: header,
        drawer: Drawer(
          child: ListView(
            children: [
              for (final (i, d) in dests.indexed)
                ListTile(
                  leading: Icon(d.icon),
                  title: Text(d.label),
                  selected: i == selected,
                  onTap: () {
                    Navigator.pop(context);
                    context.go(d.path);
                  },
                ),
            ],
          ),
        ),
        body: child,
      );
    }
    return Scaffold(
      appBar: header,
      body: Row(
        children: [
          NavigationRail(
            extended: MediaQuery.sizeOf(context).width >= 1200,
            selectedIndex: selected < 0 ? null : selected,
            labelType: MediaQuery.sizeOf(context).width >= 1200
                ? null
                : NavigationRailLabelType.all,
            onDestinationSelected: (i) => context.go(dests[i].path),
            destinations: [
              for (final d in dests)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

extension AdminRoleX on AdminRole? {
  bool get canAct => this?.canAct ?? false;
  bool get isSuper => this?.isSuper ?? false;
}
