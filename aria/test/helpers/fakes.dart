import 'package:aria/core/telemetry/telemetry.dart';
import 'package:aria/data/sync/sync_remote.dart';
import 'package:aria/features/account/application/account_status.dart';
import 'package:aria/features/account/application/app_lock.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/calendar/calendar.dart';
import 'package:aria/features/connected/whatsapp_api.dart';
import 'package:aria/features/help/application/reliability.dart';
import 'package:aria/features/places/application/places_providers.dart';
import 'package:aria/features/reminders/application/notification_gateway.dart';
import 'package:aria/features/reminders/domain/alert_plan.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/voice/application/speech_input.dart';
import 'package:aria/features/voice/application/voice_engine.dart';

// ignore_for_file: prefer_initializing_formals -- private field, public named param

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository({String? userId}) : _userId = userId;
  String? _userId;
  final sent = <String>[];

  @override
  String? get currentUserId => _userId;

  void signInAs(String? id) {
    _userId = id;
    notifyListeners();
  }

  @override
  Future<void> sendOtp(OtpChannel channel, String destination) async =>
      sent.add(destination);

  @override
  Future<void> verifyOtp(
    OtpChannel channel,
    String destination,
    String code,
  ) async {
    if (code != '123456') throw Exception('bad code');
    signInAs('user-1');
  }

  @override
  Future<void> signInWithApple() async {}
  @override
  Future<void> signInWithGoogle() async {}
  @override
  Future<void> signOut() async => signInAs(null);
}

/// In-memory server: stamps updated_at like the Postgres trigger does.
class FakeSyncRemote implements SyncRemote {
  final tables = <String, Map<String, RemoteRow>>{};
  final failFor = <String>{}; // entity ids whose push throws
  int pushCalls = 0;
  int _tick = 0;

  String _stamp() {
    _tick++;
    return DateTime.utc(
      2026,
      11,
      8,
      10,
    ).add(Duration(seconds: _tick)).toIso8601String();
  }

  /// Simulates a change made by another device.
  void serverWrite(String table, RemoteRow row) {
    tables.putIfAbsent(table, () => {})[row['id'] as String] = {
      ...row,
      'updated_at': _stamp(),
    };
  }

  @override
  Future<void> upsert(String table, RemoteRow row) async {
    pushCalls++;
    if (failFor.contains(row['id'])) throw Exception('network down');
    serverWrite(table, row);
  }

  @override
  Future<List<RemoteRow>> pullSince(
    String table, {
    String? sinceUpdatedAt,
    String? sinceId,
    int limit = 500,
  }) async {
    final rows = (tables[table]?.values.toList() ?? [])
      ..sort((a, b) {
        final c = (a['updated_at'] as String).compareTo(
          b['updated_at'] as String,
        );
        return c != 0 ? c : (a['id'] as String).compareTo(b['id'] as String);
      });
    return rows
        .where((r) {
          if (sinceUpdatedAt == null) return true;
          final c = (r['updated_at'] as String).compareTo(sinceUpdatedAt);
          return c > 0 ||
              (c == 0 && (r['id'] as String).compareTo(sinceId ?? '') > 0);
        })
        .take(limit)
        .toList();
  }
}

/// Records what would have been scheduled with the OS.
class FakeNotificationGateway implements NotificationGateway {
  List<PlannedAlert> scheduled = [];

  /// Reminder alerts only (excludes morning/night briefings).
  List<PlannedAlert> get reminderAlerts =>
      scheduled.where((a) => a.kind == AlertKind.reminder).toList();
  final dismissed = <String>[];
  NotificationStatus current = NotificationStatus.unknown;
  int applyCalls = 0;

  @override
  Future<void> apply(List<PlannedAlert> plan) async {
    applyCalls++;
    scheduled = List.of(plan);
  }

  @override
  Future<void> dismissFor(String reminderId) async => dismissed.add(reminderId);

  @override
  Future<NotificationStatus> status() async => current;

  @override
  Future<bool> requestPermissions() async {
    current = NotificationStatus.unknown;
    return true;
  }

  @override
  Future<void> openExactAlarmSettings() async {}

  int testsSent = 0;
  @override
  Future<void> sendTest(Duration delay) async => testsSent++;
}

class NotificationStatusOff extends NotificationStatus {
  const NotificationStatusOff()
    : super(notificationsAllowed: false, exactAlarmsAllowed: true);
}

