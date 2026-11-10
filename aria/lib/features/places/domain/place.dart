import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:flutter/foundation.dart';

/// A place the user saved ("Home", "Office", "Mum's house") for location
/// reminders. Synced with the rest of the settings.
@immutable
class SavedPlace {
  const SavedPlace({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.emoji = '📍',
    this.radiusM = 150,
  });

  factory SavedPlace.fromJson(Map<String, dynamic> j) => SavedPlace(
    id: j['id'] as String,
    name: j['name'] as String,
    emoji: j['emoji'] as String? ?? '📍',
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    radiusM: (j['radius_m'] as num?)?.toInt() ?? 150,
  );

  final String id;
  final String name;
  final String emoji;
  final double lat;
  final double lng;
  final int radiusM;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'lat': lat,
    'lng': lng,
    'radius_m': radiusM,
  };

  SavedPlace copyWith({
    String? name,
    String? emoji,
    double? lat,
    double? lng,
    int? radiusM,
  }) => SavedPlace(
    id: id,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    radiusM: radiusM ?? this.radiusM,
  );

  LocationTrigger trigger(PlaceTransition on) => LocationTrigger(
    placeId: id,
    placeName: name,
    lat: lat,
    lng: lng,
    radiusM: radiusM,
    on: on,
  );

  /// Suggested names with emoji for the "Add place" sheet.
  static const presets = [
    ('🏠', 'Home'),
    ('🏢', 'Work'),
    ('🛒', 'Market'),
    ('💊', 'Pharmacy'),
    ('🏫', 'School'),
    ('🏋️', 'Gym'),
  ];
}

/// Same place in English, Hinglish and Hindi ("home" = "ghar" = "घर").
const _synonyms = <String, List<String>>{
  'home': ['home', 'house', 'ghar', 'घर'],
  'work': [
    'work',
    'office',
    'workplace',
    'daftar',
    'ऑफ़िस',
    'ऑफिस',
    'दफ़्तर',
    'दफ्तर',
    'काम',
  ],
  'market': ['market', 'dukan', 'grocery store', 'बाज़ार', 'बाजार', 'दुकान'],
  'pharmacy': [
    'pharmacy',
    'chemist',
    'medical store',
    'दवा की दुकान',
    'फ़ार्मेसी',
  ],
  'school': ['school', 'स्कूल'],
  'gym': ['gym', 'जिम'],
};

String _canon(String s) {
  final w = s.toLowerCase().replaceAll(RegExp(r'^(the|my)\s+'), '').trim();
  for (final e in _synonyms.entries) {
    if (e.value.contains(w)) return e.key;
  }
  return w;
}

/// Finds a saved place by spoken name: "home", "the office" → Work, "ghar"
/// → a place saved as "घर", etc.
SavedPlace? matchPlace(List<SavedPlace> places, String spoken) {
  final want = _canon(spoken);
  return places.where((p) => _canon(p.name) == want).firstOrNull ??
      places.where((p) {
        final n = _canon(p.name);
        return n.contains(want) || want.contains(n);
      }).firstOrNull;
}
