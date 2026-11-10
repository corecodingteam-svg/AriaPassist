import 'dart:async';
import 'dart:convert';

import 'package:aria/features/places/domain/place.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/alert_plan.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:aria_device/aria_device.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Native location bridge (overridden in tests).
abstract interface class LocationBridge {
  Future<String> permission();
  Future<String> requestPermission({bool background = false});
  Future<({double lat, double lng, double accuracy})?> current();
  Future<int> setGeofences(List<Map<String, Object?>> fences);
}

class DeviceLocationBridge implements LocationBridge {
  const DeviceLocationBridge();
  @override
  Future<String> permission() => AriaDevice.locationPermission();
  @override
  Future<String> requestPermission({bool background = false}) =>
      AriaDevice.requestLocationPermission(background: background);
  @override
  Future<({double lat, double lng, double accuracy})?> current() =>
      AriaDevice.currentLocation();
  @override
  Future<int> setGeofences(List<Map<String, Object?>> fences) =>
      AriaDevice.setGeofences(fences);
}

final locationBridgeProvider = Provider<LocationBridge>(
  (_) => const DeviceLocationBridge(),
);

final placesProvider = Provider<List<SavedPlace>>(
  (ref) => ref.watch(appPrefsProvider.select((p) => p.places)),
);

/// The OS geofence spec for a location reminder.
Map<String, Object?> fenceFor(Reminder r) {
  final l = r.location!;
  final occurrence = (r.createdAt ?? DateTime.utc(2026)).toUtc();
  return {
    'id': r.id,
    'lat': l.lat,
    'lng': l.lng,
    'radius': l.radiusM.toDouble(),
    'on': l.on.name,
    'title': '📍 ${r.title}',
    'body': l.describe(),
    // Same payload shape as timed alerts → same tap / Done handling.
    'payload': jsonEncode({'r': r.id, 'o': occurrence.toIso8601String()}),
    'category': 'reminder',
    'channel': 'cat_${r.category.name}',
    'notificationId': alertId('geo:${r.id}', occurrence, 0),
  };
}

/// Keeps the phone's geofences equal to my active location reminders.
/// Cleared when the plan no longer includes location reminders.
final geofenceSyncProvider = Provider<void>((ref) {
  final bridge = ref.watch(locationBridgeProvider);
  String? last;
  Timer? debounce;

  void sync() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 500), () async {
      final allowed = ref
          .read(entitlementProvider)
          .can(Feature.locationReminders);
      final settled = ref.read(entitlementSettledProvider);
      final mine = ref.read(myRemindersProvider).value ?? const <Reminder>[];
      final fences = [
        for (final r in mine)
          if (r.isActive && r.location != null && (allowed || !settled))
            fenceFor(r),
      ];
      final key = jsonEncode(fences);
      if (key == last) return;
      last = key;
      if (fences.isNotEmpty && await bridge.permission() == 'denied') return;
      await bridge.setGeofences(fences);
    });
  }

  ref
    ..listen(myRemindersProvider, (_, _) => sync(), fireImmediately: true)
    ..listen(entitlementProvider, (_, _) => sync())
    ..onDispose(() => debounce?.cancel());
});

/// "Save this place": asks for permission in context, then reads one fix.
Future<({double lat, double lng})?> locateHere(LocationBridge bridge) async {
  var perm = await bridge.permission();
  if (perm == 'notDetermined' || perm == 'denied') {
    perm = await bridge.requestPermission();
  }
  if (perm != 'whenInUse' && perm != 'always') return null;
  final fix = await bridge.current();
  return fix == null ? null : (lat: fix.lat, lng: fix.lng);
}
