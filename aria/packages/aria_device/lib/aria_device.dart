import 'package:flutter/services.dart';

enum RingerMode { normal, vibrate, silent, unknown }

/// Thin platform bridge, safe to call from background isolates.
abstract final class AriaDevice {
  static const _ch = MethodChannel('com.aria/device');

  /// Android: AudioManager ringer mode. iOS: always `RingerMode.unknown`
  /// (no public API; iOS notification sounds obey the silent switch anyway).
  static Future<RingerMode> ringerMode() async {
    try {
      final m = await _ch.invokeMethod<String>('ringerMode');
      return RingerMode.values.asNameMap()[m] ?? RingerMode.unknown;
    } on Object {
      return RingerMode.unknown;
    }
  }

  /// Speaks with the platform TTS engine; completes when speech ends (or
  /// fails). [alarmStream] makes it audible on silent. [gender] is a hint
  /// ('female' / 'male') for voice selection where the OS exposes it.
  static Future<bool> speak(
    String text, {
    required String locale,
    double rate = 1.0,
    double pitch = 1.0,
    bool alarmStream = false,
    String? gender,
  }) async {
    try {
      return await _ch.invokeMethod<bool>('speak', {
            'text': text,
            'locale': locale,
            'rate': rate,
            'pitch': pitch,
            'alarmStream': alarmStream,
            'gender': gender,
          }) ??
          false;
    } on Object {
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await _ch.invokeMethod<bool>('stop');
    } on Object {
      // nothing to stop
    }
  }

  /// iOS: renders speech into a 16-bit PCM .caf at [path] (usable as a
  /// notification sound). Returns false where unsupported.
  static Future<bool> synthesizeToFile(
    String text, {
    required String path,
    required String locale,
    double rate = 1.0,
    double pitch = 1.0,
    String? gender,
  }) async {
    try {
      return await _ch.invokeMethod<bool>('synthesizeToFile', {
            'text': text,
            'path': path,
            'locale': locale,
            'rate': rate,
            'pitch': pitch,
            'gender': gender,
          }) ??
          false;
    } on Object {
      return false;
    }
  }

  static Future<T?> _call<T>(String method) async {
    try {
      return await _ch.invokeMethod<T>(method);
    } on Object {
      return null;
    }
  }

  /// Lower-case manufacturer ("xiaomi", "samsung", "apple"…), or null.
  static Future<String?> manufacturer() => _call<String>('manufacturer');

  /// Android: whether Aria is exempt from battery optimisation (Doze/OEM
  /// killers). True on iOS and when unknown-safe.
  static Future<bool> isIgnoringBatteryOptimizations() async =>
      await _call<bool>('isIgnoringBatteryOptimizations') ?? true;

  /// Android: opens the system exemption dialog.
  static Future<bool> requestIgnoreBatteryOptimizations() async =>
      await _call<bool>('requestIgnoreBatteryOptimizations') ?? false;

  /// Android: opens the OEM autostart screen when known, else app settings.
  static Future<bool> openAutoStartSettings() async =>
      await _call<bool>('openAutoStartSettings') ?? false;

  static Future<bool> openAppSettings() async =>
      await _call<bool>('openAppSettings') ?? false;

  // ------------------------------------------------------------- location

  /// 'denied' | 'notDetermined' | 'whenInUse' | 'always' | 'restricted'.
  static Future<String> locationPermission() async =>
      await _call<String>('locationPermission') ?? 'denied';

  /// [background]: Android 10+ second step ("Allow all the time"), needed
  /// for geofences while Aria is closed. iOS only needs "While Using".
  static Future<String> requestLocationPermission({
    bool background = false,
  }) async {
    try {
      return await _ch.invokeMethod<String>('requestLocationPermission', {
            'background': background,
          }) ??
          'denied';
    } on Object {
      return 'denied';
    }
  }

  /// One fix, or null (no permission / unavailable).
  static Future<({double lat, double lng, double accuracy})?>
  currentLocation() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('currentLocation');
      if (m == null) return null;
      return (
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        accuracy: (m['accuracy'] as num?)?.toDouble() ?? 0,
      );
    } on Object {
      return null;
    }
  }

  /// Replaces all registered geofences. Each fence: id, lat, lng, radius,
  /// on ('arrive'|'leave'), title, body, payload, category, channel,
  /// notificationId. Returns how many the OS accepted.
  static Future<int> setGeofences(List<Map<String, Object?>> fences) async {
    try {
      return await _ch.invokeMethod<int>('setGeofences', {'fences': fences}) ??
          0;
    } on Object {
      return 0;
    }
  }

  // ------------------------------------------------------------- calendar

  /// 'granted' | 'denied' | 'notDetermined'.
  static Future<String> calendarPermission() async =>
      await _call<String>('calendarPermission') ?? 'denied';

  static Future<String> requestCalendarPermission() async =>
      await _call<String>('requestCalendarPermission') ?? 'denied';

  /// Device calendar events overlapping [from, to).
  static Future<List<Map<String, dynamic>>> calendarEvents(
    DateTime from,
    DateTime to,
  ) async {
    try {
      final list = await _ch.invokeListMethod<Map<dynamic, dynamic>>(
        'calendarEvents',
        {
          'from': from.millisecondsSinceEpoch.toDouble(),
          'to': to.millisecondsSinceEpoch.toDouble(),
        },
      );
      return [
        for (final e in list ?? const <Map<dynamic, dynamic>>[])
          Map<String, dynamic>.from(e),
      ];
    } on Object {
      return const [];
    }
  }
}
