import 'dart:async';
import 'dart:convert';

import 'package:aria/data/local/app_database.dart';
import 'package:aria/data/sync/local_store.dart';
import 'package:aria/data/sync/sync_remote.dart';
import 'package:flutter/foundation.dart';

@immutable
class SyncResult {
  const SyncResult({
    required this.pushed,
    required this.failed,
    required this.pulled,
  });
  final int pushed;
  final int failed;
  final int pulled;

  static const empty = SyncResult(pushed: 0, failed: 0, pulled: 0);

  SyncResult operator +(SyncResult o) => SyncResult(
    pushed: pushed + o.pushed,
    failed: failed + o.failed,
    pulled: pulled + o.pulled,
  );

  @override
  String toString() =>
      'SyncResult(pushed: $pushed, failed: $failed, '
      'pulled: $pulled)';
}

/// Push-then-pull sync loop. Never runs two passes concurrently; extra
/// triggers during a pass coalesce into one follow-up pass.
///
/// Triggers (wired in `sync_providers.dart`): app start, app resume,
/// connectivity regained, after a local write (debounced), and a retry
/// timer for the next outbox entry whose backoff has elapsed.
class SyncEngine {
  SyncEngine({required this.store, required this.remote, this.pageSize = 500});

  final LocalStore store;
  final SyncRemote remote;
  final int pageSize;

  Future<SyncResult>? _running;
  bool _again = false;
  Timer? _retryTimer;
  Timer? _debounce;
  bool _disposed = false;

  /// Request a sync soon (debounced 1.5 s) — call after local writes.
  void requestSync() {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), () {
      unawaited(syncNow());
    });
  }

  /// Runs a sync pass now. If one is already running, the caller joins it
  /// and a follow-up pass is folded into the same future, so the returned
  /// future only completes once changes made before the call are covered.
  Future<SyncResult> syncNow() {
    if (_disposed) return Future.value(SyncResult.empty);
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<SyncResult> _loop() async {
    var total = await _pass();
    while (_again && !_disposed) {
      _again = false;
      total += await _pass();
    }
    return total;
  }

  Future<SyncResult> _pass() async {
    var pushed = 0;
    var failed = 0;
    for (final entry in await store.dueOutbox()) {
      try {
        await remote.upsert(
          entry.entity,
          jsonDecode(entry.payload) as Map<String, dynamic>,
        );
        await store.markPushed(entry);
        pushed++;
      } on Object catch (e) {
        await store.markFailed(entry, e);
        failed++;
      }
    }

    var pulled = 0;
    try {
      for (final table in kSyncedTables) {
        pulled += await _pullTable(table);
      }
    } on Object catch (e) {
      // Offline or server error: try again on the next trigger.
      debugPrint('sync pull failed: $e');
    }

    await _scheduleRetry();
    return SyncResult(pushed: pushed, failed: failed, pulled: pulled);
  }

  Future<int> _pullTable(String table) async {
    var total = 0;
    while (true) {
      final cursor = await store.cursorFor(table);
      final rows = await remote.pullSince(
        table,
        sinceUpdatedAt: cursor?.updatedAt,
        sinceId: cursor?.lastId,
        limit: pageSize,
      );
      await store.applyRemote(table, rows);
      total += rows.length;
      if (rows.length < pageSize) return total;
    }
  }

  Future<void> _scheduleRetry() async {
    _retryTimer?.cancel();
    if (_disposed) return;
    final next = await store.nextRetryAt();
    if (next == null) return;
    final delay = next.difference(DateTime.now().toUtc());
    _retryTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(syncNow()),
    );
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _debounce?.cancel();
  }
}