extension ReminderTestX on Reminder {
  Reminder copyWithId(String id) => Reminder(
    id: id,
    circleId: circleId,
    createdBy: createdBy,
    assignedTo: assignedTo,
    title: title,
    category: category,
    priority: priority,
    startAt: startAt,
    allDay: allDay,
    rrule: rrule,
    timezone: timezone,
    notifyMode: notifyMode,
    followUp: followUp,
    amount: amount,
    notes: notes,
    status: status,
  );

  Reminder copyWithTitle(String t) => copyWith(title: t);
}

/// Scripted speech recognition.
class FakeSpeechInput implements SpeechInput {
  FakeSpeechInput({this.available = true});
  bool available;
  bool listening = false;
  String? lastLocale;
  void Function(String, {required bool isFinal})? _onResult;

  @override
  Future<bool> init() async => available;

  @override
  Future<void> listen({
    required String localeId,
    required void Function(String text, {required bool isFinal}) onResult,
    void Function(double level)? onLevel,
    Duration listenFor = const Duration(seconds: 30),
    Duration pauseFor = const Duration(seconds: 3),
  }) async {
    lastLocale = localeId;
    listening = true;
    _onResult = onResult;
    onLevel?.call(5);
  }

  /// Simulates the user speaking.
  void say(String text, {bool isFinal = true}) {
    _onResult?.call(text, isFinal: isFinal);
    if (isFinal) listening = false;
  }

  @override
  Future<void> stop() async => listening = false;

  @override
  bool get isListening => listening;
}

class FakeSpeaker implements Speaker {
  final spoken = <String>[];
  VoiceProfile? lastVoice;

  @override
  Future<void> speak(String text, VoiceProfile voice) async {
    spoken.add(text);
    lastVoice = voice;
  }

  @override
  Future<void> stop() async {}
}

class FakeAuthenticator implements Authenticator {
  bool available = true;
  bool succeed = true;
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return succeed;
  }
}

class FakeDeviceHealth implements DeviceHealth {
  FakeDeviceHealth({this.isAndroid = true, this.maker = 'xiaomi'});
  @override
  final bool isAndroid;
  final String? maker;
  bool exempt = false;
  int autoStartOpened = 0;

  @override
  Future<String?> manufacturer() async => maker;
  @override
  Future<bool> batteryExempt() async => exempt;
  @override
  Future<bool> requestBatteryExemption() async => exempt = true;
  @override
  Future<bool> openAutoStart() async {
    autoStartOpened++;
    return true;
  }

  @override
  Future<bool> openAppSettings() async => true;
}

/// Location bridge stand-in: a fixed position and recorded geofences.
class FakeLocationBridge implements LocationBridge {
  String perm = 'whenInUse';
  ({double lat, double lng, double accuracy})? here = (
    lat: 12.9716,
    lng: 77.5946,
    accuracy: 20,
  );
  List<Map<String, Object?>> fences = const [];
  int requests = 0;

  @override
  Future<String> permission() async => perm;
  @override
  Future<String> requestPermission({bool background = false}) async {
    requests++;
    return perm;
  }

  @override
  Future<({double lat, double lng, double accuracy})?> current() async => here;
  @override
  Future<int> setGeofences(List<Map<String, Object?>> f) async {
    fences = f;
    return f.length;
  }
}

class FakeCalendarBridge implements CalendarBridge {
  String perm = 'notDetermined';
  String grantOnRequest = 'granted';
  List<CalendarEvent> all = const [];
  @override
  Future<String> permission() async => perm;
  @override
  Future<String> requestPermission() async => perm = grantOnRequest;
  @override
  Future<List<CalendarEvent>> events(DateTime from, DateTime to) async =>
      all.where((e) => e.start.isBefore(to) && e.end.isAfter(from)).toList();
}

class FakeWhatsAppApi implements WhatsAppApi {
  String? number;
  Exception? error;
  @override
  Future<String?> status() async => number;
  @override
  Future<String?> setEnabled({required bool enabled}) async {
    if (error != null) throw error!;
    return number = enabled ? '+919888888888' : null;
  }
}

class FakeTelemetry implements Telemetry {
  final events = <(TelemetryEvent, Map<String, Object>)>[];
  ({bool analytics, bool crashes})? consent;
  @override
  Future<void> setConsent({
    required bool analytics,
    required bool crashes,
  }) async => consent = (analytics: analytics, crashes: crashes);
  @override
  void event(TelemetryEvent e, [Map<String, Object> params = const {}]) =>
      events.add((e, params));
  @override
  void recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  }) {}
  @override
  void screen(String name) {}
}

class FakeAccountStatus implements AccountStatusApi {
  bool isSuspended = false;
  @override
  Future<bool> suspended() async => isSuspended;
}
