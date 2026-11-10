import 'dart:async';

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VerifyOtpScreen extends ConsumerStatefulWidget {
  const VerifyOtpScreen({
    required this.channel,
    required this.destination,
    super.key,
  });

  final OtpChannel channel;
  final String destination;

  @override
  ConsumerState<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends ConsumerState<VerifyOtpScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _controller.text.trim();
    if (code.length != 6) {
      setState(() => _error = tr('Enter the 6-digit code'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .verifyOtp(widget.channel, widget.destination, code);
      // Router redirect takes over once the session exists.
    } on Object {
      if (mounted) {
        setState(() => _error = tr('That code didn’t work. Please try again.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.all(AriaTokens.s5),
        children: [
          Text(tr('Enter code'), style: text.headlineMedium),
          const SizedBox(height: AriaTokens.s2),
          Text(
            tr('We sent a 6-digit code to {0}', [widget.destination]),
            style: text.bodyLarge?.copyWith(color: context.palette.muted),
          ),
          const SizedBox(height: AriaTokens.s5),
          TextField(
            key: const Key('otp-field'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: text.headlineSmall?.copyWith(letterSpacing: 8),
            textAlign: TextAlign.center,
            decoration: InputDecoration(errorText: _error, hintText: '••••••'),
            onChanged: (v) {
              if (v.length == 6) unawaited(_verify());
            },
          ),
          const SizedBox(height: AriaTokens.s4),
          FilledButton(
            onPressed: _busy ? null : _verify,
            child: Text(tr('Verify')),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => ref
                      .read(authRepositoryProvider)
                      .sendOtp(widget.channel, widget.destination),
            child: Text(tr('Resend code')),
          ),
        ],
      ),
    );
  }
}
