import 'dart:convert';

import 'package:aria/features/places/domain/place.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/foundation.dart';

/// App UI language. `system` follows the phone (Hindi if the phone is in
/// Hindi, else English).
enum AppLanguage {
  system('Same as phone'),
  en('English'),
  hi('हिन्दी');

  AppLanguage(this.label);
  final String label;
}

enum SwipeAction {
  done('✓ Mark done'),
  snooze('⏰ Snooze'),
  delete('🗑 Delete'),
  none('Nothing');

  SwipeAction(this._label);
  final String _label;
  String get label => tr(_label);
}

enum TimeFormat { system, h12, h24 }

/// Date style used in headers and "when" lines.
enum DateStyle {
  dayMonth('Mon 9 Nov'),
  monthDay('Mon, Nov 9'),
  numeric('09/11/2026');

  DateStyle(this.example);
  final String example;
}

/// One-tap shortcuts shown on Today (spec 6.4, up to 4).
enum QuickAction {
  medicine('💊', 'Medicine', 'Take medicine', ReminderCategory.health),
  water('💧', 'Water', 'Drink water', ReminderCategory.health),
  callMom('📞', 'Call Mom', 'Call Mom', ReminderCategory.people),
  bill('💰', 'Pay a bill', 'Pay bill', ReminderCategory.bills),
  grocery('🛒', 'Grocery', 'Buy groceries', ReminderCategory.home),
  exercise('🏃', 'Exercise', 'Exercise', ReminderCategory.health),
  talk('🎙️', 'Talk', '', ReminderCategory.personal);

  QuickAction(this.emoji, this._label, this.title, this.category);
  final String emoji;
  final String _label;
  String get label => tr(_label);
  final String title;
  final ReminderCategory category;
}

/// Default "parts of the day" (spec 6.4) in minutes since midnight.
@immutable
class DayParts {
  const DayParts({
    this.morning = 8 * 60,
    this.afternoon = 13 * 60,
    this.evening = 18 * 60,
    this.night = 21 * 60,
  });

  factory DayParts.fromJson(Map<String, dynamic>? j) => j == null
      ? const DayParts()
      : DayParts(
          morning: j['morning'] as int? ?? 8 * 60,
          afternoon: j['afternoon'] as int? ?? 13 * 60,
          evening: j['evening'] as int? ?? 18 * 60,
          night: j['night'] as int? ?? 21 * 60,
        );

  final int morning;
  final int afternoon;
  final int evening;
  final int night;

  Map<String, dynamic> toJson() => {
    'morning': morning,
    'afternoon': afternoon,
    'evening': evening,
    'night': night,
  };

  DayParts copyWith({int? morning, int? afternoon, int? evening, int? night}) =>
      DayParts(
        morning: morning ?? this.morning,
        afternoon: afternoon ?? this.afternoon,
        evening: evening ?? this.evening,
        night: night ?? this.night,
      );

  @override
  bool operator ==(Object other) =>
      other is DayParts &&
      other.morning == morning &&
      other.afternoon == afternoon &&
      other.evening == evening &&
      other.night == night;
  @override
  int get hashCode => Object.hash(morning, afternoon, evening, night);
}

/// Everything in Settings › Simplify (6.4), Privacy (6.9) and a few
/// Reminder-style extras (6.2) that aren't voice-specific.
@immutable
class AppPrefs {
  const AppPrefs({
    this.onboarded = false,
    this.userName,
    this.simpleMode = false,
    this.dayParts = const DayParts(),
    this.defaultSnoozeMin = 15,
    this.defaultCategory = ReminderCategory.personal,
    this.defaultPriority = Priority.normal,
    this.quickActions = const [
      QuickAction.medicine,
      QuickAction.water,
      QuickAction.callMom,
      QuickAction.bill,
    ],
    this.swipeEnabled = true,
    this.swipeRight = SwipeAction.done,
    this.swipeLeft = SwipeAction.snooze,
    this.oneHanded = false,
    this.confirmDelete = false,
    this.haptics = true,
    this.sounds = true,
    this.smartSuggestions = true,
    this.weekStartsMonday = true,
    this.timeFormat = TimeFormat.system,
    this.dateStyle = DateStyle.dayMonth,
    this.interactiveTips = true,
    this.dismissedTips = const {},
    this.followUpEnabled = true,
    this.followUpEveryMin = 10,
    this.followUpMax = 3,
    this.fullScreenUrgent = true,
    this.dailySummaryText = true,
    this.hideOnLockScreen = false,
    this.appLock = false,
    this.storeVoiceRecordings = false,
    this.celebrations = true,
    this.analytics = false,
    this.crashReports = true,
    this.appLanguage = AppLanguage.system,
    this.places = const [],
    this.calendarSync = false,
    this.activeCircleId,
  });

