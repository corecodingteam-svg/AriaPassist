import 'package:aria/core/config/env.dart';
import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Accepts 10-digit Indian mobiles (prefixed +91) or full E.164 numbers.
String? normalisePhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^\d+]'), '');
  if (RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) return '+91$digits';
  if (RegExp(r'^\+\d{10,15}$').hasMatch(digits)) return digits;
  return null;
}

bool isValidEmail(String raw) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(raw.trim());

/// Phone OTP first (primary in India), email OTP as alternative.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _controller = TextEditingController();
  OtpChannel _channel = OtpChannel.phone;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final raw = _controller.text.trim();
    final destination = _channel == OtpChannel.phone
        ? normalisePhone(raw)
        : (isValidEmail(raw) ? raw : null);
    if (destination == null) {
      setState(
        () => _error = _channel == OtpChannel.phone
            ? tr('Enter a valid mobile number')
            : tr('Enter a valid email address'),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendOtp(_channel, destination);
      if (!mounted) return;
      await context.push(
        '/sign-in/verify',
        extra: (channel: _channel, destination: destination),
      );
    } on Object catch (e) {
      setState(
        () => _error = tr('Could not send the code. {0}', [_friendly(e)]),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final isPhone = _channel == OtpChannel.phone;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AriaTokens.s5),
          children: [
            const SizedBox(height: AriaTokens.s6),
            Text(tr('Hi, I’m Aria 👋'), style: text.headlineMedium),
            const SizedBox(height: AriaTokens.s2),
            Text(
              tr('Sign in so I can keep your reminders safe across devices.'),
              style: text.bodyLarge?.copyWith(color: p.muted),
            ),
            const SizedBox(height: AriaTokens.s6),
            SegmentedButton<OtpChannel>(
              segments: [
                ButtonSegment(
                  value: OtpChannel.phone,
                  label: Text(tr('Phone')),
                  icon: const Icon(Icons.phone_iphone_rounded),
                ),
                ButtonSegment(
                  value: OtpChannel.email,
                  label: Text(tr('Email')),
                  icon: const Icon(Icons.mail_outline_rounded),
                ),
              ],
              selected: {_channel},
              onSelectionChanged: (s) => setState(() {
                _channel = s.first;
                _error = null;
                _controller.clear();
              }),
            ),
            const SizedBox(height: AriaTokens.s4),
            TextField(
              key: const Key('sign-in-field'),
              controller: _controller,
              keyboardType: isPhone
                  ? TextInputType.phone
                  : TextInputType.emailAddress,
              autofillHints: [
                if (isPhone)
                  AutofillHints.telephoneNumber
                else
                  AutofillHints.email,
              ],
              decoration: InputDecoration(
                labelText: isPhone ? tr('Mobile number') : tr('Email'),
                prefixText: isPhone ? '+91 ' : null,
                errorText: _error,
              ),
              onSubmitted: (_) => _send(),
            ),
            const SizedBox(height: AriaTokens.s4),
            FilledButton(
              onPressed: _busy ? null : _send,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(tr('Send code')),
            ),
            if (Env.enableGoogleSignIn || Env.enableAppleSignIn) ...[
              const SizedBox(height: AriaTokens.s5),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: AriaTokens.s3),
                    child: Text('or'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: AriaTokens.s4),
            ],
            if (Env.enableGoogleSignIn)
              OutlinedButton.icon(
                onPressed: () =>
                    ref.read(authRepositoryProvider).signInWithGoogle(),
                icon: const Icon(Icons.g_mobiledata_rounded),
                label: Text(tr('Continue with Google')),
              ),
            if (Env.enableAppleSignIn) ...[
              const SizedBox(height: AriaTokens.s3),
              OutlinedButton.icon(
                onPressed: () =>
                    ref.read(authRepositoryProvider).signInWithApple(),
                icon: const Icon(Icons.apple_rounded),
                label: Text(tr('Continue with Apple')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _friendly(Object e) => friendlyAuthError(e);

/// Plain-language sign-in errors (never raw exception text).
String friendlyAuthError(Object e) {
  final s = e.toString().toLowerCase();
  if (s.contains('banned') || s.contains('suspended')) {
    return tr('This account is suspended. Contact support for help.');
  }
  if (s.contains('socket') ||
      s.contains('failed host lookup') ||
      s.contains('connection')) {
    return tr('Check your internet connection and try again.');
  }
  if (s.contains('rate limit') ||
      s.contains('too many') ||
      s.contains('429') ||
      s.contains('only request this after')) {
    return tr('Too many tries. Please wait a minute and try again.');
  }
  if (s.contains('sms') ||
      s.contains('twilio') ||
      s.contains('phone provider') ||
      s.contains('sending')) {
    return tr(
      'We couldn’t send a text to this number right now. Try email instead.',
    );
  }
  if (s.contains('expired') || s.contains('invalid') && s.contains('token')) {
    return tr('That code has expired or is wrong. Ask for a new one.');
  }
  if (s.contains('invalid') && (s.contains('phone') || s.contains('email'))) {
    return tr('That doesn’t look right. Please check and try again.');
  }
  return tr('Something went wrong. Please try again.');
}
