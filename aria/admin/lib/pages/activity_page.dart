import 'package:aria_admin/core/format.dart';
import 'package:aria_admin/pages/subscriptions_page.dart';
import 'package:aria_admin/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ActivityPage extends ConsumerWidget {
  const ActivityPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageFrame(
    title: 'Activity log',
    subtitle: 'Every admin action and every user profile opened. Append-only: nobody can edit or delete it.',
    children: [
      AsyncBody(
        value: ref.watch(reportProvider('admin_activity')),
        builder: (rows) => RowsTable(
          rows: rows,
          onTap: (r) {
            if (r['target_user'] != null) {
              context.go('/users/${r['target_user']}');
            }
          },
          cols: [
            Col('When', (r) => dateTime(r['at'])),
            Col('Who', (r) => '${r['actor']}'),
            Col('Action', (r) => '${r['action']}'),
            Col('Reason', (r) => '${r['reason']}'),
            Col(
              'Details',
              (r) => r['details'] is Map && (r['details'] as Map).isNotEmpty
                  ? '${r['details']}'
                  : '',
            ),
          ],
        ),
      ),
    ],
  );
}
