import 'dart:math' as math;

/// Exponential backoff with full jitter: 2s, 4s, 8s … capped at 10 min.
Duration backoffFor(
  int attempts, {
  Duration base = const Duration(seconds: 2),
  Duration max = const Duration(minutes: 10),
  math.Random? random,
}) {
  final exp = base.inMilliseconds * math.pow(2, math.max(0, attempts - 1));
  final capped = math.min(exp.toDouble(), max.inMilliseconds.toDouble());
  final r = random ?? math.Random();
  // Full jitter between 50% and 100% to avoid thundering herds.
  final ms = capped * (0.5 + r.nextDouble() * 0.5);
  return Duration(milliseconds: ms.round());
}
