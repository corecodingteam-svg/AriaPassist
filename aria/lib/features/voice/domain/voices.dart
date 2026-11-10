import 'package:aria/l10n/tr.dart';
import 'package:flutter/foundation.dart';

enum VoiceGender { female, male, any }

/// A selectable voice. Mirrors `public.voices`. Until neural TTS is
/// configured, each voice is rendered by the device TTS engine with its own
/// locale and pitch/rate shaping, so they still sound distinct.
@immutable
class VoiceOption {
  const VoiceOption({
    required this.id,
    required this.name,
    required this._description,
    required this.locale,
    required this.gender,
    this.isFree = false,
    this.pitch = 1.0,
    this.rate = 1.0,
    this.hinglish = false,
  });

  final String id;
  final String name;
  final String _description;
  String get description => tr(_description);

  /// BCP-47 locale for TTS and speech recognition.
  final String locale;
  final VoiceGender gender;
  final bool isFree;

  /// Shaping multipliers applied on top of the user's speed/pitch.
  final double pitch;
  final double rate;

  /// Speaks Romanised Hindi phrasing.
  final bool hinglish;
}

abstract final class Voices {
  static const aria = VoiceOption(
    id: 'aria',
    name: 'Aria',
    description: 'Indian English · warm',
    locale: 'en-IN',
    gender: VoiceGender.female,
    isFree: true,
  );
  static const meera = VoiceOption(
    id: 'meera',
    name: 'Meera',
    description: 'Hindi · soft',
    locale: 'hi-IN',
    gender: VoiceGender.female,
    pitch: 0.95,
    rate: 0.92,
  );
  static const sia = VoiceOption(
    id: 'sia',
    name: 'Sia',
    description: 'Indian English · cheerful & energetic',
    locale: 'en-IN',
    gender: VoiceGender.female,
    pitch: 1.15,
    rate: 1.1,
  );
  static const grace = VoiceOption(
    id: 'grace',
    name: 'Grace',
    description: 'British English · calm',
    locale: 'en-GB',
    gender: VoiceGender.female,
    rate: 0.95,
  );
  static const kavya = VoiceOption(
    id: 'kavya',
    name: 'Kavya',
    description: 'Hinglish · friendly',
    locale: 'en-IN',
    gender: VoiceGender.female,
    pitch: 1.05,
    hinglish: true,
  );
  static const arjun = VoiceOption(
    id: 'arjun',
    name: 'Arjun',
    description: 'Indian English · calm (male)',
    locale: 'en-IN',
    gender: VoiceGender.male,
    pitch: 0.85,
    rate: 0.95,
  );
  static const device = VoiceOption(
    id: 'device',
    name: 'Device voice',
    description: 'Works offline · free',
    locale: 'en-IN',
    gender: VoiceGender.any,
    isFree: true,
  );

  static const List<VoiceOption> all = [
    aria,
    meera,
    sia,
    grace,
    kavya,
    arjun,
    device,
  ];

  static VoiceOption byId(String? id) =>
      all.firstWhere((v) => v.id == id, orElse: () => aria);
}
