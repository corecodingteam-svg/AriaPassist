import 'package:aria_admin/data/admin_api.dart';
import 'package:aria_admin/data/admin_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridden in main() (and with fakes in tests).
final adminAuthProvider = Provider<AdminAuth>(
  (_) => throw UnimplementedError('override adminAuthProvider'),
);
final adminApiProvider = Provider<AdminApi>(
  (_) => throw UnimplementedError('override adminApiProvider'),
);

/// The signed-in admin's role (null = not an admin). Re-read after sign-in
/// and after the second factor.
final adminRoleProvider = FutureProvider<AdminRole?>((ref) async {
  final auth = ref.watch(adminAuthProvider);
  if (!auth.signedIn) return null;
  return (await ref.watch(adminApiProvider).me()).role;
});
