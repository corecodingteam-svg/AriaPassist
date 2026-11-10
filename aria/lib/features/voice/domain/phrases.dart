import 'package:aria/features/voice/domain/voice_settings.dart';
import 'package:aria/features/voice/domain/voices.dart';

/// What Aria says, per personality and language (spec §10). Phrasing
/// varies by a stable seed (e.g. the reminder id) to avoid repetition
/// while staying deterministic for tests and cached audio.
class Phrases {
  Phrases(this.settings) : voice = Voices.byId(settings.voiceId);

  final VoiceSettings settings;
  final VoiceOption voice;

  Personality get _p => settings.personality;

  /// Kavya is a Hinglish voice whatever the language setting says.
  VoiceLanguage get lang =>
      voice.hinglish ? VoiceLanguage.hinglish : settings.language;

  bool get _male => voice.gender == VoiceGender.male;

  /// Hindi verb agreement: "dungi" (female PA) / "dunga" (male PA).
  String get _dunga => _male ? 'dunga' : 'dungi';
  String get _dungaHi => _male ? 'दूँगा' : 'दूँगी';

  static String pick(List<String> options, Object seed) =>
      options[(seed.hashCode & 0x7fffffff) % options.length];

  /// Spoken at fire time. [time] like "8:30 AM"; [extra] e.g. "₹1,840 due".
  String due(String title, String time, {Object seed = 0, String? extra}) {
    final x = extra == null ? '' : ' ${_sentence(extra)}';
    return switch ((lang, _p)) {
      (VoiceLanguage.en, Personality.friendly) => pick([
        "Hey, it's $time — time for $title.$x",
        "It's $time. Just a reminder: $title.$x",
        '$time already! Time for $title.$x',
      ], seed),
      (VoiceLanguage.en, Personality.professional) =>
        "It's $time. Reminder: $title.$x",
      (VoiceLanguage.en, Personality.coach) => pick([
        '$time. $title. Now.$x',
        '$time. $title. No excuses.$x',
      ], seed),
      (VoiceLanguage.en, Personality.caring) => pick([
        "It's $time. A gentle reminder — $title.$x Take care of yourself.",
        "Hi, it's $time. Don't forget: $title.$x",
      ], seed),
      (VoiceLanguage.en, Personality.short) => '$title.$x',
      (VoiceLanguage.hinglish, Personality.friendly) => pick([
        '$time ho gaye — $title ka time hai!$x',
        'Suniye, $time ho gaye. $title.$x',
      ], seed),
      (VoiceLanguage.hinglish, Personality.professional) =>
        '$time — reminder: $title.$x',
      (VoiceLanguage.hinglish, Personality.coach) => '$time. $title. Abhi!$x',
      (VoiceLanguage.hinglish, Personality.caring) =>
        '$time ho gaye. $title yaad se kar lena.$x',
      (VoiceLanguage.hinglish, Personality.short) => '$title.$x',
      (VoiceLanguage.hi, Personality.friendly) => pick([
        '$time बज गए — $title का समय है।$x',
        'सुनिए, $time बज गए। $title।$x',
      ], seed),
      (VoiceLanguage.hi, Personality.professional) =>
        '$time — याद दिला रही हूँ: $title।$x',
      (VoiceLanguage.hi, Personality.coach) => '$time। $title। अभी!$x',
      (VoiceLanguage.hi, Personality.caring) =>
        '$time बज गए। $title याद से कर लीजिए।$x',
      (VoiceLanguage.hi, Personality.short) => '$title।$x',
    };
  }

  String followUp(String title, {required bool last, Object seed = 0}) =>
      switch (lang) {
        VoiceLanguage.en => switch (_p) {
          Personality.coach =>
            last ? 'Last call: $title. Do it now.' : 'Still waiting: $title.',
          Personality.short => title,
          _ =>
            last
                ? 'Last nudge — $title is still pending.'
                : pick([
                    'Just checking — $title is still pending.',
                    'Quick reminder: $title.',
                  ], seed),
        },
        VoiceLanguage.hinglish =>
          last
              ? 'Aakhri baar — $title abhi baaki hai.'
              : '$title abhi baaki hai.',
        VoiceLanguage.hi =>
          last ? 'आख़िरी बार — $title अभी बाकी है।' : '$title अभी बाकी है।',
      };

  /// After creating reminders. [when] like "tomorrow at 8 AM".
  String created(int count, String? when) {
    final what = count == 1
        ? ''
        : (lang == VoiceLanguage.en
              ? '$count reminders. '
              : '$count reminders. ');
    if (when == null) {
      return switch (lang) {
        VoiceLanguage.en =>
          _p == Personality.short
              ? 'Saved.'
              : "${what}Saved. I'll keep it on your list.",
        VoiceLanguage.hinglish => '${what}Save kar liya.',
        VoiceLanguage.hi => '$whatसेव कर लिया।',
      };
    }
    return switch ((lang, _p)) {
      (VoiceLanguage.en, Personality.coach) => '${what}Set. $when.',
      (VoiceLanguage.en, Personality.short) => '${what}Set for $when.',
      (VoiceLanguage.en, Personality.professional) =>
        "${what}Noted. I'll remind you $when.",
      (VoiceLanguage.en, _) => "${what}Done! I'll remind you $when.",
      (VoiceLanguage.hinglish, _) => '${what}Ho gaya! $when yaad dila $_dunga.',
      (VoiceLanguage.hi, _) => '$whatहो गया! $when याद दिला $_dungaHi।',
    };
  }