  factory AppPrefs.fromJson(Map<String, dynamic> j) {
    T e<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.asNameMap()[name] ?? fallback;
    return AppPrefs(
      onboarded: j['onboarded'] as bool? ?? false,
      userName: j['user_name'] as String?,
      simpleMode: j['simple_mode'] as bool? ?? false,
      dayParts: DayParts.fromJson(j['day_parts'] as Map<String, dynamic>?),
      defaultSnoozeMin: j['default_snooze_min'] as int? ?? 15,
      defaultCategory: e(
        ReminderCategory.values,
        j['default_category'],
        ReminderCategory.personal,
      ),
      defaultPriority: e(
        Priority.values,
        j['default_priority'],
        Priority.normal,
      ),
      quickActions: [
        for (final q
            in (j['quick_actions'] as List<dynamic>? ??
                const ['medicine', 'water', 'callMom', 'bill']))
          ?QuickAction.values.asNameMap()[q],
      ].take(4).toList(),
      swipeEnabled: j['swipe_enabled'] as bool? ?? true,
      swipeRight: e(SwipeAction.values, j['swipe_right'], SwipeAction.done),
      swipeLeft: e(SwipeAction.values, j['swipe_left'], SwipeAction.snooze),
      oneHanded: j['one_handed'] as bool? ?? false,
      confirmDelete: j['confirm_delete'] as bool? ?? false,
      haptics: j['haptics'] as bool? ?? true,
      sounds: j['sounds'] as bool? ?? true,
      smartSuggestions: j['smart_suggestions'] as bool? ?? true,
      weekStartsMonday: j['week_starts_monday'] as bool? ?? true,
      timeFormat: e(TimeFormat.values, j['time_format'], TimeFormat.system),
      dateStyle: e(DateStyle.values, j['date_style'], DateStyle.dayMonth),
      interactiveTips: j['interactive_tips'] as bool? ?? true,
      dismissedTips: {
        ...(j['dismissed_tips'] as List<dynamic>? ?? const []).cast<String>(),
      },
      followUpEnabled: j['follow_up_enabled'] as bool? ?? true,
      followUpEveryMin: j['follow_up_every_min'] as int? ?? 10,
      followUpMax: j['follow_up_max'] as int? ?? 3,
      fullScreenUrgent: j['full_screen_urgent'] as bool? ?? true,
      dailySummaryText: j['daily_summary_text'] as bool? ?? true,
      hideOnLockScreen: j['hide_on_lock_screen'] as bool? ?? false,
      appLock: j['app_lock'] as bool? ?? false,
      storeVoiceRecordings: j['store_voice_recordings'] as bool? ?? false,
      celebrations: j['celebrations'] as bool? ?? true,
      analytics: j['analytics'] as bool? ?? false,
      crashReports: j['crash_reports'] as bool? ?? true,
      appLanguage:
          AppLanguage.values.asNameMap()[j['app_language']] ??
          AppLanguage.system,
      places: [
        for (final p in (j['places'] as List? ?? const []))
          if (p is Map) SavedPlace.fromJson(Map<String, dynamic>.from(p)),
      ],
      calendarSync: j['calendar_sync'] as bool? ?? false,
      activeCircleId: j['active_circle_id'] as String?,
    );
  }

  final bool onboarded;
  final String? userName;
  final bool simpleMode;
  final DayParts dayParts;
  final int defaultSnoozeMin;
  final ReminderCategory defaultCategory;
  final Priority defaultPriority;
  final List<QuickAction> quickActions;
  final bool swipeEnabled;
  final SwipeAction swipeRight;
  final SwipeAction swipeLeft;
  final bool oneHanded;
  final bool confirmDelete;
  final bool haptics;
  final bool sounds;
  final bool smartSuggestions;
  final bool weekStartsMonday;
  final TimeFormat timeFormat;
  final DateStyle dateStyle;
  final bool interactiveTips;
  final Set<String> dismissedTips;
  final bool followUpEnabled;
  final int followUpEveryMin;
  final int followUpMax;
  final bool fullScreenUrgent;
  final bool dailySummaryText;
  final bool hideOnLockScreen;
  final bool appLock;

  /// Always false today: Aria never stores audio (spec 6.9). Kept as an
  /// explicit, visible setting.
  final bool storeVoiceRecordings;

  /// Streaks, confetti and the weekly report card (spec 5.9).
  final bool celebrations;

  /// Opt-in, anonymous usage analytics (off until the user agrees).
  final bool analytics;

  /// Crash reports help fix bugs; contain no reminder content.
  final bool crashReports;

  /// App UI language (voice language is separate, in VoiceSettings).
  final AppLanguage appLanguage;

  /// Saved places for location reminders.
  final List<SavedPlace> places;

  /// Show device calendar events on Today and in the morning briefing.
  final bool calendarSync;

  /// Circle new reminders/lists go into (null = personal). Device-local.
  final String? activeCircleId;

  /// Follow-up settings applied to new reminders.
  FollowUp get followUp => FollowUp(
    enabled: followUpEnabled,
    everyMin: followUpEveryMin,
    maxAttempts: followUpMax,
  );

  /// "Reset to simple defaults" keeps identity/onboarding state.
  AppPrefs resetToDefaults() =>
      AppPrefs(onboarded: onboarded, userName: userName);

