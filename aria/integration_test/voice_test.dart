// Voice on a real device/simulator: TTS speaks, and voice reminders are
// rendered into Library/Sounds as notification sounds.
//   flutter test integration_test/voice_test.dart -d <ios device> \
//     --dart-define-from-file=env/dev.json
import 'dart:io';
import 'dart:typed_data';

import 'package:aria/features/reminders/application/notification_gateway.dart';
import 'package:aria/features/reminders/domain/alert_plan.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/voice/application/voice_engine.dart';
import 'package:aria/features/voice/domain/phrases.dart';
import 'package:aria/features/voice/domain/voice_settings.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide Priority;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('speaks, and renders a voice reminder as a notification sound', (
    tester,
  ) async {
    ensureTimeZones();
    const settings = VoiceSettings();
    final voice = VoiceProfile.of(settings);
    final speaker = DeviceSpeaker();

    // 1. Foreground speech completes (real AVSpeechSynthesizer).
    final sw = Stopwatch()..start();
    await speaker.speak('Testing Aria', voice);
    expect(sw.elapsed, lessThan(const Duration(seconds: 15)));

    // 2. Render the exact line a reminder would speak.
    final line = Phrases(settings).due('Vitamin D', '8:30 AM', seed: 1);
    final name = await speaker.renderNotificationSound(line, voice);
    expect(name, isNotNull, reason: 'synthesizeToFile produced nothing');
    final file = File('${(await getLibraryDirectory()).path}/Sounds/$name');
    expect(file.lengthSync(), greaterThan(10000), reason: 'audio too short');
    final caf = parseCaf(file.readAsBytesSync());
    // UNNotificationSound needs linear PCM (etc.) and < 30 s.
    expect(caf.format, 'lpcm');
    expect(caf.bits, 16);
    expect(caf.seconds, inInclusiveRange(1, 29));

    // Cached: second call is instant and returns the same file.
    final again = Stopwatch()..start();
    expect(await speaker.renderNotificationSound(line, voice), name);
    expect(again.elapsedMilliseconds, lessThan(200));

    // 3. Through the real gateway: a voice alert is scheduled with it.
    SharedPreferences.setMockInitialValues({
      // Skip onboarding (covered by widget tests).
      'aria.prefs.v1': '{"onboarded":true}',
    });
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(settings: LocalNotificationGateway.initSettings);
    await plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, sound: true, provisional: true);
    await plugin.cancelAll();
    final gateway = LocalNotificationGateway(
      plugin,
      voice: PlatformVoiceDelivery(
        speaker,
        await SharedPreferences.getInstance(),
      ),
      profile: () => voice,
    );
    final fire = DateTime.now().toUtc().add(const Duration(hours: 1));
    await gateway.apply([
      PlannedAlert(
        id: 4242,
        reminderId: 'r1',
        occurrence: fire,
        attempt: 0,
        totalAttempts: 1,
        fireAt: fire,
        title: '💊 Vitamin D',
        body: 'Time for this now',
        category: ReminderCategory.health,
        priority: Priority.normal,
        mode: NotifyMode.voice,
        spoken: line,
      ),
    ]);
    final pending = await plugin.pendingNotificationRequests();
    final mine = pending.singleWhere((p) => p.id == 4242);
    expect(mine.payload, contains(name), reason: 'voice file not attached');
    await plugin.cancelAll();
  });
}

/// Minimal CAF reader: format, bit depth and duration from the desc/data
/// chunks (big-endian per Apple's spec).
({String format, int bits, double seconds}) parseCaf(List<int> b) {
  final d = ByteData.sublistView(Uint8List.fromList(b));
  if (String.fromCharCodes(b.sublist(0, 4)) != 'caff') {
    throw const FormatException('not a CAF file');
  }
  var off = 8;
  var rate = 0.0;
  var bytesPerFrame = 0;
  var format = '';
  var bits = 0;
  var dataBytes = 0;
  while (off + 12 <= b.length) {
    final type = String.fromCharCodes(b.sublist(off, off + 4));
    final size = d.getInt64(off + 4);
    final body = off + 12;
    if (type == 'desc') {
      rate = d.getFloat64(body);
      format = String.fromCharCodes(b.sublist(body + 8, body + 12));
      bytesPerFrame = d.getUint32(body + 16);
      bits = d.getUint32(body + 28);
    } else if (type == 'data') {
      dataBytes = size < 0 ? b.length - body - 4 : size - 4; // minus edit count
    }
    if (size < 0) break;
    off = body + size;
  }
  return (
    format: format,
    bits: bits,
    seconds: dataBytes / (rate * bytesPerFrame),
  );
}
