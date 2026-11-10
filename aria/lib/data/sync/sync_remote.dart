import 'package:supabase_flutter/supabase_flutter.dart';

/// A page of rows pulled from the server.
typedef RemoteRow = Map<String, dynamic>;

/// What the sync engine needs from the backend. Abstracted for tests.
abstract interface class SyncRemote {
  /// Insert-or-update one row. RLS decides whether it's allowed.
  Future<void> upsert(String table, RemoteRow row);

  /// Rows changed after the cursor `(sinceUpdatedAt, sinceId)`, ordered by
  /// `(updated_at, id)` so paging never skips rows sharing a timestamp.
  Future<List<RemoteRow>> pullSince(
    String table, {
    String? sinceUpdatedAt,
    String? sinceId,
    int limit = 500,
  });
}

class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this._client);
  final SupabaseClient _client;

  @override
  Future<void> upsert(String table, RemoteRow row) =>
      _client.from(table).upsert(row);

  @override
  Future<List<RemoteRow>> pullSince(
    String table, {
    String? sinceUpdatedAt,
    String? sinceId,
    int limit = 500,
  }) async {
    var q = _client.from(table).select();
    if (sinceUpdatedAt != null) {
      q = q.or(cursorFilter(sinceUpdatedAt, sinceId));
    }
    final rows = await q
        .order('updated_at', ascending: true)
        .order('id', ascending: true)
        .limit(limit);
    return List<RemoteRow>.from(rows);
  }
}

/// PostgREST `or=` filter for "strictly after (updated_at, id)".
/// Timestamps are double-quoted because they contain `:` and `+`; the
/// client library URL-encodes the whole value, so no manual encoding.
String cursorFilter(String updatedAt, String? id) {
  final ts = '"$updatedAt"';
  if (id == null || id.isEmpty) return 'updated_at.gt.$ts';
  return 'updated_at.gt.$ts,and(updated_at.eq.$ts,id.gt.$id)';
}
