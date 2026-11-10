import 'dart:async';

import 'package:aria/data/local/app_database.dart';
import 'package:aria/data/sync/local_store.dart';
import 'package:aria/data/sync/sync_engine.dart';
import 'package:aria/data/sync/sync_remote.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final localStoreProvider = Provider<LocalStore>(
  (ref) => LocalStore(ref.watch(appDatabaseProvider)),
);

final syncRemoteProvider = Provider<SyncRemote>(
  (ref) => SupabaseSyncRemote(ref.watch(supabaseClientProvider)),
);

/// Lives only while signed in; disposed (and its timers cancelled) on
/// sign-out because it watches the signed-in user id.
final syncEngineProvider = Provider<SyncEngine?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;

  final engine = SyncEngine(
    store: ref.watch(localStoreProvider),
    remote: ref.watch(syncRemoteProvider),
  );

  final connSub = Connectivity().onConnectivityChanged.listen((results) {
    if (results.any((r) => r != ConnectivityResult.none)) {
      unawaited(engine.syncNow());
    }
  });
  final lifecycle = AppLifecycleListener(
    onResume: () => unawaited(engine.syncNow()),
  );

  ref.onDispose(() {
    unawaited(connSub.cancel());
    lifecycle.dispose();
    engine.dispose();
  });

  unawaited(engine.syncNow());
  return engine;
});
