import 'dart:async';

import 'package:aria/data/providers.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Server-side account check (start + every resume). Also records "last
/// seen" for active-user reports (the server keeps it to once an hour).
abstract interface class AccountStatusApi {
  /// True when the account is suspended.
  Future<bool> suspended();
}

class SupabaseAccountStatusApi implements AccountStatusApi {
  SupabaseAccountStatusApi(this._db);
  final SupabaseClient _db;

  @override
  Future<bool> suspended() async {
    try {
      await _db.rpc<dynamic>('account_status');
      unawaited(
        _db
            .rpc<dynamic>('touch_last_seen')
            .then((_) {}, onError: (Object _) {}),
      );
      return false;
    } on PostgrestException catch (e) {
      return isSuspendedError(e);
    } on Object catch (e) {
      debugPrint('account status check failed: $e');
      return false; // offline etc. — never lock someone out by mistake
    }
  }
}

/// The API answers 403 "account suspended" (PostgREST pre-request).
bool isSuspendedError(Object e) {
  final s = e.toString().toLowerCase();
  return s.contains('account suspended') ||
      s.contains('pt403') ||
      s.contains('user is banned');
}

final accountStatusApiProvider = Provider<AccountStatusApi?>((ref) {
  try {
    return SupabaseAccountStatusApi(ref.watch(supabaseClientProvider));
  } on Object {
    return null;
  }
});

/// Whether the signed-in account is suspended (false while unknown).
final suspendedProvider = NotifierProvider<Suspended, bool>(Suspended.new);

class Suspended extends Notifier<bool> {
  @override
  bool build() {
    final uid = ref.watch(currentUserIdProvider);
    if (uid != null) {
      unawaited(check());
      final l = AppLifecycleListener(onResume: () => unawaited(check()));
      ref.onDispose(l.dispose);
    }
    return false;
  }

  Future<void> check() async {
    final api = ref.read(accountStatusApiProvider);
    if (api == null || ref.read(currentUserIdProvider) == null) return;
    final s = await api.suspended();
    if (ref.mounted) state = s;
  }
}
