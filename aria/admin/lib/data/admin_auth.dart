import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sign-in + authenticator-app (TOTP) second factor.
abstract interface class AdminAuth implements Listenable {
  bool get signedIn;

  /// 'aal1' after the code sign-in, 'aal2' after the second factor.
  String get aal;
  String? get userLabel;

  Future<void> sendCode(String emailOrPhone);
  Future<void> verifyCode(String emailOrPhone, String code);

  /// Verified authenticator factors (empty → must enrol first).
  Future<List<String>> verifiedFactorIds();

  /// Starts enrolment: (factorId, otpauth URI, secret) to show as a QR code.
  Future<({String factorId, String uri, String secret})> enroll();
  Future<void> verifyFactor(String factorId, String code);
  Future<void> signOut();
}

bool isPhone(String s) => RegExp(r'^\+?[0-9 ]{10,15}$').hasMatch(s.trim());

String normalisePhone(String s) {
  final d = s.replaceAll(RegExp('[^0-9]'), '');
  return d.length == 10 ? '+91$d' : '+$d';
}

class SupabaseAdminAuth extends ChangeNotifier implements AdminAuth {
  SupabaseAdminAuth(this._db) {
    _sub = _db.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
  final SupabaseClient _db;
  late final StreamSubscription<AuthState> _sub;

  @override
  bool get signedIn => _db.auth.currentSession != null;

  @override
  String get aal =>
      _db.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel?.name ??
      'aal1';

  @override
  String? get userLabel =>
      _db.auth.currentUser?.email ?? _db.auth.currentUser?.phone;

  @override
  Future<void> sendCode(String id) => isPhone(id)
      ? _db.auth.signInWithOtp(
          phone: normalisePhone(id),
          shouldCreateUser: false,
        )
      : _db.auth.signInWithOtp(email: id.trim(), shouldCreateUser: false);

  @override
  Future<void> verifyCode(String id, String code) => isPhone(id)
      ? _db.auth.verifyOTP(
          phone: normalisePhone(id),
          token: code.trim(),
          type: OtpType.sms,
        )
      : _db.auth.verifyOTP(
          email: id.trim(),
          token: code.trim(),
          type: OtpType.email,
        );

  @override
  Future<List<String>> verifiedFactorIds() async => [
    for (final f in (await _db.auth.mfa.listFactors()).totp)
      if (f.status == FactorStatus.verified) f.id,
  ];

  @override
  Future<({String factorId, String uri, String secret})> enroll() async {
    // Drop half-finished enrolments first (Supabase allows a few at most).
    for (final f in (await _db.auth.mfa.listFactors()).all) {
      if (f.status == FactorStatus.unverified) {
        await _db.auth.mfa.unenroll(f.id);
      }
    }
    final r = await _db.auth.mfa.enroll(
      issuer: 'Aria Admin',
      friendlyName: 'Authenticator ${DateTime.now().millisecondsSinceEpoch}',
    );
    return (factorId: r.id, uri: r.totp!.uri, secret: r.totp!.secret);
  }

  @override
  Future<void> verifyFactor(String factorId, String code) async {
    await _db.auth.mfa.challengeAndVerify(
      factorId: factorId,
      code: code.trim(),
    );
    notifyListeners();
  }

  @override
  Future<void> signOut() => _db.auth.signOut();

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}
