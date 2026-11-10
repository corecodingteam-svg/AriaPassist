import 'package:aria/core/router/app_router.dart';
import 'package:aria/core/theme/theme_settings.dart';
import 'package:aria/data/sync/local_store.dart';
import 'package:aria/features/account/application/session_service.dart';
import 'package:aria/features/assistant/domain/rule_parser.dart';
import 'package:aria/features/help/application/reliability.dart';
import 'package:aria/features/preferences/application/settings_sync.dart';
import 'package:aria/features/preferences/domain/app_prefs.dart';
import 'package:aria/features/reminders/application/notification_gateway.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/voice/domain/voice_settings.dart';
import 'package:aria/features/widgets/home_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

DateTime at(int d, int h, [int m = 0]) =>
    fromWall(DateTime.utc(2026, 11, d, h, m), kTestZone);

void main() {
  setUpAll(ensureTimeZones);

  test('AppPrefs JSON round-trips; reset keeps identity', () {
    final p = const AppPrefs().copyWith(
      onboarded: true,
      userName: () => 'Rahul',
      simpleMode: true,
      dayParts: const DayParts(morning: 7 * 60 + 30),
      defaultSnoozeMin: 30,
      quickActions: [QuickAction.water, QuickAction.talk],
      swipeLeft: SwipeAction.delete,
      timeFormat: TimeFormat.h24,
      dateStyle: DateStyle.numeric,
      dismissedTips: {'swipe'},
      hideOnLockScreen: true,
    );
    expect(AppPrefs.fromJson(p.toJson()), p);
    final reset = p.resetToDefaults();
    expect(reset.simpleMode, isFalse);
    expect(reset.onboarded, isTrue);
    expect(reset.userName, 'Rahul');
  });

  test('settings ⇄ user_settings row round-trip (all three blobs)', () {
    const theme = ThemeSettings(
      mode: ThemeMode.dark,
      presetId: 'mint',
      fontSize: FontSizeOption.l,
    );
    const voice = VoiceSettings(
      voiceId: 'meera',
      paName: 'Riya',
      speed: 1.25,
      personality: Personality.caring,
      language: VoiceLanguage.hinglish,
      defaultMode: NotifyMode.voice,
      categoryModes: {ReminderCategory.bills: NotifyMode.text},
      quietHours: QuietHours(enabled: true, start: 22 * 60),
      spokenConfirmations: false,
    );
    final prefs = const AppPrefs(onboarded: true)
        .copyWith(simpleMode: true, followUpEveryMin: 15, followUpMax: 2);
    final row = SettingsMapping.toRow(theme, voice, prefs);
    // Column values satisfy the DB check constraints.
    expect(row['personality'], 'caring');
    expect(row['language'], 'hinglish');
    expect(row['notify_mode_default'], 'voice');
    expect(row['simple_mode'], isTrue);
    expect(row['follow_up_json'], {
      'enabled': true,
      'every_min': 15,
      'max_attempts': 2,
    });

    final (t2, v2, p2) = SettingsMapping.fromRow({
      ...row,
      'updated_at': '2026-11-09T00:00:00Z',
    });
    expect(t2, theme);
    expect(v2, voice);
    expect(p2.simpleMode, isTrue);
    expect(p2.followUpEveryMin, 15);
  });

  test('server defaults (fresh account row) map to sane settings', () {
    final (t, v, p) = SettingsMapping.fromRow({
      'voice_id': 'aria',
      'pa_name': 'Aria',
      'speed': 1.0,
      'pitch': 1.0,
      'personality': 'friendly',
      'language': 'en',
      'notify_mode_default': 'both',
      'category_overrides_json': <String, dynamic>{},
      'theme_json': <String, dynamic>{},
      'simple_mode': false,
      'quiet_hours_json': {
        'enabled': false,
        'start': '23:00',
        'end': '07:00',
        'allow_urgent': true,
      },
      'follow_up_json': {'enabled': true, 'every_min': 10, 'max_attempts': 3},
      'briefing_json': {
        'morning': {'enabled': true, 'at': '07:30'},
      },
      'extra_json': <String, dynamic>{},
    });
    expect(t, const ThemeSettings());
    expect(v.defaultMode, NotifyMode.both);
    expect(
      v.quietHours.enabled,
      isFalse,
      reason: 'legacy string times tolerated',
    );
    expect(p.followUpEnabled, isTrue);
  });

  test('onboarding redirect', () {
    expect(
      authRedirect(signedIn: true, onboarded: false, location: '/today'),
      '/onboarding',
    );
    expect(
      authRedirect(signedIn: true, onboarded: false, location: '/onboarding'),
      isNull,
    );
    expect(authRedirect(signedIn: true, location: '/onboarding'), '/today');
    expect(
      authRedirect(signedIn: false, onboarded: false, location: '/onboarding'),
      '/sign-in',
    );
  });

  test('your "morning" time drives the voice parser', () {
    final p = RuleParser(
      now: at(9, 5),
      zone: kTestZone,
      dayParts: const DayParts(morning: 6 * 60 + 30, evening: 19 * 60),
    );
    expect(p.parse('yoga tomorrow morning').items.single.at, at(10, 6, 30));
    expect(p.parse('call dad this evening').items.single.at, at(9, 19));
  });

  test('widget snapshot: next reminder and today lines', () {
    Reminder r(String id, String t, DateTime s, {bool allDay = false}) =>
        Reminder(
          id: id,
          circleId: 'c',
          createdBy: 'me',
          title: t,
          startAt: s,
          allDay: allDay,
          timezone: kTestZone,
          category: ReminderCategory.health,
        );
    final snap = WidgetSnapshot.build(
      [
        r('a', 'Past', at(9, 8)),
        r('b', 'Vitamin D', at(9, 20, 30)),
        r('c', 'Call', at(9, 21)),
      ],
      userId: 'me',
      now: at(9, 10),
      zone: kTestZone,
    );
    final d = snap.toData();
    expect(d['next_title'], '💊 Vitamin D');
    expect(d['next_time'], contains('8:30'));
    expect(d['next_link'], 'aria:///reminder/b');
    expect(snap.today, hasLength(2));
    expect(d['today_count'], 'Today · 2');
    final empty = WidgetSnapshot.build(
      const [],
      userId: 'me',
      now: at(9, 10),
      zone: kTestZone,
    );
    expect(empty.toData()['next_link'], 'aria:///today');
    expect(empty.toData()['today_lines'], contains('clear day'));
  });

  test('OEM guidance for aggressive battery savers', () {
    expect(oemGuide('Xiaomi'), contains('Autostart'));
    expect(oemGuide('realme'), contains('Oppo / Realme'));
    expect(oemGuide('vivo'), contains('Vivo'));
    expect(oemGuide('samsung'), contains('Never sleeping apps'));
    expect(oemGuide('Google'), isNull);
  });

  test('reliability checks find problems and fix them', () async {
    final gw = FakeNotificationGateway()
      ..current = const NotificationStatus(
        notificationsAllowed: false,
        exactAlarmsAllowed: false,
      );
    final device = FakeDeviceHealth();
    var checks = await runReliabilityChecks(gateway: gw, device: device);
    expect(checks.map((c) => c.id), [
      'notifications',
      'exact',
      'battery',
      'oem',
    ]);
    expect(checks.where((c) => c.status == CheckStatus.problem), hasLength(3));
    for (final c in checks) {
      await c.fix?.call();
    }
    checks = await runReliabilityChecks(gateway: gw, device: device);
    expect(
      checks.firstWhere((c) => c.id == 'notifications').status,
      CheckStatus.ok,
    );
    expect(checks.firstWhere((c) => c.id == 'battery').status, CheckStatus.ok);
    expect(device.autoStartOpened, 1);

    final ios = await runReliabilityChecks(
      gateway: gw,
      device: FakeDeviceHealth(isAndroid: false),
    );
    expect(ios.map((c) => c.id), [
      'notifications',
    ], reason: 'Android-only checks hidden');
  });

  test('sign-out wipes this device and silences alerts', () async {
    SharedPreferences.setMockInitialValues({'aria.user_id': 'u1'});
    final prefs = await SharedPreferences.getInstance();
    final db = memoryDb();
    addTearDown(db.close);
    await seedCircle(db, 'u1');
    await LocalStore(db).write('reminders', {
      'id': 'r1',
      'circle_id': kTestCircle,
      'created_by': 'u1',
      'title': 'Private thing',
    });
    final gw = FakeNotificationGateway()..scheduled = [];
    final auth = FakeAuthRepository(userId: 'u1');
    await SessionService(
      db: db,
      auth: auth,
      gateway: gw,
      prefs: prefs,
    ).signOut();

    expect(await db.select(db.reminders).get(), isEmpty);
    expect(await db.select(db.circles).get(), isEmpty);
    expect(await db.select(db.syncOutbox).get(), isEmpty);
    expect(gw.applyCalls, 1);
    expect(gw.scheduled, isEmpty);
    expect(prefs.getString('aria.user_id'), isNull);
    expect(auth.currentUserId, isNull);
  });

  test('data export: JSON has everything, CSV escapes', () async {
    final db = memoryDb();
    addTearDown(db.close);
    await LocalStore(db).write('reminders', {
      'id': 'r1',
      'circle_id': 'c',
      'created_by': 'u1',
      'title': 'Pay "rent", now',
      'notes': 'line1\nline2',
    });
    final ex = DataExporter(db, () => {'theme': 'x'});
    final json = await ex.buildJson();
    final first = (json['reminders'] as List).single as Map<String, dynamic>;
    expect(first['title'], 'Pay "rent", now');
    expect(json['settings'], {'theme': 'x'});
    final csv = await ex.buildCsv();
    expect(csv, contains('"Pay ""rent"", now"'));
    expect(csv, contains('"line1\nline2"'));
  });
}
