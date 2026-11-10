import 'package:aria_admin/core/format.dart';
import 'package:aria_admin/core/providers.dart';
import 'package:aria_admin/data/admin_api.dart';
import 'package:aria_admin/pages/subscriptions_page.dart';
import 'package:aria_admin/pages/users_page.dart';
import 'package:aria_admin/widgets/common.dart';
import 'package:aria_admin/widgets/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ignore: specify_nonobvious_property_types -- family type is verbose
final userDetailProvider = FutureProvider.autoDispose.family<Rec, String>(
  (ref, id) => ref.watch(adminApiProvider).userDetail(id),
);

class UserDetailPage extends ConsumerWidget {
  const UserDetailPage({required this.userId, super.key});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(userDetailProvider(userId));
    final role = ref.watch(adminRoleProvider).value;
    final api = ref.read(adminApiProvider);

    Future<void> act(
      String title,
      String action,
      Future<void> Function(String reason) op, {
      String? message,
      String? confirmWord,
      bool danger = false,
      bool leave = false,
    }) async {
      final reason = await askReason(
        context,
        title: title,
        action: action,
        message: message,
        confirmWord: confirmWord,
        danger: danger,
      );
      if (reason == null || !context.mounted) return;
      final ok = await runAction(
        context,
        () => op(reason),
        done: '$action: done',
      );
      if (!ok) return;
      ref.invalidate(userSearchProvider);
      if (leave && context.mounted) {
        context.go('/users');
      } else {
        ref.invalidate(userDetailProvider(userId));
      }
    }

    return AsyncBody(
      value: detail,
      builder: (d) {
        final u = Map<String, dynamic>.from(d['user'] as Map);
        final suspended = u['suspended_at'] != null;
        final circles = [
          for (final c in d['circles'] as List)
            Map<String, dynamic>.from(c as Map),
        ];
        return PageFrame(
          title: '${u['name'] ?? 'User'}',
          subtitle:
              '${u['phone'] ?? ''}  ${u['email'] ?? ''}  ·  ${userStatus(u)}',
          actions: [
            TextButton.icon(
              onPressed: () => context.go('/users'),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Users'),
            ),
          ],
          children: [
            if (suspended)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.block),
                  title: Text('Suspended ${dateTime(u['suspended_at'])}'),
                  subtitle: Text('Reason: ${u['suspended_reason'] ?? '—'}'),
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                KpiCard(label: 'Joined', value: date(u['created_at'])),
                KpiCard(label: 'Last seen', value: relative(u['last_seen_at'])),
                KpiCard(label: 'Circles', value: count(u['circles'])),
                KpiCard(
                  label: 'Reminders',
                  value: count(u['reminders']),
                  hint: 'count only',
                ),
              ],
            ),
            if (role.canAct) ...[
              const SectionTitle('Actions'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!suspended)
                    FilledButton.tonalIcon(
                      key: const Key('act-suspend'),
                      icon: const Icon(Icons.block),
                      label: const Text('Suspend'),
                      onPressed: () => act(
                        'Suspend this account?',
                        'Suspend',
                        (r) => api.suspend(userId, r),
                        message: 'They are signed out everywhere and can’t sign in or use the app. Data is kept and reminders already on their phone keep ringing.',
                        danger: true,
                      ),
                    )
                  else
                    FilledButton.tonalIcon(
                      key: const Key('act-unsuspend'),
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Unsuspend'),
                      onPressed: () => act(
                        'Restore this account?',
                        'Unsuspend',
                        (r) => api.unsuspend(userId, r),
                      ),
                    ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out everywhere'),
                    onPressed: () => act(
                      'Sign out of all devices?',
                      'Sign out everywhere',
                      (r) => api.signOutEverywhere(userId, r),
                    ),
                  ),
                  if (u['deletion_after'] != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.restore),
                      label: const Text('Cancel deletion'),
                      onPressed: () => act(
                        'Cancel the pending deletion?',
                        'Cancel deletion',
                        (r) => api.cancelDeletion(userId, r),
                      ),
                    ),
                  if (role.isSuper && u['admin_role'] == null)
                    OutlinedButton.icon(
                      key: const Key('act-delete'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Delete now'),
                      onPressed: () => act(
                        'Delete this account now?',
                        'Delete forever',
                        (r) => api.deleteNow(userId, r),
                        message: 'Permanently deletes the account and everything it owns. This can’t be undone.',
                        confirmWord: 'DELETE',
                        danger: true,
                        leave: true,
                      ),
                    ),
                ],
              ),
            ],
            const SectionTitle('Circles and plans'),
            RowsTable(
              rows: circles,
              empty: 'Not in any Circle.',
              cols: [
                Col('Circle', (r) => '${r['name']}'),
                Col('Type', (r) => '${r['type']}'),
                Col('Role', (r) => '${r['role']}'),
                Col('Plan', (r) => '${r['plan']}'),
                Col(
                  'Paid until',
                  (r) => r['paid_until'] == null
                      ? '—'
                      : '${date(r['paid_until'])} (${relative(r['paid_until'])})',
                ),
                Col(
                  'Renews',
                  (r) => r['auto_renews'] == true
                      ? 'auto (${r['provider']})'
                      : (r['paid_until'] == null ? '—' : 'no'),
                ),
                Col('Members', (r) => count(r['members']), numeric: true),
              ],
            ),
            if (role.canAct)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final c in circles.where((c) => c['role'] == 'owner'))
                      TextButton.icon(
                        icon: const Icon(Icons.card_giftcard),
                        label: Text('Grant months on “${c['name']}”'),
                        onPressed: () async {
                          final ok = await showGrantDialog(
                            context,
                            ref,
                            circleId: '${c['id']}',
                            circleType: '${c['type']}',
                          );
                          if (ok) ref.invalidate(userDetailProvider(userId));
                        },
                      ),
                  ],
                ),
              ),
            const SectionTitle('Billing history (Circles they own)'),
            RowsTable(
              rows: [
                for (final b in d['billing'] as List)
                  Map<String, dynamic>.from(b as Map),
              ],
              empty: 'No billing events.',
              cols: [
                Col('When', (r) => dateTime(r['at'])),
                Col('Event', (r) => '${r['type']}'),
                Col('Plan', (r) => '${r['plan'] ?? '—'}'),
                Col(
                  'Amount',
                  (r) =>
                      r['amount_inr'] == null ? '—' : rupees(r['amount_inr']),
                  numeric: true,
                ),
                Col('Via', (r) => '${r['provider']}'),
              ],
            ),
            const SectionTitle('Renewal messages'),
            RowsTable(
              rows: [
                for (final n in d['renewal_notices'] as List)
                  Map<String, dynamic>.from(n as Map),
              ],
              empty: 'None sent.',
              cols: [
                Col('When', (r) => dateTime(r['at'])),
                Col('Step', (r) => '${r['step']}'),
                Col('Channel', (r) => '${r['channel']}'),
                Col('Status', (r) => '${r['status']}'),
              ],
            ),
            const SectionTitle('Admin history'),
            RowsTable(
              rows: [
                for (final a in d['actions'] as List)
                  Map<String, dynamic>.from(a as Map),
              ],
              empty: 'No admin actions.',
              cols: [
                Col('When', (r) => dateTime(r['at'])),
                Col('Action', (r) => '${r['action']}'),
                Col('By', (r) => '${r['actor']}'),
                Col('Reason', (r) => '${r['reason']}'),
              ],
            ),
          ],
        );
      },
    );
  }
}