  Map<String, dynamic> toJson() => {
    'onboarded': onboarded,
    'user_name': userName,
    'simple_mode': simpleMode,
    'day_parts': dayParts.toJson(),
    'default_snooze_min': defaultSnoozeMin,
    'default_category': defaultCategory.name,
    'default_priority': defaultPriority.name,
    'quick_actions': quickActions.map((q) => q.name).toList(),
    'swipe_enabled': swipeEnabled,
    'swipe_right': swipeRight.name,
    'swipe_left': swipeLeft.name,
    'one_handed': oneHanded,
    'confirm_delete': confirmDelete,
    'haptics': haptics,
    'sounds': sounds,
    'smart_suggestions': smartSuggestions,
    'week_starts_monday': weekStartsMonday,
    'time_format': timeFormat.name,
    'date_style': dateStyle.name,
    'interactive_tips': interactiveTips,
    'dismissed_tips': dismissedTips.toList()..sort(),
    'follow_up_enabled': followUpEnabled,
    'follow_up_every_min': followUpEveryMin,
    'follow_up_max': followUpMax,
    'full_screen_urgent': fullScreenUrgent,
    'daily_summary_text': dailySummaryText,
    'hide_on_lock_screen': hideOnLockScreen,
    'app_lock': appLock,
    'store_voice_recordings': storeVoiceRecordings,
    'celebrations': celebrations,
    'analytics': analytics,
    'crash_reports': crashReports,
    'app_language': appLanguage.name,
    'places': [for (final p in places) p.toJson()],
    'calendar_sync': calendarSync,
    'active_circle_id': activeCircleId,
  };

  AppPrefs copyWith({
    bool? onboarded,
    String? Function()? userName,
    bool? simpleMode,
    DayParts? dayParts,
    int? defaultSnoozeMin,
    ReminderCategory? defaultCategory,
    Priority? defaultPriority,
    List<QuickAction>? quickActions,
    bool? swipeEnabled,
    SwipeAction? swipeRight,
    SwipeAction? swipeLeft,
    bool? oneHanded,
    bool? confirmDelete,
    bool? haptics,
    bool? sounds,
    bool? smartSuggestions,
    bool? weekStartsMonday,
    TimeFormat? timeFormat,
    DateStyle? dateStyle,
    bool? interactiveTips,
    Set<String>? dismissedTips,
    bool? followUpEnabled,
    int? followUpEveryMin,
    int? followUpMax,
    bool? fullScreenUrgent,
    bool? dailySummaryText,
    bool? hideOnLockScreen,
    bool? appLock,
    bool? celebrations,
    bool? analytics,
    bool? crashReports,
    AppLanguage? appLanguage,
    List<SavedPlace>? places,
    bool? calendarSync,
    String? Function()? activeCircleId,
  }) => AppPrefs(
    onboarded: onboarded ?? this.onboarded,
    userName: userName != null ? userName() : this.userName,
    simpleMode: simpleMode ?? this.simpleMode,
    dayParts: dayParts ?? this.dayParts,
    defaultSnoozeMin: defaultSnoozeMin ?? this.defaultSnoozeMin,
    defaultCategory: defaultCategory ?? this.defaultCategory,
    defaultPriority: defaultPriority ?? this.defaultPriority,
    quickActions: quickActions ?? this.quickActions,
    swipeEnabled: swipeEnabled ?? this.swipeEnabled,
    swipeRight: swipeRight ?? this.swipeRight,
    swipeLeft: swipeLeft ?? this.swipeLeft,
    oneHanded: oneHanded ?? this.oneHanded,
    confirmDelete: confirmDelete ?? this.confirmDelete,
    haptics: haptics ?? this.haptics,
    sounds: sounds ?? this.sounds,
    smartSuggestions: smartSuggestions ?? this.smartSuggestions,
    weekStartsMonday: weekStartsMonday ?? this.weekStartsMonday,
    timeFormat: timeFormat ?? this.timeFormat,
    dateStyle: dateStyle ?? this.dateStyle,
    interactiveTips: interactiveTips ?? this.interactiveTips,
    dismissedTips: dismissedTips ?? this.dismissedTips,
    followUpEnabled: followUpEnabled ?? this.followUpEnabled,
    followUpEveryMin: followUpEveryMin ?? this.followUpEveryMin,
    followUpMax: followUpMax ?? this.followUpMax,
    fullScreenUrgent: fullScreenUrgent ?? this.fullScreenUrgent,
    dailySummaryText: dailySummaryText ?? this.dailySummaryText,
    hideOnLockScreen: hideOnLockScreen ?? this.hideOnLockScreen,
    appLock: appLock ?? this.appLock,
    celebrations: celebrations ?? this.celebrations,
    analytics: analytics ?? this.analytics,
    crashReports: crashReports ?? this.crashReports,
    appLanguage: appLanguage ?? this.appLanguage,
    places: places ?? this.places,
    calendarSync: calendarSync ?? this.calendarSync,
    activeCircleId: activeCircleId != null
        ? activeCircleId()
        : this.activeCircleId,
  );

  // Deep equality via the canonical JSON (nested lists/maps included).
  @override
  bool operator ==(Object other) =>
      other is AppPrefs && jsonEncode(other.toJson()) == jsonEncode(toJson());
  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}
