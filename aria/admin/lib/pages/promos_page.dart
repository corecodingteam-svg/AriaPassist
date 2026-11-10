import 'package:aria_admin/core/format.dart';
import 'package:aria_admin/core/providers.dart';
import 'package:aria_admin/data/admin_api.dart';
import 'package:aria_admin/widgets/common.dart';
import 'package:aria_admin/widgets/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final promosProvider = FutureProvider<List<Rec>>(
  (ref) => ref.watch(adminApiProvider).promos(),
);

class PromosPage extends ConsumerWidget {
  const PromosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canAct = ref.watch(adminRoleProvider).value.canAct;
    return PageFrame(
      title: 'Promo codes',
      subtitle: 'Free time on a plan, redeemed by the Circle owner in the app (Subscription › Have a code?).',
      actions: [
        if (canAct)
          FilledButton.icon(
            key: const Key('new-promo'),
            icon: const Icon(Icons.add),
            label: const Text('New code'),
            onPressed: () async {
              final created = await showDialog<bool>(
                context: context,
                builder: (_) => const _NewPromoDialog(),
              );
              if (created ?? false) ref.invalidate(promosProvider);
            },
          ),
      ],
      children: [
        AsyncBody(
          value: ref.watch(promosProvider),
          builder: (rows) => RowsTable(
            rows: rows,
            empty: 'No promo codes yet.',
            onTap: !canAct
                ? null
                : (r) async {
                    if (r['is_active'] != true) return;
                    final reason = await askReason(
                      context,
                      title: 'Stop code ${r['code']}?',
                      action: 'Disable',
                      danger: true,
                    );
                    if (reason == null || !context.mounted) return;
                    final ok = await runAction(
                      context,
                      () => ref
                          .read(adminApiProvider)
                          .disablePromo('${r['code']}', reason),
                      done: 'Code ${r['code']} disabled',
                    );
                    if (ok) ref.invalidate(promosProvider);
                  },
            cols: [
              Col('Code', (r) => '${r['code']}'),
              Col('Plan', (r) => '${r['plan']}'),
              Col('Days', (r) => '${r['days']}', numeric: true),
              Col(
                'Used',
                (r) => '${r['redemptions']} / ${r['max_redemptions'] ?? '∞'}',
              ),
              Col('Expires', (r) => date(r['expires_at'])),
              Col(
                'Status',
                (r) => r['is_active'] == true
                    ? (canAct ? 'Active · tap to stop' : 'Active')
                    : 'Stopped',
              ),
              Col('Note', (r) => '${r['note'] ?? ''}'),
            ],
          ),
        ),
      ],
    );
  }
}

class _NewPromoDialog extends ConsumerStatefulWidget {
  const _NewPromoDialog();
  @override
  ConsumerState<_NewPromoDialog> createState() => _NewPromoDialogState();
}

class _NewPromoDialogState extends ConsumerState<_NewPromoDialog> {
  final _code = TextEditingController();
  final _max = TextEditingController();
  final _note = TextEditingController();
  final _reason = TextEditingController();
  String _plan = 'personal';
  int _days = 30;
  String? _error;

  @override
  void dispose() {
    for (final c in [_code, _max, _note, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New promo code'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('promo-code'),
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Code (4–20 letters/digits)',
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'personal', label: Text('Personal')),
              ButtonSegment(value: 'family', label: Text('Family')),
              ButtonSegment(value: 'team', label: Text('Team')),
            ],
            selected: {_plan},
            onSelectionChanged: (v) => setState(() => _plan = v.first),
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('7 days')),
              ButtonSegment(value: 30, label: Text('30 days')),
              ButtonSegment(value: 90, label: Text('90 days')),
            ],
            selected: {_days},
            onSelectionChanged: (v) => setState(() => _days = v.first),
          ),
          TextField(
            controller: _max,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Max redemptions (empty = unlimited)',
            ),
          ),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Note (e.g. campaign)',
            ),
          ),
          TextField(
            key: const Key('promo-reason'),
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'Reason (saved in the activity log)',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('promo-create'),
        onPressed: () async {
          try {
            await ref
                .read(adminApiProvider)
                .createPromo(
                  code: _code.text.trim(),
                  plan: _plan,
                  days: _days,
                  maxRedemptions: int.tryParse(_max.text.trim()),
                  expiresAt: null,
                  note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                  reason: _reason.text.trim(),
                );
            if (context.mounted) Navigator.pop(context, true);
          } on Object catch (e) {
            setState(() => _error = friendlyError(e));
          }
        },
        child: const Text('Create'),
      ),
    ],
  );
}
