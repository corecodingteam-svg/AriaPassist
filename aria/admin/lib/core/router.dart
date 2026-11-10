import 'package:aria_admin/core/providers.dart';
import 'package:aria_admin/data/admin_api.dart';
import 'package:aria_admin/pages/activity_page.dart';
import 'package:aria_admin/pages/admins_page.dart';
import 'package:aria_admin/pages/messaging_page.dart';
import 'package:aria_admin/pages/mfa_page.dart';
import 'package:aria_admin/pages/not_admin_page.dart';
import 'package:aria_admin/pages/overview_page.dart';
import 'package:aria_admin/pages/promos_page.dart';
import 'package:aria_admin/pages/revenue_page.dart';
import 'package:aria_admin/pages/sign_in_page.dart';
import 'package:aria_admin/pages/subscriptions_page.dart';
import 'package:aria_admin/pages/user_detail_page.dart';
import 'package:aria_admin/pages/users_page.dart';
import 'package:aria_admin/widgets/shell.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Pure gate: sign-in → second factor → admin role.
String? adminRedirect({
  required bool signedIn,
  required String aal,
  required AsyncValue<AdminRole?> role,
  required String location,
}) {
  const open = {'/sign-in'};
  if (!signedIn) return open.contains(location) ? null : '/sign-in';
  if (aal != 'aal2') return location == '/mfa' ? null : '/mfa';
  if (role.isLoading) return null;
  if (role.value == null) return location == '/not-admin' ? null : '/not-admin';
  if (location == '/sign-in' ||
      location == '/mfa' ||
      location == '/not-admin') {
    return '/';
  }
  if (location == '/admins' && !(role.value?.isSuper ?? false)) return '/';
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(adminAuthProvider);
  final roleTick = ValueNotifier<int>(0);
  ref
    ..listen(adminRoleProvider, (_, _) => roleTick.value++)
    ..onDispose(roleTick.dispose);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: Listenable.merge([auth, roleTick]),
    redirect: (_, state) => adminRedirect(
      signedIn: auth.signedIn,
      aal: auth.aal,
      role: ref.read(adminRoleProvider),
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInPage()),
      GoRoute(path: '/mfa', builder: (_, _) => const MfaPage()),
      GoRoute(path: '/not-admin', builder: (_, _) => const NotAdminPage()),
      ShellRoute(
        builder: (_, state, child) =>
            AdminShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const OverviewPage()),
          GoRoute(path: '/users', builder: (_, _) => const UsersPage()),
          GoRoute(
            path: '/users/:id',
            builder: (_, s) => UserDetailPage(userId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/subscriptions',
            builder: (_, _) => const SubscriptionsPage(),
          ),
          GoRoute(path: '/revenue', builder: (_, _) => const RevenuePage()),
          GoRoute(path: '/promos', builder: (_, _) => const PromosPage()),
          GoRoute(path: '/messaging', builder: (_, _) => const MessagingPage()),
          GoRoute(path: '/activity', builder: (_, _) => const ActivityPage()),
          GoRoute(path: '/admins', builder: (_, _) => const AdminsPage()),
        ],
      ),
    ],
  );
});
