import 'package:aria_admin/core/format.dart';
import 'package:aria_admin/core/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Step 1: email (or phone) + one-time code. Existing accounts only.
class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key});
  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final _id = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(adminAuthProvider);
    try {
      if (!_sent) {
        await auth.sendCode(_id.text);
        setState(() => _sent = true);
      } else {
        await auth.verifyCode(_id.text, _code.text);
      }
    } on Object catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthCard(
    title: 'Aria Admin',
    subtitle: _sent
        ? 'Enter the 6-digit code we sent.'
        : 'Sign in with your admin email or phone.',
    children: [
      TextField(
        key: const Key('admin-id'),
        controller: _id,
        enabled: !_sent,
        decoration: const InputDecoration(labelText: 'Email or phone'),
        onSubmitted: (_) => _go(),
      ),
      if (_sent) ...[
        const SizedBox(height: 12),
        TextField(
          key: const Key('admin-code'),
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Code'),
          onSubmitted: (_) => _go(),
        ),
      ],
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('admin-continue'),
        onPressed: _busy ? null : _go,
        child: Text(_sent ? 'Verify' : 'Send code'),
      ),
      if (_sent)
        TextButton(
          onPressed: () => setState(() => _sent = false),
          child: const Text('Use a different email or phone'),
        ),
    ],
  );
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(subtitle),
                  const SizedBox(height: 20),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Shared frame for the auth steps.
Widget authCard({
  required String title,
  required String subtitle,
  required List<Widget> children,
}) => _AuthCard(title: title, subtitle: subtitle, children: children);
