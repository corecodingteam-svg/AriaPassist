import 'dart:async';

import 'package:aria_admin/core/format.dart';
import 'package:aria_admin/core/providers.dart';
import 'package:aria_admin/data/admin_api.dart';
import 'package:aria_admin/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ignore: specify_nonobvious_property_types -- family type is verbose
final userSearchProvider = FutureProvider.family<List<Rec>, String>(
  (ref, q) => ref.watch(adminApiProvider).searchUsers(q),
);

class UsersPage extends ConsumerStatefulWidget {
  const UsersPage({super.key});
  @override
  ConsumerState<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends ConsumerState<UsersPage> {
  final _q = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _q.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(userSearchProvider(_query));
    return PageFrame(
      title: 'Users',
      subtitle: 'Search by phone, email, name or user id. Account metadata only — reminder content is never shown.',
      children: [
        TextField(
          key: const Key('user-search'),
          controller: _q,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: '+91 98…, name@…, name or id',
          ),
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(
              const Duration(milliseconds: 350),
              () => setState(() => _query = v.trim()),
            );
          },
        ),
        const SizedBox(height: 12),
        AsyncBody(
          value: rows,
          builder: (list) => RowsTable(
            rows: list,
            empty: 'No users match.',
            onTap: (r) => context.go('/users/${r['id']}'),
            cols: [
              Col('Name', (r) => '${r['name'] ?? '—'}'),
              Col('Phone / email', (r) => '${r['phone'] ?? r['email'] ?? '—'}'),
              Col('Joined', (r) => date(r['created_at'])),
              Col('Last seen', (r) => relative(r['last_seen_at'])),
              Col('Circles', (r) => count(r['circles']), numeric: true),
              Col('Reminders', (r) => count(r['reminders']), numeric: true),
              const Col('Status', userStatus),
            ],
          ),
        ),
      ],
    );
  }
}

String userStatus(Rec r) => [
  if (r['suspended_at'] != null) 'Suspended',
  if (r['deletion_after'] != null) 'Deleting ${date(r['deletion_after'])}',
  if (r['admin_role'] != null) 'Admin (${r['admin_role']})',
].join(' · ').ifEmpty('Active');

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
