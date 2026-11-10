import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/data/local/app_database.dart';
import 'package:aria/data/providers.dart';
import 'package:aria/data/sync/sync_engine.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/reminders/application/background_actions.dart';
import 'package:aria/features/reminders/application/notification_gateway.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/data/reminder_repository.dart';
import 'package:aria/features/voice/application/voice_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Account-level operations that touch several layers at once.
class SessionService {
  SessionService({
    required this.db,
    required this.auth,
    required this.gateway,
    required this.prefs,
    this.sync,
    this.supabase,
  });

  final AppDatabase db;
  final AuthRepository auth;
  final NotificationGateway gateway;
  final SharedPreferences prefs;
  final SyncEngine? sync;
  final SupabaseClient? supabase;

  /// Pushes pending changes (best effort), silences this user's alerts and
  /// spoken alarms, wipes the local database, then signs out.
  Future<void> signOut() async {
    try {
      await sync?.syncNow().timeout(const Duration(seconds: 5));
    } on Object catch (e) {
      debugPrint('final sync before sign-out failed: $e');
    }
    await gateway.apply(const []);
    await db.wipe();
    await prefs.remove(kUserIdPrefKey);
    await auth.signOut();
  }

  /// Schedules account deletion in 7 days, then signs out.
  Future<DateTime?> requestDeletion() async {
    final res = await supabase?.rpc<String>('request_account_deletion');
    await signOut();
    return res == null ? null : DateTime.parse(res);
  }

  Future<void> cancelDeletion() async {
    await supabase?.rpc<void>('cancel_account_deletion');
  }

  /// When the signed-in account is scheduled for deletion, else null.
  Future<DateTime?> pendingDeletion() async {
    final row = await supabase
        ?.from('account_deletions')
        .select('purge_after')
        .maybeSingle();
    final v = row?['purge_after'] as String?;
    return v == null ? null : DateTime.parse(v);
  }
}

final sessionServiceProvider = Provider<SessionService>((ref) {
  SupabaseClient? client;
  try {
    client = ref.watch(supabaseClientProvider);
  } on Object {
    client = null;
  }
  return SessionService(
    db: ref.watch(appDatabaseProvider),
    auth: ref.watch(authRepositoryProvider),
    gateway: ref.watch(notificationGatewayProvider),
    prefs: ref.watch(sharedPreferencesProvider),
    sync: ref.watch(syncEngineProvider),
    supabase: client,
  );
});

final pendingDeletionProvider = FutureProvider<DateTime?>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return null;
  try {
    return await ref.read(sessionServiceProvider).pendingDeletion();
  } on Object {
    return null; // offline: show nothing
  }
});

// ------------------------------------------------------------------ export

/// "Export my data" (spec 6.9): everything Aria holds locally for the user,
/// as JSON (complete) and CSV (reminders, spreadsheet-friendly).
class DataExporter {
  DataExporter(this.db, this.settings);
  final AppDatabase db;
  final Map<String, dynamic> Function() settings;

  Future<Map<String, dynamic>> buildJson() async {
    final reminders = await db.select(db.reminders).get();
    final events = await db.select(db.reminderEvents).get();
    return {
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'app': 'Aria',
      'reminders': [
        for (final r in reminders)
          {
            ...ReminderRepository.fromRow(r).toRow(),
            'updated_at': r.updatedAt?.toUtc().toIso8601String(),
          },
      ],
      'reminder_events': [
        for (final e in events) ReminderRepository.eventFromRow(e).toRow(),
      ],
      'settings': settings(),
    };
  }

  Future<String> buildCsv() async {
    final rows = await db.select(db.reminders).get();
    String esc(Object? v) {
      final s = v?.toString() ?? '';
      return s.contains(RegExp('[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final b = StringBuffer(
      'title,category,priority,start_at,all_day,repeat,amount,notes,status,deleted\n',
    );
    for (final r in rows) {
      b.writeln(
        [
          r.title,
          r.category,
          r.priority,
          r.startAt?.toUtc().toIso8601String(),
          r.allDay,
          r.rrule,
          r.amount,
          r.notes,
          r.status,
          r.deletedAt != null,
        ].map(esc).join(','),
      );
    }
    return b.toString();
  }

  /// Writes both files and opens the share sheet.
  Future<void> share() async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final json = File('${dir.path}/aria-export-$stamp.json')
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(await buildJson()),
      );
    final csv = File('${dir.path}/aria-reminders-$stamp.csv')
      ..writeAsStringSync(await buildCsv());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(json.path), XFile(csv.path)],
        subject: 'My Aria data',
      ),
    );
  }
}

final dataExporterProvider = Provider<DataExporter>(
  (ref) => DataExporter(
    ref.watch(appDatabaseProvider),
    () => {
      'theme': ref.read(themeControllerProvider).toJson(),
      'voice': ref.read(voiceSettingsProvider).toJson(),
      'preferences': ref.read(appPrefsProvider).toJson(),
    },
  ),
);
