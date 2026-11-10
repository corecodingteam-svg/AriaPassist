import 'dart:async';

import 'package:aria/core/config/env.dart';
import 'package:aria/data/providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum OtpChannel { phone, email }

/// Thin seam over Supabase Auth so screens and the router are testable.
abstract class AuthRepository extends ChangeNotifier {
  String? get currentUserId;
  bool get isSignedIn => currentUserId != null;

  /// Sends a 6-digit code by SMS or email. [destination] is E.164 phone
  /// (e.g. +919876543210) or an email address.
  Future<void> sendOtp(OtpChannel channel, String destination);
  Future<void> verifyOtp(OtpChannel channel, String destination, String code);
  Future<void> signInWithGoogle();
  Future<void> signInWithApple();
  Future<void> signOut();
}

class SupabaseAuthRepository extends AuthRepository {
  SupabaseAuthRepository(this._auth) {
    _sub = _auth.onAuthStateChange.listen((_) => notifyListeners());
  }

  final GoTrueClient _auth;
  late final StreamSubscription<AuthState> _sub;

  @override
  String? get currentUserId => _auth.currentUser?.id;

  @override
  Future<void> sendOtp(OtpChannel channel, String destination) =>
      switch (channel) {
        OtpChannel.phone => _auth.signInWithOtp(phone: destination),
        OtpChannel.email => _auth.signInWithOtp(email: destination),
      };

  @override
  Future<void> verifyOtp(OtpChannel channel, String destination, String code) =>
      switch (channel) {
        OtpChannel.phone => _auth.verifyOTP(
          phone: destination,
          token: code,
          type: OtpType.sms,
        ),
        OtpChannel.email => _auth.verifyOTP(
          email: destination,
          token: code,
          type: OtpType.email,
        ),
      };

  // Native Google/Apple flows need console credentials; until configured we
  // use the browser OAuth flow, which redirects back via aria://login.
  @override
  Future<void> signInWithGoogle() => _auth.signInWithOAuth(
    OAuthProvider.google,
    redirectTo: '${Env.deepLinkScheme}://login-callback',
  );

  @override
  Future<void> signInWithApple() => _auth.signInWithOAuth(
    OAuthProvider.apple,
    redirectTo: '${Env.deepLinkScheme}://login-callback',
  );

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repo = SupabaseAuthRepository(ref.watch(supabaseClientProvider).auth);
  ref.onDispose(repo.dispose);
  return repo;
});

/// The signed-in user's id, or null. Rebuilds dependants on sign-in/out.
class CurrentUserId extends Notifier<String?> {
  @override
  String? build() {
    final repo = ref.watch(authRepositoryProvider);
    void listener() => state = repo.currentUserId;
    repo.addListener(listener);
    ref.onDispose(() => repo.removeListener(listener));
    return repo.currentUserId;
  }
}

final currentUserIdProvider = NotifierProvider<CurrentUserId, String?>(
  CurrentUserId.new,
);