  String done() => switch ((lang, _p)) {
    (VoiceLanguage.en, Personality.coach) => 'Good. Next.',
    (VoiceLanguage.en, Personality.short) => 'Done.',
    (VoiceLanguage.en, Personality.caring) =>
      "Well done. That's taken care of.",
    (VoiceLanguage.en, _) => "Nice! That's done.",
    (VoiceLanguage.hinglish, _) => 'Badhiya! Ho gaya.',
    (VoiceLanguage.hi, _) => 'बढ़िया! हो गया।',
  };

  String snoozed(String when) => switch (lang) {
    VoiceLanguage.en =>
      _p == Personality.short
          ? 'Snoozed till $when.'
          : "No worries, I'll remind you $when.",
    VoiceLanguage.hinglish => 'Theek hai, $when phir yaad dila $_dunga.',
    VoiceLanguage.hi => 'ठीक है, $when फिर याद दिला $_dungaHi।',
  };

  String deleted(String title) => switch (lang) {
    VoiceLanguage.en => 'Okay, I removed $title.',
    VoiceLanguage.hinglish => 'Theek hai, $title hata diya.',
    VoiceLanguage.hi => 'ठीक है, $title हटा दिया।',
  };

  String listAdded(List<String> items, String list) => switch (lang) {
    VoiceLanguage.en => 'Added ${_join(items)} to your $list list.',
    VoiceLanguage.hinglish => '${_join(items)} $list list mein daal diya.',
    VoiceLanguage.hi => '${_join(items)} $list लिस्ट में जोड़ दिया।',
  };

  String notUnderstood() => switch (lang) {
    VoiceLanguage.en => "Sorry, I didn't catch that. Could you say it again?",
    VoiceLanguage.hinglish => 'Sorry, samajh nahi aaya. Ek baar phir boliye?',
    VoiceLanguage.hi => 'माफ़ कीजिए, समझ नहीं आया। एक बार फिर बोलिए?',
  };

  String greeting(String part) => switch (lang) {
    VoiceLanguage.en => 'Good $part!',
    VoiceLanguage.hinglish => 'Good $part!',
    VoiceLanguage.hi => switch (part) {
      'morning' => 'सुप्रभात!',
      _ => 'नमस्ते!',
    },
  };

  /// "You have 4 things today: water at 11, ..." (morning briefing / query).
  String daySummary({
    required String dayWord,
    required List<String> items,
    required int bills,
    required int birthdays,
  }) {
    if (items.isEmpty) {
      return switch (lang) {
        VoiceLanguage.en => 'Nothing planned for $dayWord. Enjoy!',
        VoiceLanguage.hinglish => '$dayWord kuch plan nahi hai. Enjoy!',
        VoiceLanguage.hi => '$dayWord कुछ तय नहीं है।',
      };
    }
    final top = items.take(3).toList();
    final more = items.length > 3 ? items.length - 3 : 0;
    final extras = [
      if (bills > 0)
        lang == VoiceLanguage.en
            ? '$bills bill${bills == 1 ? '' : 's'} due'
            : '$bills bill due',
      if (birthdays > 0)
        lang == VoiceLanguage.en
            ? '$birthdays birthday${birthdays == 1 ? '' : 's'}'
            : '$birthdays birthday',
    ];
    final tail = extras.isEmpty ? '' : ' ${_sentence(extras.join(', '))}';
    return switch (lang) {
      VoiceLanguage.en =>
        'You have ${items.length} thing${items.length == 1 ? '' : 's'} $dayWord: ${_join(top)}${more > 0 ? ', and $more more' : ''}.$tail',
      VoiceLanguage.hinglish =>
        '$dayWord ${items.length} kaam hain: ${_join(top)}${more > 0 ? ', aur $more' : ''}.$tail',
      VoiceLanguage.hi =>
        '$dayWord ${items.length} काम हैं: ${_join(top)}${more > 0 ? ', और $more' : ''}।$tail',
    };
  }

  String wrapUp({
    required int done,
    required int pending,
    required String tomorrow,
  }) {
    return switch (lang) {
      VoiceLanguage.en => [
        if (done > 0) 'You finished $done thing${done == 1 ? '' : 's'} today.',
        if (pending > 0)
          '$pending ${pending == 1 ? 'is' : 'are'} still pending — want me to move ${pending == 1 ? 'it' : 'them'} to tomorrow?',
        if (done == 0 && pending == 0) 'All clear today.',
        tomorrow,
      ].join(' '),
      VoiceLanguage.hinglish => [
        if (done > 0) 'Aaj $done kaam ho gaye.',
        if (pending > 0) '$pending baaki hain — kal pe shift kar doon?',
        tomorrow,
      ].join(' '),
      VoiceLanguage.hi => [
        if (done > 0) 'आज $done काम हो गए।',
        if (pending > 0) '$pending बाकी हैं — कल पर कर दूँ?',
        tomorrow,
      ].join(' '),
    };
  }

  /// Sample line for the personality picker / voice preview.
  String sample() => due('Vitamin D', '8:30 AM', extra: '4 tablets left');

  static String _sentence(String s) => s.isEmpty
      ? s
      : '${s[0].toUpperCase()}${s.substring(1)}${RegExp(r'[.!?।]$').hasMatch(s) ? '' : '.'}';

  String _join(List<String> xs) {
    if (xs.length <= 1) return xs.join();
    final and = switch (lang) {
      VoiceLanguage.en => 'and',
      VoiceLanguage.hinglish => 'aur',
      VoiceLanguage.hi => 'और',
    };
    return '${xs.sublist(0, xs.length - 1).join(', ')} $and ${xs.last}';
  }
}
