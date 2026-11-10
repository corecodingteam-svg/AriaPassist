import 'package:aria_admin/core/format.dart';
import 'package:aria_admin/pages/subscriptions_page.dart';
import 'package:aria_admin/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MessagingPage extends ConsumerWidget {
  const MessagingPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageFrame(
    title: 'Messaging',
    subtitle: 'WhatsApp reminders and renewal messages. “logged” = not sent (provider keys not set yet).',
    children: [
      AsyncBody(
        value: ref.watch(reportProvider('messaging_daily')),
        builder: (rows) => RowsTable(
          rows: rows,
          empty: 'No messages yet.',
          cols: [
            Col('Day', (r) => date(r['day'])),
            Col('Kind', (r) => '${r['kind']}'),
            Col('Status', (r) => '${r['status']}'),
            Col('Messages', (r) => count(r['messages']), numeric: true),
          ],
        ),
      ),
    ],
  );
}
