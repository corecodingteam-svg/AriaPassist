import 'dart:io' show Platform;

import 'package:aria/features/reminders/application/notification_gateway.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/l10n/tr.dart';
import 'package:aria_device/aria_device.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Device facts the troubleshooter needs (faked in tests).
abstract interface class DeviceHealth {
  bool get isAndroid;
  Future<String?> manufacturer();
  Future<bool> batteryExempt();
  Future<bool> requestBatteryExemption();
  Future<bool> openAutoStart();
  Future<bool> openAppSettings();
}

class PlatformDeviceHealth implements DeviceHealth {
  @override
  bool get isAndroid => !kIsWeb && Platform.isAndroid;
  @override
  Future<String?> manufacturer() => AriaDevice.manufacturer();
  @override
  Future<bool> batteryExempt() => AriaDevice.isIgnoringBatteryOptimizations();
  @override
  Future<bool> requestBatteryExemption() =>
      AriaDevice.requestIgnoreBatteryOptimizations();
  @override
  Future<bool> openAutoStart() => AriaDevice.openAutoStartSettings();
  @override
  Future<bool> openAppSettings() => AriaDevice.openAppSettings();
}

final deviceHealthProvider = Provider<DeviceHealth>(
  (_) => PlatformDeviceHealth(),
);

enum CheckStatus { ok, problem, info }

@immutable
class ReliabilityCheck {
  const ReliabilityCheck({
    required this.id,
    required this.title,
    required this.status,
    required this.detail,
    this.fixLabel,
    this.fix,
  });

  final String id;
  final String title;
  final CheckStatus status;
  final String detail;
  final String? fixLabel;
  final Future<void> Function()? fix;
}

/// Brand-specific steps for phones that kill background apps.
String? oemGuide(String? maker) {
  final m = (maker ?? '').toLowerCase();
  if (RegExp('xiaomi|redmi|poco').hasMatch(m)) {
    return tr(
      'Xiaomi / Redmi / POCO: Settings → Apps → Manage apps → Aria → turn on Autostart, and set Battery saver to “No restrictions”.',
    );
  }
  if (RegExp('oppo|realme').hasMatch(m)) {
    return tr(
      'Oppo / Realme: Settings → Battery → App battery management → Aria → allow background activity and auto launch.',
    );
  }
  if (RegExp('vivo|iqoo').hasMatch(m)) {
    return tr(
      'Vivo / iQOO: Settings → Battery → Background power consumption → Aria → Allow, and turn on Autostart in i Manager.',
    );
  }
  if (m.contains('samsung')) {
    return tr(
      'Samsung: Settings → Battery → Background usage limits → Never sleeping apps → add Aria.',
    );
  }
  if (m.contains('oneplus')) {
    return tr(
      'OnePlus: Settings → Battery → Battery optimisation → Aria → Don’t optimise. You can also lock Aria in Recent apps.',
    );
  }
  return null;
}

/// "Reminders not ringing?" — every check comes with a one-tap fix.
Future<List<ReliabilityCheck>> runReliabilityChecks({
  required NotificationGateway gateway,
  required DeviceHealth device,
}) async {
  final status = await gateway.status();
  final checks = <ReliabilityCheck>[
    ReliabilityCheck(
      id: 'notifications',
      title: tr('Notifications allowed'),
      status: status.notificationsAllowed
          ? CheckStatus.ok
          : CheckStatus.problem,
      detail: status.notificationsAllowed
          ? tr('Aria can show reminders.')
          : tr('Notifications are off, so reminders can’t appear.'),
      fixLabel: status.notificationsAllowed ? null : tr('Allow'),
      fix: status.notificationsAllowed ? null : gateway.requestPermissions,
    ),
  ];
  if (device.isAndroid) {
    checks.add(
      ReliabilityCheck(
        id: 'exact',
        title: tr('Alarms & reminders permission'),
        status: status.exactAlarmsAllowed
            ? CheckStatus.ok
            : CheckStatus.problem,
        detail: status.exactAlarmsAllowed
            ? tr('Reminders ring at the exact minute.')
            : tr(
                'Without it, Android may deliver reminders several minutes late.',
              ),
        fixLabel: status.exactAlarmsAllowed ? null : tr('Allow'),
        fix: status.exactAlarmsAllowed ? null : gateway.openExactAlarmSettings,
      ),
    );
    final exempt = await device.batteryExempt();
    checks.add(
      ReliabilityCheck(
        id: 'battery',
        title: tr('Battery optimisation'),
        status: exempt ? CheckStatus.ok : CheckStatus.problem,
        detail: exempt
            ? tr('Aria is allowed to run in the background.')
            : tr(
                'Battery optimisation can stop reminders when the phone is idle.',
              ),
        fixLabel: exempt ? null : tr('Don’t optimise'),
        fix: exempt
            ? null
            : () async {
                await device.requestBatteryExemption();
              },
      ),
    );
    final guide = oemGuide(await device.manufacturer());
    if (guide != null) {
      checks.add(
        ReliabilityCheck(
          id: 'oem',
          title: tr('Your phone’s extra battery saver'),
          status: CheckStatus.info,
          detail: guide,
          fixLabel: tr('Open settings'),
          fix: () async {
            await device.openAutoStart();
          },
        ),
      );
    }
  }
  return checks;
}

final reliabilityChecksProvider = FutureProvider<List<ReliabilityCheck>>(
  (ref) => runReliabilityChecks(
    gateway: ref.watch(notificationGatewayProvider),
    device: ref.watch(deviceHealthProvider),
  ),
);
