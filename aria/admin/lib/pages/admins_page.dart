import 'package:aria_admin/core/format.dart';
import 'package:aria_admin/core/providers.dart';
import 'package:aria_admin/data/admin_api.dart';
import 'package:aria_admin/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final adminsProvider = FutureProvider<List<Rec>>(
  (ref) => ref.watch(adminApiProvider).admins(),
);

/// Super-admins only: who has admin access, and changing it.
class AdminsPage extends ConsumerWidget {
  const AdminsPage({super.key});

  Future<void> _change(
    BuildContext context,
    WidgetRef ref,
    String userId,
    AdminRole? role,
    String who,
  ) async {
    final reason = await askReason(
      context,
      title: role == null
          ? 'Remove admin access for $who?'
          : 'Make $who ${role.label}?',
      action: role == null ? 'Remove' : 'Save',
      danger: role == null,
    );
    if (reason == null || !context.mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(adminApiProvider).setRole(userId, role, reason),
      done: 'Admin access updated',
    );
    if (ok) ref.invalidate(adminsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => PageFrame(
    title: 'Admins',
    subtitle: 'Every admin must use two-factor sign-in. To add someone, open them under Users, copy their id, and use “Add admin”.',
    actions: [
      FilledButton.icon(
        icon: const Icon(Icons.person_add),
        label: const Text('Add admin'),
        onPressed: () async {
          final id = TextEditingController();
          var role = AdminRole.support;
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => StatefulBuilder(
              builder: (c, set) => AlertDialog(
                title: const Text('Add admin'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: id,
                      decoration: const InputDecoration(labelText: 'User id'),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<AdminRole>(
                      segments: [
                        for (final r in AdminRole.values)
                          ButtonSegment(value: r, label: Text(r.label)),
                      ],
                      selected: {role},
                      onSelectionChanged: (v) => set(() => role = v.first),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Next'),
                  ),
                ],
              ),
            ),
          );
          if ((ok ?? false) && context.mounted) {
            await _change(context, ref, id.text.trim(), role, id.text.trim());
          }
          id.dispose();
        },
      ),
    ],
    children: [
      AsyncBody(
        value: ref.watch(adminsProvider),
        builder: (rows) => Card(
          child: Column(
            children: [
              for (final r in rows)
                ListTile(
                  title: Text(
                    '${r['name'] ?? '—'}  ·  ${r['email'] ?? r['phone'] ?? ''}',
                  ),
                  subtitle: Text(
                    'Since ${date(r['since'])} · last seen ${relative(r['last_seen_at'])}',
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Change role',
                    onSelected: (v) => _change(
                      context,
                      ref,
                      '${r['user_id']}',
                      AdminRole.parse(v),
                      '${r['name'] ?? r['user_id']}',
                    ),
                    itemBuilder: (_) => [
                      for (final role in AdminRole.values)
                        if (role.wire != r['role'])
                          PopupMenuItem(
                            value: role.wire,
                            child: Text('Make ${role.label}'),
                          ),
                      const PopupMenuItem(
                        value: 'remove',
                        child: Text('Remove admin access'),
                      ),
                    ],
                    child: Chip(
                      label: Text(
                        AdminRole.parse(r['role'])?.label ?? '${r['role']}',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}
