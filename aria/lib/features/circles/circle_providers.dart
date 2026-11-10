import 'package:aria/data/providers.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/circles/data/circle_api.dart';
import 'package:aria/features/circles/data/circle_repository.dart';
import 'package:aria/features/circles/domain/circle.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final circleRepositoryProvider = Provider<CircleRepository?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  return CircleRepository(ref.watch(appDatabaseProvider), userId: uid);
});

final circleApiProvider = Provider<CircleApi>(
  (ref) => SupabaseCircleApi(ref.watch(supabaseClientProvider)),
);

final myCirclesProvider = StreamProvider<List<Circle>>(
  (ref) =>
      ref.watch(circleRepositoryProvider)?.watchMyCircles() ??
      const Stream.empty(),
);

/// The Circle new items go into: the one picked in the switcher if I'm
/// still a member, otherwise my personal Circle.
final activeCircleProvider = Provider<Circle?>((ref) {
  final circles = ref.watch(myCirclesProvider).value ?? const <Circle>[];
  final picked = ref.watch(appPrefsProvider.select((p) => p.activeCircleId));
  return circles.where((c) => c.id == picked).firstOrNull ??
      circles.where((c) => c.isPersonal).firstOrNull ??
      circles.firstOrNull;
});

// ignore: specify_nonobvious_property_types -- family type is verbose
final membersProvider = StreamProvider.family<List<Member>, String>(
  (ref, id) =>
      ref.watch(circleRepositoryProvider)?.watchMembers(id) ??
      const Stream.empty(),
);

/// Names of everyone in my circles (for "from Asha" labels).
final memberNamesProvider = FutureProvider<Map<String, String>>((ref) async {
  ref.watch(myCirclesProvider); // refresh when circles change
  return await ref.watch(circleRepositoryProvider)?.names() ?? const {};
});

/// Admin-set Simple Mode lock on me (dependents).
final mySimpleLockProvider = StreamProvider<SimpleLock?>(
  (ref) =>
      ref.watch(circleRepositoryProvider)?.watchMySimpleLock() ??
      Stream.value(null),
);

/// PIN entered this session to leave a locked Simple Mode.
final simpleUnlockedProvider = NotifierProvider<SimpleUnlocked, bool>(
  SimpleUnlocked.new,
);

class SimpleUnlocked extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(currentUserIdProvider); // re-lock on account change
    return false;
  }

  bool unlock(SimpleLock lock, String pin) {
    final ok = lock.verify(pin);
    if (ok) state = true;
    return ok;
  }
}

/// Simple Mode as the UI should render it: the user's choice, or forced on
/// while an admin's lock is in place and not unlocked with the PIN.
final simpleModeProvider = Provider<bool>((ref) {
  if (ref.watch(appPrefsProvider.select((p) => p.simpleMode))) return true;
  final lock = ref.watch(mySimpleLockProvider).value;
  return lock != null && !ref.watch(simpleUnlockedProvider);
});

/// Locked by an admin and not unlocked this session.
final simpleLockedProvider = Provider<bool>(
  (ref) =>
      ref.watch(mySimpleLockProvider).value != null &&
      !ref.watch(simpleUnlockedProvider),
);

/// Dependents get the simple app with limited settings.
final isDependentProvider = Provider<bool>((ref) {
  final circles = ref.watch(myCirclesProvider).value ?? const <Circle>[];
  return circles.any((c) => c.myRole == CircleRole.dependent);
});

/// Reminders I assigned to others in a circle (dependent monitoring).
// ignore: specify_nonobvious_property_types -- family type is verbose
final assignedByMeProvider = StreamProvider.family<List<Reminder>, String>((
  ref,
  circleId,
) {
  final repo = ref.watch(reminderRepositoryProvider);
  if (repo == null) return const Stream.empty();
  return repo.watchAssignedByMe(circleId);
});
