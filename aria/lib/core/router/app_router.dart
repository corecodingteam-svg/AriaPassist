import 'package:aria/core/telemetry/telemetry.dart';
import 'package:aria/features/account/application/account_status.dart';
import 'package:aria/features/account/presentation/privacy_screen.dart';
import 'package:aria/features/account/presentation/suspended_screen.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/auth/presentation/sign_in_screen.dart';
import 'package:aria/features/auth/presentation/verify_otp_screen.dart';
import 'package:aria/features/circles/presentation/circle_screen.dart';
import 'package:aria/features/connected/connected_apps_screen.dart';
import 'package:aria/features/help/presentation/help_screens.dart';
import 'package:aria/features/lists/presentation/bills_screen.dart';
import 'package:aria/features/lists/presentation/list_detail_screen.dart';
import 'package:aria/features/lists/presentation/lists_hub_screen.dart';
import 'package:aria/features/notes/presentation/notes_screen.dart';
import 'package:aria/features/onboarding/onboarding_screen.dart';
import 'package:aria/features/people/presentation/people_screens.dart';
import 'package:aria/features/placeholders/placeholder_screen.dart';
import 'package:aria/features/places/presentation/places_screen.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/preferences/presentation/simplify_screen.dart';
import 'package:aria/features/profile/me_screen.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/presentation/alert_screen.dart';
import 'package:aria/features/reminders/presentation/missed_screen.dart';
import 'package:aria/features/reminders/presentation/reminder_detail_screen.dart';
import 'package:aria/features/reminders/presentation/reminder_editor_screen.dart';
import 'package:aria/features/reminders/presentation/search_screen.dart';
import 'package:aria/features/routines/presentation/routine_screens.dart';
import 'package:aria/features/settings/appearance_screen.dart';
import 'package:aria/features/settings/settings_screen.dart';
import 'package:aria/features/shell/home_shell.dart';
import 'package:aria/features/splash/splash_screen.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:aria/features/subscription/presentation/subscription_screen.dart';
import 'package:aria/features/today/today_screen.dart';
import 'package:aria/features/voice/presentation/reminder_style_screen.dart';
import 'package:aria/features/voice/presentation/voice_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Pure redirect rule, unit-tested separately.
String? authRedirect({
  required bool signedIn,
  required String location,
  bool onboarded = true,
  bool suspended = false,
}) {
  final onAuthPage = location.startsWith('/sign-in');
  if (!signedIn) return onAuthPage ? null : '/sign-in';
  if (suspended) return location == '/suspended' ? null : '/suspended';
  if (location == '/suspended') return '/today';
  if (!onboarded) return location == '/onboarding' ? null : '/onboarding';
  if (onAuthPage ||
      location == '/splash' ||
      location == '/' ||
      location == '/onboarding') {
    return '/today';
  }
  return null;
}

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  // read, not watch: the router must survive auth changes; it re-runs
  // redirect via refreshListenable instead of being rebuilt.
  final auth = ref.read(authRepositoryProvider);
  final onboarded = ValueNotifier<bool>(ref.read(appPrefsProvider).onboarded);
  final suspended = ValueNotifier<bool>(false);
  ref
    ..listen(
      appPrefsProvider.select((p) => p.onboarded),
      (_, v) => onboarded.value = v,
    )
    ..listen(
      suspendedProvider,
      (_, v) => suspended.value = v,
      fireImmediately: true,
    )
    ..onDispose(onboarded.dispose)
    ..onDispose(suspended.dispose);

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    // Route patterns only (e.g. /reminder/:id), never ids or content.
    observers: [TelemetryRouteObserver(ref.read(telemetryProvider))],
    refreshListenable: Listenable.merge([auth, onboarded, suspended]),
    redirect: (context, state) => authRedirect(
      signedIn: auth.isSignedIn,
      onboarded: onboarded.value,
      suspended: suspended.value,
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/today'),
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/suspended', builder: (_, _) => const SuspendedScreen()),
      GoRoute(
        path: '/sign-in',
        builder: (_, _) => const SignInScreen(),
        routes: [
          GoRoute(
            path: 'verify',
            redirect: (_, state) => state.extra == null ? '/sign-in' : null,
            builder: (_, state) {
              final args =
                  state.extra! as ({OtpChannel channel, String destination});
              return VerifyOtpScreen(
                channel: args.channel,
                destination: args.destination,
              );
            },
          ),
        ],
      ),
      // OAuth deep-link return; the session is picked up by supabase_flutter.
      GoRoute(path: '/login-callback', redirect: (_, _) => '/today'),
      // aria:///talk — home widget, Quick Settings tile, app shortcut.
      GoRoute(path: '/talk', redirect: (_, _) => '/today?talk=1'),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/today',
                // ?talk=1 opens the Talk sheet (widgets, tile, shortcuts).
                builder: (_, s) =>
                    TodayScreen(openTalk: s.uri.queryParameters['talk'] == '1'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/lists',
                builder: (_, _) => const ListsHubScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, s) =>
                        ListDetailScreen(listId: s.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      // Full-screen routes above the shell. '/reminder/new' must precede
      // '/reminder/:id'.
      GoRoute(
        path: '/reminder/new',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ReminderEditorScreen(
          draft: s.extra is Reminder ? s.extra! as Reminder : null,
        ),
      ),
      GoRoute(
        path: '/reminder/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) =>
            ReminderDetailScreen(reminderId: s.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (_, s) =>
                ReminderEditorScreen(reminderId: s.pathParameters['id']),
          ),
          GoRoute(
            path: 'alert',
            builder: (_, s) => AlertScreen(reminderId: s.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(path: '/me', builder: (_, _) => const MeScreen()),
      GoRoute(path: '/notes', builder: (_, _) => const NotesScreen()),
      GoRoute(path: '/bills', builder: (_, _) => const BillsScreen()),
      GoRoute(
        path: '/people',
        builder: (_, _) => const PeopleScreen(),
        routes: [
          GoRoute(path: 'new', builder: (_, _) => const PersonEditorScreen()),
          GoRoute(
            path: ':id',
            builder: (_, s) =>
                PersonEditorScreen(personId: s.pathParameters['id']),
          ),
        ],
      ),
      GoRoute(
        path: '/routines',
        builder: (_, _) => const RoutinesScreen(),
        routes: [
          GoRoute(
            path: ':id/edit',
            builder: (_, s) =>
                RoutineEditorScreen(routineId: s.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/routine/:id',
        builder: (_, s) =>
            RoutineRunnerScreen(routineId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'appearance',
            builder: (_, _) => const AppearanceScreen(),
          ),
          GoRoute(
            path: 'voice',
            builder: (_, _) => const VoiceSettingsScreen(),
          ),
          GoRoute(
            path: 'reminder-style',
            builder: (_, _) => const ReminderStyleScreen(),
          ),
          GoRoute(
            path: 'quiet-hours',
            builder: (_, _) => const ReminderStyleScreen(),
          ),
          GoRoute(
            path: 'routines',
            builder: (_, _) => const BriefingsSettingsScreen(),
          ),
          GoRoute(path: 'simplify', builder: (_, _) => const SimplifyScreen()),
          GoRoute(path: 'privacy', builder: (_, _) => const PrivacyScreen()),
          GoRoute(path: 'places', builder: (_, _) => const PlacesScreen()),
          GoRoute(
            path: 'connected-apps',
            builder: (_, _) => const ConnectedAppsScreen(),
          ),
          GoRoute(
            path: 'help',
            builder: (_, _) => const HelpScreen(),
            routes: [
              GoRoute(
                path: 'troubleshooter',
                builder: (_, _) => const TroubleshooterScreen(),
              ),
            ],
          ),
          GoRoute(
            path: ':group',
            builder: (_, state) {
              final id = state.pathParameters['group'];
              final g = kSettingsGroups.firstWhere(
                (g) => g.id == id,
                orElse: () => kSettingsGroups.first,
              );
              return PlaceholderScreen(
                title: g.title,
                phase: g.phase,
                emoji: g.emoji,
                detail: g.subtitle,
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/circle',
        builder: (_, _) => const CircleScreen(),
        routes: [
          GoRoute(
            path: ':id/audit',
            builder: (_, s) =>
                AuditLogScreen(circleId: s.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/join/:token',
        builder: (_, s) => JoinCircleScreen(token: s.pathParameters['token']!),
      ),
      GoRoute(
        path: '/subscription',
        builder: (_, _) => const SubscriptionScreen(),
      ),
      GoRoute(
        path: '/paywall',
        builder: (_, s) {
          // ?feature=routines, or legacy extra 'voice:<id>'.
          final extra = s.extra is String ? s.extra! as String : '';
          final f =
              Feature.parse(s.uri.queryParameters['feature']) ??
              (extra.startsWith('voice:') ? Feature.premiumVoices : null) ??
              Feature.premiumVoices;
          return PaywallScreen(feature: f);
        },
      ),
      GoRoute(path: '/notifications', builder: (_, _) => const MissedScreen()),
      GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
