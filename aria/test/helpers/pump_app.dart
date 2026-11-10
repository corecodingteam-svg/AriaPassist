import 'dart:convert';

import 'package:aria/app.dart';
import 'package:aria/core/connectivity.dart';
import 'package:aria/core/telemetry/telemetry.dart';
import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/data/local/app_database.dart';
import 'package:aria/data/providers.dart';
import 'package:aria/features/account/application/account_status.dart';
import 'package:aria/features/account/application/app_lock.dart';
import 'package:aria/features/assistant/application/assistant_controller.dart';
import 'package:aria/features/assistant/data/parser_service.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/calendar/calendar.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/connected/whatsapp_api.dart';
import 'package:aria/features/help/application/reliability.dart';
import 'package:aria/features/places/application/places_providers.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/subscription/data/billing_api.dart';
import 'package:aria/features/voice/application/voice_engine.dart';
import 'package:aria/features/voice/application/voice_providers.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_billing_api.dart';
import 'fake_circle_api.dart';
import 'fakes.dart';

const kTestZone = 'Asia/Kolkata';
const kTestCircle = 'circle-personal';

/// 9 Nov 2026, 10:00 IST — a Monday.
final kTestNow = DateTime.utc(2026, 11, 9, 4, 30);

class TestApp {
  TestApp(
    this.container,
    this.db,
    this.gateway,
    this.auth,
    this.speech,
    this.speaker,
    this.circles,
    this.billing,
    this.location,
    this.calendar,
    this.whatsapp,
    this.telemetry,
    this.account,
  );
  final ProviderContainer container;
  final AppDatabase db;
  final FakeNotificationGateway gateway;
  final FakeAuthRepository auth;
  final FakeSpeechInput speech;
  final FakeSpeaker speaker;
  final FakeCircleApi circles;
  final FakeBillingApi billing;
  final FakeLocationBridge location;
  final FakeCalendarBridge calendar;
  final FakeWhatsAppApi whatsapp;
  final FakeTelemetry telemetry;
  final FakeAccountStatus account;
}

AppDatabase memoryDb() => AppDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);

/// Seeds the personal circle (and owner membership) a real sign-up + first
/// sync would provide.
Future<void> seedCircle(AppDatabase db, String userId) async {
  await db
      .into(db.circles)
      .insert(
        CirclesCompanion.insert(
          id: kTestCircle,
          name: 'Personal',
          type: 'personal',
          ownerId: userId,
          planId: const Value('plan-free'),
        ),
      );
  await db
      .into(db.memberships)
      .insert(
        MembershipsCompanion.insert(
          id: 'm-$userId',
          circleId: kTestCircle,
          userId: userId,
          role: 'owner',
          status: 'active',
        ),
      );
}

Future<TestApp> pumpApp(
  WidgetTester tester, {
  required FakeAuthRepository auth,
  bool online = true,
  DateTime? now,
  bool onboarded = true,
  Map<String, dynamic> prefs = const {},

  /// Plan of the personal circle (most UI tests want premium unlocked).
  String plan = 'personal',
  FakeAuthenticator? authenticator,
}) async {
  ensureTimeZones();
  // A typical phone: 360×800 dp.
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    kAppPrefsKey: jsonEncode({'onboarded': onboarded, ...prefs}),
    kPlansCacheKey: jsonEncode([for (final p in kTestPlans) p.toJson()]),
  });
  final sharedPrefs = await SharedPreferences.getInstance();
  final db = memoryDb();
  final gateway = FakeNotificationGateway();
  final speech = FakeSpeechInput();
  final speaker = FakeSpeaker();
  if (auth.currentUserId != null) {
    await seedCircle(db, auth.currentUserId!);
    await setPlan(db, kTestCircle, plan);
  }
  final billing = FakeBillingApi(db);
  final location = FakeLocationBridge();
  final calendar = FakeCalendarBridge();
  final whatsapp = FakeWhatsAppApi();
  final telemetry = FakeTelemetry();
  final account = FakeAccountStatus();
  final clockNow = now ?? kTestNow;
  final circles = FakeCircleApi(db, auth.currentUserId ?? 'nobody');

  final overrides = [
    sharedPreferencesProvider.overrideWithValue(sharedPrefs),
    authenticatorProvider.overrideWithValue(
      authenticator ?? FakeAuthenticator(),
    ),
    deviceHealthProvider.overrideWithValue(FakeDeviceHealth()),
    authRepositoryProvider.overrideWithValue(auth),
    appDatabaseProvider.overrideWithValue(db),
    syncEngineProvider.overrideWithValue(null),
    isOnlineProvider.overrideWith((ref) => Stream.value(online)),
    notificationGatewayProvider.overrideWithValue(gateway),
    clockProvider.overrideWithValue(() => clockNow),
    nowProvider.overrideWith((ref) => Stream.value(clockNow)),
    deviceTimeZoneProvider.overrideWith(DeviceTimeZone.new), // defaults to IST
    speechInputProvider.overrideWithValue(speech),
    speakerProvider.overrideWithValue(speaker),
    voiceDeliveryProvider.overrideWithValue(const NoVoiceDelivery()),
    // On-device parsing only (no network in tests).
    parserServiceProvider.overrideWithValue(ParserService()),
    circleApiProvider.overrideWithValue(circles),
    billingApiProvider.overrideWithValue(billing),
    locationBridgeProvider.overrideWithValue(location),
    calendarBridgeProvider.overrideWithValue(calendar),
    whatsAppApiProvider.overrideWithValue(whatsapp),
    telemetryProvider.overrideWithValue(telemetry),
    accountStatusApiProvider.overrideWithValue(account),
  ];
  // An owned ProviderScope: when the test framework unmounts the tree, the
  // container (and every timer/subscription it owns) is disposed with it.
  addTearDown(() async {
    // Unmount (disposing providers and their live queries) before closing
    // the DB; otherwise a failed test can hang in teardown.
    await tester.pumpWidget(const SizedBox.shrink());
    await db.close();
  });
  await tester.pumpWidget(
    ProviderScope(overrides: overrides, child: const AriaApp()),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(AriaApp)),
  );
  return TestApp(
    container,
    db,
    gateway,
    auth,
    speech,
    speaker,
    circles,
    billing,
    location,
    calendar,
    whatsapp,
    telemetry,
    account,
  );
}
