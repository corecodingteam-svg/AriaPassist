import 'package:flutter/foundation.dart';

@immutable
class RoutineStep {
  const RoutineStep(this.title, {this.emoji = '•'});
  factory RoutineStep.fromJson(Map<String, dynamic> j) => RoutineStep(
    j['title'] as String? ?? '',
    emoji: j['emoji'] as String? ?? '•',
  );
  final String title;
  final String emoji;
  Map<String, dynamic> toJson() => {'title': title, 'emoji': emoji};

  @override
  bool operator ==(Object other) =>
      other is RoutineStep && other.title == title && other.emoji == emoji;
  @override
  int get hashCode => Object.hash(title, emoji);
}

/// A named sequence ("Morning mode": water → vitamins → stretch → keys).
@immutable
class Routine {
  const Routine({
    required this.id,
    required this.circleId,
    required this.userId,
    required this.name,
    this.emoji = '☀️',
    this.steps = const [],
    this.atMinute,
    this.days = const {1, 2, 3, 4, 5, 6, 7},
    this.runs = const [],
  });

  factory Routine.fromJson({
    required String id,
    required String circleId,
    required String userId,
    required String name,
    Map<String, dynamic>? trigger,
    List<dynamic>? steps,
  }) => Routine(
    id: id,
    circleId: circleId,
    userId: userId,
    name: name,
    emoji: trigger?['emoji'] as String? ?? '☀️',
    atMinute: trigger?['at'] as int?,
    days: {
      ...(trigger?['days'] as List<dynamic>? ?? const [1, 2, 3, 4, 5, 6, 7])
          .cast<int>(),
    },
    runs: [...(trigger?['runs'] as List<dynamic>? ?? const []).cast<String>()],
    steps: [
      for (final s in steps ?? const [])
        if (s is Map<String, dynamic>) RoutineStep.fromJson(s),
    ],
  );

  final String id;
  final String circleId;
  final String userId;
  final String name;
  final String emoji;
  final List<RoutineStep> steps;

  /// Start automatically at this local time (minutes since midnight);
  /// null = start by voice / widget / tap only.
  final int? atMinute;

  /// ISO weekdays the time trigger runs on.
  final Set<int> days;

  /// Local dates (yyyy-MM-dd) the routine was completed — for streaks.
  final List<String> runs;

  /// Stored in routines.trigger_json (+ runs history) / steps_json.
  Map<String, dynamic> triggerJson() => {
    'emoji': emoji,
    'at': atMinute,
    'days': days.toList()..sort(),
    'runs': runs.length > 120 ? runs.sublist(runs.length - 120) : runs,
  };

  Routine copyWith({
    String? name,
    String? emoji,
    List<RoutineStep>? steps,
    int? Function()? atMinute,
    Set<int>? days,
    List<String>? runs,
  }) => Routine(
    id: id,
    circleId: circleId,
    userId: userId,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    steps: steps ?? this.steps,
    atMinute: atMinute != null ? atMinute() : this.atMinute,
    days: days ?? this.days,
    runs: runs ?? this.runs,
  );

  /// Consecutive days completed, ending today or yesterday.
  int streak(DateTime today) {
    final set = runs.toSet();
    String key(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    var d = DateTime(today.year, today.month, today.day);
    if (!set.contains(key(d))) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (set.contains(key(d))) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// Suggested starter routines.
  static const templates = <(String, String, List<RoutineStep>)>[
    (
      'Morning mode',
      '☀️',
      [
        RoutineStep('Drink a glass of water', emoji: '💧'),
        RoutineStep('Take vitamins', emoji: '💊'),
        RoutineStep('Stretch for 5 minutes', emoji: '🧘'),
        RoutineStep('Keys, wallet, phone, mask', emoji: '🔑'),
      ],
    ),
    (
      'Bedtime',
      '🌙',
      [
        RoutineStep('Lock the main door', emoji: '🔒'),
        RoutineStep('Turn off the gas', emoji: '🔥'),
        RoutineStep('Charge your phone', emoji: '🔌'),
        RoutineStep('Set out tomorrow’s clothes', emoji: '👕'),
      ],
    ),
    (
      'Leaving home',
      '🚪',
      [
        RoutineStep('Lights and fans off', emoji: '💡'),
        RoutineStep('Windows closed', emoji: '🪟'),
        RoutineStep('Keys, wallet, phone', emoji: '🔑'),
      ],
    ),
  ];
}
