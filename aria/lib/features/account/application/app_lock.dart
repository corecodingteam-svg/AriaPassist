import 'dart:async';

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// Device authentication seam (faked in tests).
abstract interface class Authenticator {
  Future<bool> isAvailable();
  Future<bool> authenticate(String reason);
}

class DeviceAuthenticator implements Authenticator {
  final _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  /// Fingerprint / face, or the device PIN / passcode as fallback.
  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } on Object {
      return false;
    }
  }
}

final authenticatorProvider = Provider<Authenticator>(
  (_) => DeviceAuthenticator(),
);

/// Re-lock after this long in the background.
const kLockAfter = Duration(seconds: 30);

/// Covers the app until the user authenticates, when App lock is on:
/// at launch and after [kLockAfter] in the background.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  late bool _locked = ref.read(appPrefsProvider).appLock;
  DateTime? _backgroundedAt;
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!ref.read(appPrefsProvider).appLock) return;
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _backgroundedAt != null) {
      if (DateTime.now().difference(_backgroundedAt!) > kLockAfter) {
        setState(() => _locked = true);
        unawaited(_unlock());
      }
      _backgroundedAt = null;
    }
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    _authenticating = true;
    final ok = await ref
        .read(authenticatorProvider)
        .authenticate('Unlock Aria');
    _authenticating = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    // Turning App lock off in Settings unlocks immediately.
    if (!ref.watch(appPrefsProvider.select((p) => p.appLock))) _locked = false;
    return Stack(
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            child: Material(
              color: context.palette.background,
              child: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_rounded,
                        size: 56,
                        color: context.palette.primary,
                      ),
                      const SizedBox(height: AriaTokens.s4),
                      Text(
                        tr('Aria is locked'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AriaTokens.s4),
                      FilledButton.icon(
                        onPressed: _unlock,
                        icon: const Icon(Icons.fingerprint_rounded),
                        label: Text(tr('Unlock')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
