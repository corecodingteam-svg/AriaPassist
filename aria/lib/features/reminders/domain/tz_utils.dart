import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _initialised = false;

/// Loads the tz database once (sync, ~fast; 10-year slice keeps it small).
void ensureTimeZones() {
  if (_initialised) return;
  tzdata.initializeTimeZones();
  _initialised = true;
}

tz.Location locationOf(String? name) {
  ensureTimeZones();
  if (name != null) {
    try {
      return tz.getLocation(name);
    } on Object {
      // fall through
    }
  }
  return tz.local;
}

/// Instant → naive wall-clock (fields local to [zone]) in a UTC container.
DateTime toWall(DateTime instant, String? zone) {
  final t = tz.TZDateTime.from(instant, locationOf(zone));
  return DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second);
}

/// Naive wall-clock in [zone] → UTC instant (DST gaps resolve forward).
///
/// Returns a plain `DateTime`: a `TZDateTime` never compares `==` to a
/// `DateTime` for the same instant, which silently breaks equality checks.
DateTime fromWall(DateTime wall, String? zone) =>
    DateTime.fromMillisecondsSinceEpoch(
      tz.TZDateTime(
        locationOf(zone),
        wall.year,
        wall.month,
        wall.day,
        wall.hour,
        wall.minute,
        wall.second,
      ).millisecondsSinceEpoch,
      isUtc: true,
    );
