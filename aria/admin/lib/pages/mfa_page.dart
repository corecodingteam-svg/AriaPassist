import 'dart:async';

import 'package:aria_admin/core/format.dart';
import 'package:aria_admin/core/providers.dart';
import 'package:aria_admin/pages/sign_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Step 2: authenticator-app code. First time: scan the QR to enrol.
class MfaPage extends ConsumerStatefulWidget {
  const MfaPage({super.key});
  @override
  ConsumerState<MfaPage> createState() => _MfaPageState();
}

class _MfaPageState extends ConsumerState<MfaPage> {
  final _code = TextEditingController();
  String? _factorId;
  ({String factorId, String uri, String secret})? _enrolling;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final factors = await ref.read(adminAuthProvider).verifiedFactorIds();
      if (!mounted) return;
      setState(() {
        _factorId = factors.firstOrNull;
        _loading = false;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _enroll() async {
    setState(() => _busy = true);
    try {
      final e = await ref.read(adminAuthProvider).enroll();
      setState(() => _enrolling = e);
    } on Object catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final id = _enrolling?.factorId ?? _factorId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(adminAuthProvider).verifyFactor(id, _code.text);
      ref.invalidate(adminRoleProvider);
    } on Object catch (e) {
      setState(() => _error = 'That code didn’t work. ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(adminAuthProvider);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final needsEnrol = _factorId == null;
    return authCard(
      title: 'Two-factor sign-in',
      subtitle: needsEnrol
          ? 'Admins must use an authenticator app (Google Authenticator, 1Password, Authy…).'
          : 'Enter the 6-digit code from your authenticator app.',
      children: [
        if (needsEnrol && _enrolling == null)
          FilledButton(
            key: const Key('mfa-enroll'),
            onPressed: _busy ? null : _enroll,
            child: const Text('Set up authenticator app'),
          ),
        if (_enrolling != null) ...[
          Center(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: QrImageView(
                data: _enrolling!.uri,
                size: 180,
                semanticsLabel: 'Authenticator QR code',
              ),
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            'Or enter this key: ${_enrolling!.secret}',
            key: const Key('mfa-secret'),
            textAlign: TextAlign.center,
          ),
          TextButton(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: _enrolling!.secret)),
            child: const Text('Copy key'),
          ),
        ],
        if (!needsEnrol || _enrolling != null) ...[
          TextField(
            key: const Key('mfa-code'),
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '6-digit code'),
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('mfa-verify'),
            onPressed: _busy ? null : _verify,
            child: const Text('Verify'),
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
        TextButton(
          onPressed: () => unawaited(auth.signOut()),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}
