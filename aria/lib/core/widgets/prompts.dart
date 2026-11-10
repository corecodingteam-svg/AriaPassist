import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks for one line of text. The dialog owns its controller, so it's never
/// disposed while the closing animation still draws the field.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  int maxLines = 1,
  Key? fieldKey,
  String action = 'Save',
  bool pin = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _PromptDialog(
    title: title,
    initial: initial,
    hint: hint,
    maxLines: maxLines,
    fieldKey: fieldKey,
    action: action,
    pin: pin,
  ),
);

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.maxLines,
    required this.fieldKey,
    required this.action,
    this.pin = false,
  });
  final String title;
  final String initial;
  final String? hint;
  final int maxLines;
  final Key? fieldKey;
  final String action;

  /// Numeric, obscured, 4 digits.
  final bool pin;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: widget.fieldKey,
      controller: _c,
      autofocus: true,
      maxLines: widget.maxLines,
      minLines: 1,
      textCapitalization: TextCapitalization.sentences,
      keyboardType: widget.pin ? TextInputType.number : null,
      obscureText: widget.pin,
      maxLength: widget.pin ? 4 : null,
      inputFormatters: widget.pin
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      decoration: InputDecoration(hintText: widget.hint),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('Cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _c.text.trim()),
        child: Text(tr(widget.action)),
      ),
    ],
  );
}
