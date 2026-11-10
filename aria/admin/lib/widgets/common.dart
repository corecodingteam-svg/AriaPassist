import 'package:aria_admin/core/format.dart';
import 'package:aria_admin/data/admin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Page frame: title, optional actions, scrollable body.
class PageFrame extends StatelessWidget {
  const PageFrame({
    required this.title,
    required this.children,
    this.actions = const [],
    this.subtitle,
    super.key,
  });
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(title, style: t.headlineSmall),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: t.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            ...actions,
          ],
        ),
        const SizedBox(height: 20),
        ...children,
      ],
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({
    required this.label,
    required this.value,
    this.hint,
    this.tone,
    this.tile,
    super.key,
  });
  final String label;
  final String value;
  final String? hint;
  final Color? tone;

  /// Draw it as a Neon stat tile in this colour (white text); a plain panel when null.
  final Color? tile;

  @override
  Widget build(BuildContext context) {
    final tile = this.tile;
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final ink = tile == null ? null : Colors.white;
    return SizedBox(
      width: 220,
      child: Card(
        color: tile,
        shape: tile == null
            ? null
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: t.labelLarge?.copyWith(color: ink ?? s.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: t.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: ink ?? tone,
                ),
              ),
              if (hint != null)
                Text(
                  hint!,
                  style: t.bodySmall?.copyWith(color: ink ?? s.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

/// Column spec for [RowsTable].
class Col {
  const Col(this.label, this.cell, {this.numeric = false});
  final String label;
  final String Function(Rec r) cell;
  final bool numeric;
}

/// A simple horizontally-scrollable table of rows.
class RowsTable extends StatelessWidget {
  const RowsTable({
    required this.rows,
    required this.cols,
    this.onTap,
    this.empty = 'Nothing here.',
    super.key,
  });
  final List<Rec> rows;
  final List<Col> cols;
  final void Function(Rec r)? onTap;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Card(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(empty)),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          columns: [
            for (final c in cols)
              DataColumn(label: Text(c.label), numeric: c.numeric),
          ],
          rows: [
            for (final r in rows)
              DataRow(
                onSelectChanged: onTap == null ? null : (_) => onTap!(r),
                cells: [for (final c in cols) DataCell(Text(c.cell(r)))],
              ),
          ],
        ),
      ),
    );
  }
}

/// Loading / error / data for a FutureProvider.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({required this.value, required this.builder, super.key});
  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) => value.when(
    loading: () => const Padding(
      padding: EdgeInsets.all(32),
      child: Center(child: CircularProgressIndicator()),
    ),
    error: (e, _) => Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(friendlyError(e)),
      ),
    ),
    data: builder,
  );
}

/// Every admin action asks for a reason (stored in the audit log). For
/// destructive actions, [confirmWord] must be typed too.
Future<String?> askReason(
  BuildContext context, {
  required String title,
  required String action,
  String? message,
  String? confirmWord,
  bool danger = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ReasonDialog(
    title: title,
    action: action,
    message: message,
    confirmWord: confirmWord,
    danger: danger,
  ),
);

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.action,
    this.message,
    this.confirmWord,
    this.danger = false,
  });
  final String title;
  final String action;
  final String? message;
  final String? confirmWord;
  final bool danger;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _ok =>
      _reason.text.trim().length >= 3 &&
      (widget.confirmWord == null ||
          _confirm.text.trim() == widget.confirmWord);

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(widget.message!),
              ),
            TextField(
              key: const Key('reason'),
              controller: _reason,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason (saved in the activity log)',
                hintText: 'e.g. spam reported in ticket #123',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (widget.confirmWord != null) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('confirm-word'),
                controller: _confirm,
                decoration: InputDecoration(
                  labelText: 'Type ${widget.confirmWord} to confirm',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('reason-ok'),
          style: widget.danger
              ? FilledButton.styleFrom(
                  backgroundColor: s.error,
                  foregroundColor: s.onError,
                )
              : null,
          onPressed: _ok
              ? () => Navigator.pop(context, _reason.text.trim())
              : null,
          child: Text(widget.action),
        ),
      ],
    );
  }
}

/// Runs an admin action and reports the result in a snackbar.
Future<bool> runAction(
  BuildContext context,
  Future<void> Function() op, {
  required String done,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final errorColor = Theme.of(context).colorScheme.error;
  try {
    await op();
    messenger.showSnackBar(SnackBar(content: Text(done)));
    return true;
  } on Object catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(friendlyError(e)), backgroundColor: errorColor),
    );
    return false;
  }
}

/// Simple bar chart (no extra packages).
class Bars extends StatelessWidget {
  const Bars({
    required this.values,
    required this.labels,
    this.height = 140,
    super.key,
  });
  final List<num> values;
  final List<String> labels;
  final double height;

  @override
  Widget build(BuildContext context) {
    final max = values.fold<num>(1, (m, v) => v > m ? v : m);
    final c = Theme.of(context).colorScheme;
    return Semantics(
      label: [
        for (var i = 0; i < values.length; i++) '${labels[i]}: ${values[i]}',
      ].join(', '),
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < values.length; i++)
              Expanded(
                child: Tooltip(
                  message: '${labels[i]}: ${values[i]}',
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    height: (values[i] / max) * (height - 4) + 2,
                    decoration: BoxDecoration(
                      color: c.primary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
