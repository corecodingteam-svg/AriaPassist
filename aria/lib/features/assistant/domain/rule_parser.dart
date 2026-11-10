import 'package:aria/features/assistant/domain/parse_result.dart';
import 'package:aria/features/preferences/domain/app_prefs.dart';
import 'package:aria/features/reminders/domain/recurrence.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';

/// On-device, rule-based parser: the offline path and the fallback when the
/// LLM is slow (> 4 s), unavailable or returns something invalid.
///
/// Handles English, romanised Hinglish and common Devanagari keywords:
/// "remind me to pay rent on the 1st of every month at 10",
/// "kal subah 8 baje dawai lene ki yaad dilana", "add milk and eggs to
/// grocery list", "snooze 20 minutes", "mark vitamin d done", "what's on today".
class RuleParser {
  RuleParser({
    required DateTime now,
    required this.zone,
    this.reminders = const [],
    this.dayParts = const DayParts(),
  }) : now = now.toUtc();

  /// The user's "morning / afternoon / evening / night" (Settings › Simplify).
  final DayParts dayParts;

  final DateTime now;
  final String zone;

  /// Existing reminders for commands; the most relevant (currently due)
  /// first — "snooze 20 minutes" with no name targets reminders.first.
  final List<ReminderRef> reminders;

  late final DateTime _wallNow = toWall(now, zone);
  DateTime get _today =>
      DateTime.utc(_wallNow.year, _wallNow.month, _wallNow.day);

  ParsedCommand parse(String input) {
    final text = normalise(input);
    if (text.isEmpty) {
      return _clarify('Sorry, I didn’t catch that. Could you say it again?');
    }
    return _query(text) ??
        _forgetNote(text) ??
        _routine(text) ??
        _listItem(text) ??
        _note(text) ??
        _snooze(text) ??
        _complete(text) ??
        _delete(text) ??
        _update(text) ??
        _reminders(text);
  }

  /// Only the "when" part of an utterance ("at 8 pm", "kal subah", "every
  /// day") — for follow-ups like "change the time to 8".
  ({DateTime? at, bool allDay, String? rrule}) whenOf(String input) {
    final e = _extract(normalise(input));
    return (at: e.at, allDay: e.allDay, rrule: e.rrule);
  }

  // ------------------------------------------------------------ normalise

  static const _devanagari = {
    'परसों': ' parso ',
    'कल': ' kal ',
    'आज': ' aaj ',
    'सुबह': ' subah ',
    'दोपहर': ' dopahar ',
    'शाम': ' shaam ',
    'रात': ' raat ',
    'बजे': ' baje ',
    'रोज़': ' roz ',
    'रोज': ' roz ',
    'हर': ' har ',
    'दिन': ' din ',
    'महीने': ' mahine ',
    'मिनट': ' minute ',
    'घंटे': ' ghante ',
    'बाद': ' baad ',
    'याद दिलाना': ' yaad dilana ',
    'याद दिला': ' yaad dila ',
    'की': ' ki ',
    'को': ' ko ',
  };

  static String normalise(String input) {
    var s = input.trim();
    _devanagari.forEach((k, v) => s = s.replaceAll(k, v));
    const digits = '०१२३४५६७८९';
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(digits[i], '$i');
    }
    s = s.toLowerCase().replaceAll('’', "'").replaceAll(RegExp('[!?"]'), ' ');
    // Keep . : / , ₹ - for times, dates and amounts; drop a trailing period.
    s = s.replaceAll(RegExp(r'\.\s*$'), '');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ------------------------------------------------------------- queries

  ParsedCommand? _query(String t) {
    if (RegExp(
      r"\b(what'?s|what is|what do i have)( (on|planned|happening|lined up))?( for)? today\b|\btoday'?s (plan|schedule|reminders)\b|\baaj (kya|ka plan)",
    ).hasMatch(t)) {
      return _cmd(ParseIntent.query, const [], query: QueryKind.today);
    }
    if (RegExp(
      r'\b(what did i miss|did i miss|missed (anything|reminders)|kya miss)',
    ).hasMatch(t)) {
      return _cmd(ParseIntent.query, const [], query: QueryKind.missed);
    }
    final m = RegExp(
      r"^(what|where|when|who)('s| was| is| are| were) (the |my )?(.+)$",
    ).firstMatch(t);
    if (m != null) {
      return _cmd(ParseIntent.query, [
        ParsedItem(title: _tidy(m.group(4)!)),
      ], query: QueryKind.lookup);
    }
    return null;
  }

  ParsedCommand? _forgetNote(String t) {
    if (!RegExp(
      r'^(?:please )?(?:forget|delete|remove) (?:that|this|the last|my last|last) note$',
    ).hasMatch(t)) {
      return null;
    }
    return _cmd(ParseIntent.forgetNote, const []);
  }

  ParsedCommand? _routine(String t) {
    final m = RegExp(
      r'^(?:start|begin|run|let.?s do|chalu karo|shuru karo) (?:my |the )?(.+?)(?: routine)?$',
    ).firstMatch(t);
    if (m == null ||
        !RegExp('mode|routine|bedtime|morning|night|leaving').hasMatch(t)) {
      return null;
    }
    return _cmd(ParseIntent.startRoutine, [
      ParsedItem(title: m.group(1)!.trim()),
    ]);
  }

  // ---------------------------------------------------------- lists/notes

  ParsedCommand? _listItem(String t) {
    final m = RegExp(
      r'^(?:please )?(?:add|put) (.+?) (?:to|in|on) (?:my |the )?(.+?) ?list$',
    ).firstMatch(t);
    if (m == null) return null;
    final list = _capitalise(m.group(2)!.trim());
    final things = m
        .group(1)!
        .split(RegExp(',| and | aur '))
        .map(_tidy)
        .where((s) => s.isNotEmpty)
        .toList();
    return _cmd(ParseIntent.createListItem, [
      for (final th in things) ParsedItem(title: th, listName: list),
    ]);
  }

  ParsedCommand? _note(String t) {
    final m = RegExp(
      r'^(?:note(?: that|:)?|remember that|save (?:a )?note(?: that)?) (.+)$',
    ).firstMatch(t);
    if (m == null) return null;
    return _cmd(ParseIntent.createNote, [
      ParsedItem(title: _capitalise(m.group(1)!.trim())),
    ]);
  }

  // ------------------------------------------------------------ commands

  static const _durUnit =
      '(min|mins|minute|minutes|hour|hours|hr|hrs|ghante|ghanta)';

  ParsedCommand? _snooze(String t) {
    final m = RegExp(
      '^(?:snooze|remind me again|baad mein yaad dilana)(?: (.+?))?(?: for| in)? (\\d+|an?|one|half an?) $_durUnit(?: baad)?\$',
    ).firstMatch(t);
    if (m == null) {
      if (RegExp(r'^snooze( it| that| this)?$').hasMatch(t)) {
        return _target(ParseIntent.snooze, null, snooze: 10);
      }
      return null;
    }
    final mins = _minutes(m.group(2)!, m.group(3)!);
    return _target(ParseIntent.snooze, m.group(1), snooze: mins);
  }

  ParsedCommand? _complete(String t) {
    final patterns = [
      RegExp(
        r'^(?:mark|tick|check) (?:off )?(.+?)(?: as)? (?:done|complete|completed|finished)$',
      ),
      RegExp(
        r'^(?:i )?(?:took|finished|completed|paid|did) (?:my |the )?(.+)$',
      ),
      RegExp(
        r'^(.+?) (?:is )?(?:done|ho gaya|ho gayi|le li|kar liya|kar diya)$',
      ),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(t);
      if (m != null) return _target(ParseIntent.complete, m.group(1));
    }
    if (RegExp(r'^(done|ho gaya|ho gayi)$').hasMatch(t)) {
      return _target(ParseIntent.complete, null);
    }
    return null;
  }

  ParsedCommand? _delete(String t) {
    final m = RegExp(
      r'^(?:cancel|delete|remove|forget)(?: the| my)? (.+?)(?: reminder)?$',
    ).firstMatch(t);
    if (m == null) return null;
    return _target(ParseIntent.delete, m.group(1));
  }

  ParsedCommand? _update(String t) {
    final m = RegExp(
      r'^(?:change|move|reschedule|shift) (?:the |my )?(.+?) (?:reminder )?to (.+)$',
    ).firstMatch(t);
    if (m == null) return null;
    final when = _extract(m.group(2)!);
    final cmd = _target(ParseIntent.update, m.group(1));
    if (cmd.items.isEmpty) return cmd;
    final item = cmd.items.single;
    return _cmd(ParseIntent.update, [
      ParsedItem(
        title: item.title,
        targetId: item.targetId,
        at: when.at,
        allDay: when.allDay,
        rrule: when.rrule,
      ),
    ], clarification: cmd.clarification);
  }

  ParsedCommand _target(ParseIntent intent, String? phrase, {int? snooze}) {
    final ref =
        phrase == null || RegExp(r'^(it|that|this)$').hasMatch(phrase.trim())
        ? reminders.firstOrNull
        : bestMatch(phrase, reminders);
    if (ref == null) {
      return _clarify(
        phrase == null
            ? 'Which reminder do you mean?'
            : 'I couldn’t find “${_tidy(phrase)}”. Which reminder do you mean?',
        intent: intent,
      );
    }
    return _cmd(intent, [
      ParsedItem(title: ref.title, targetId: ref.id, snoozeMinutes: snooze),
    ]);
  }

  static const _stop = {
    'the',
    'my',
    'a',
    'an',
    'to',
    'for',
    'of',
    'reminder',
    'ki',
    'ka',
    'ke',
  };

  /// Token-overlap match ("mark medicine done" → "Take medicine").
  static ReminderRef? bestMatch(String phrase, List<ReminderRef> refs) {
    Set<String> toks(String s) => normalise(s)
        .split(RegExp('[^a-z0-9ऀ-ॿ]+'))
        .where((w) => w.length > 1 && !_stop.contains(w))
        .map(
          (w) => w.endsWith('s') && w.length > 3
              ? w.substring(0, w.length - 1)
              : w,
        )
        .toSet();
    final want = toks(phrase);
    if (want.isEmpty) return null;
    ReminderRef? best;
    var bestScore = 0.0;
    for (final r in refs) {
      final have = toks(r.title);
      final overlap = want.intersection(have).length;
      if (overlap == 0) continue;
      final score = overlap / (want.length + have.length - overlap);
      if (score > bestScore) {
        best = r;
        bestScore = score;
      }
    }
    return best;
  }

  // ------------------------------------------------------------ reminders

  ParsedCommand _reminders(String t) {
    final body = t
        .replaceFirst(
          RegExp(
            '^(?:hey aria,? |aria,? )?(?:please )?(?:can you )?(?:set (?:a )?reminder (?:to |for )?|remind me (?:to |about |that )?|reminder (?:to |for )?|mujhe |yaad dila(?:na|o)? )',
          ),
          '',
        )
        .trim();
    final segments = _split(body);
    final items = <ParsedItem>[];
    for (final seg in segments) {
      final e = _extract(seg);
      if (e.title.isEmpty) continue;
      items.add(
        ParsedItem(
          title: e.title,
          category: categorise(e.title),
          at: e.at,
          allDay: e.allDay,
          rrule: e.rrule,
          priority: e.priority,
          amount: e.amount,
          place: e.place,
          placeOn: e.placeOn,
        ),
      );
    }
    if (items.isEmpty) {
      return _clarify('What should I remind you about?');
    }
    final noTime = items.where((i) => !i.hasTrigger).length;
    return _cmd(
      ParseIntent.createReminder,
      items,
      clarification: noTime > 0 ? 'When should I remind you?' : null,
    );
  }

  /// "X at 8 and Y at 9" → two segments; "call mom and dad at 6" → one.
  List<String> _split(String body) {
    final parts = body
        .split(
          RegExp(
            r'\s*(?:;|,? and also |,? also |, then |,? and then |,? aur phir )\s*',
          ),
        )
        .where((p) => p.trim().isNotEmpty)
        .toList();
    final out = <String>[];
    for (final p in parts) {
      final halves = p.split(RegExp(',? and |,? aur '));
      if (halves.length > 1 && halves.every(_hasWhen)) {
        out.addAll(halves);
      } else {
        out.add(p);
      }
    }
    return out;
  }

  /// A half counts as its own reminder only if it has both a task and a
  /// time ("gym every monday and thursday at 7" stays one reminder).
  bool _hasWhen(String s) {
    final e = _extract(s);
    return e.title.isNotEmpty && (e.at != null || e.rrule != null);
  }

  // ----------------------------------------------------------- extraction

  static const _months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };
  static const _weekdays = {
    'mon': 1,
    'tue': 2,
    'wed': 3,
    'thu': 4,
    'fri': 5,
    'sat': 6,
    'sun': 7,
    'somvar': 1,
    'mangalvar': 2,
    'budhvar': 3,
    'guruvar': 4,
    'shukravar': 5,
    'shanivar': 6,
    'ravivar': 7,
  };
  static const _dayRe =
      '(mon(?:day)?|tue(?:s|sday)?|wed(?:nesday)?|thu(?:rs|rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?|somvar|mangalvar|budhvar|guruvar|shukravar|shanivar|ravivar)';
  static const _monthRe =
      '(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';

  _Extracted _extract(String segment) {
    var s = ' $segment ';
    String? take(RegExp re, [void Function(RegExpMatch m)? onMatch]) {
      final m = re.firstMatch(s);
      if (m == null) return null;
      onMatch?.call(m);
      s = s.replaceRange(m.start, m.end, ' ');
      return m.group(0);
    }

    // Places first: "when I get home", "ghar pahunch kar".
    String? place;
    var placeOn = PlaceTransition.arrive;
    const end = r'(?=\s*$|\s(?:and|then|today|tomorrow|please)\b)';
    take(
      RegExp(
        r"\b(?:when|once|as soon as) i(?:'m| am)? (?:leave|leaving|exit|head out of|get out of|go out of) (?:the |my )?([a-z][a-z' ]*?)" +
            end,
      ),
      (m) {
        place = m.group(1);
        placeOn = PlaceTransition.leave;
      },
    );
    if (place == null) {
      take(
        RegExp(
          r"\b(?:when|once|as soon as|after) i(?:(?:'m| am) (?:back )?(?:at |in )?| (?:get|reach|arrive|come|go)(?: back)?(?: (?:to|at|in))? )(?:the |my )?([a-z][a-z' ]*?)" +
              end,
        ),
        (m) => place = m.group(1),
      );
    }
    if (place == null) {
      take(
        RegExp(
          r'\b(ghar|office|daftar|dukan|market|gym|school)(?: se)? nikal(?:te|ne|kar)?(?: (?:hi|par|waqt|samay|hue))?\b',
        ),
        (m) {
          place = m.group(1);
          placeOn = PlaceTransition.leave;
        },
      );
    }
    if (place == null) {
      take(
        RegExp(
          r'\b(ghar|office|daftar|dukan|market|gym|school)(?: pe| par)? pahunch(?:kar|ne par|te hi|un to|ke)?\b',
        ),
        (m) => place = m.group(1),
      );
    }
    if (place != null) {
      place = switch (place!.trim()) {
        'ghar' => 'home',
        'daftar' => 'office',
        'dukan' => 'market',
        final p => p,
      };
    }

    // Amount first (so "1840" isn't read as a time).
    double? amount;
    take(
      RegExp(
        r'(?:₹|\brs\.?|\binr)\s?([\d,]+(?:\.\d+)?)|\b([\d,]+(?:\.\d+)?)\s?(?:rupees|rupaye|rupee|rs\b\.?|₹)',
      ),
      (m) => amount = double.tryParse(
        (m.group(1) ?? m.group(2))!.replaceAll(',', ''),
      ),
    );

    var priority = Priority.normal;
    take(
      RegExp(
        r'\b(urgent(ly)?|asap|very important|must not miss|bahut zaroori|zaroori)\b',
      ),
      (_) => priority = Priority.urgent,
    );
    if (priority == Priority.normal) {
      take(RegExp(r'\bimportant\b'), (_) => priority = Priority.high);
    }

    // ---- recurrence
    RecurrenceRule? rule;
    int? monthDay;
    take(RegExp(r'\bevery (\d+) (day|week|month|year)s?\b'), (m) {
      rule = RecurrenceRule(
        freq: switch (m.group(2)!) {
          'day' => Freq.daily,
          'week' => Freq.weekly,
          'month' => Freq.monthly,
          _ => Freq.yearly,
        },
        interval: int.parse(m.group(1)!).clamp(1, 99),
      );
    });
    rule ??=
        take(
              RegExp(
                r'\b(?:every |on )?(?:weekdays?|working days?|week ?days)\b|\bmon(?:day)? ?(?:to|-) ?fri(?:day)?\b',
              ),
            ) !=
            null
        ? RecurrenceRule.weekdays
        : null;
    if (rule == null) {
      take(
        RegExp(
          '\\b(?:every|har|each) $_dayRe(?:s)?((?:(?:,| and| &|,? aur) ?$_dayRe)*)\\b',
        ),
        (m) {
          final days = RegExp(_dayRe)
              .allMatches(m.group(0)!)
              .map(
                (d) =>
                    _weekdays[d.group(0)!.length >= 3 &&
                            !d.group(0)!.endsWith('var')
                        ? d.group(0)!.substring(0, 3)
                        : d.group(0)]!,
              )
              .toSet();
          rule = RecurrenceRule(freq: Freq.weekly, byDay: days);
        },
      );
    }
    if (rule == null) {
      take(
        RegExp(
          r'\blast day of (?:every|each|the) month\b|\bevery month on the last day\b',
        ),
        (_) {
          rule = const RecurrenceRule(freq: Freq.monthly, byMonthDay: [-1]);
        },
      );
    }
    if (rule == null) {
      take(
        RegExp(
          r'\b(?:on )?(?:the )?(\d{1,2})(?:st|nd|rd|th| tarikh| tareekh)? (?:of )?(?:every|each|har) (?:month|mahine)\b|\b(?:every|each|har) (?:month|mahine) (?:on )?(?:the )?(\d{1,2})(?:st|nd|rd|th| tarikh| tareekh| date)?\b',
        ),
        (m) {
          monthDay = int.parse((m.group(1) ?? m.group(2))!).clamp(1, 31);
          rule = RecurrenceRule(freq: Freq.monthly, byMonthDay: [monthDay!]);
        },
      );
    }
    if (rule == null) {
      for (final (re, r) in [
        (
          RegExp(
            r'\b(?:every ?day|daily|each day|roz(?:ana)?|har (?:roz|din)|every morning|every night|every evening)\b',
          ),
          RecurrenceRule.daily,
        ),
        (RegExp(r'\b(?:every week|weekly|har hafte)\b'), RecurrenceRule.weekly),
        (
          RegExp(r'\b(?:every month|monthly|har mahine)\b'),
          RecurrenceRule.monthly,
        ),
        (
          RegExp(r'\b(?:every year|yearly|annually|har saal)\b'),
          RecurrenceRule.yearly,
        ),
      ]) {
        if (re.hasMatch(s)) {
          // "every morning" keeps its time-of-day word for the time parser.
          final m = re.firstMatch(s)!;
          final keepPart = RegExp('morning|night|evening')
              .firstMatch(m.group(0)!)
              ?.group(0);
          s = s.replaceRange(m.start, m.end, ' ${keepPart ?? ''} ');
          rule = r;
          break;
        }
      }
    }

    // ---- relative time ("in 20 minutes", "2 ghante baad")
    DateTime? relative;
    take(
      RegExp(
        '\\b(?:in|after) (\\d+|an?|one|two|half an?) $_durUnit\\b|\\b(\\d+) $_durUnit baad\\b',
      ),
      (m) {
        final n = m.group(1) ?? m.group(3)!;
        final unit = m.group(2) ?? m.group(4)!;
        relative = now.add(Duration(minutes: _minutes(n, unit)));
      },
    );

    // ---- date
    DateTime? date; // wall-clock midnight
    if (take(RegExp(r'\b(?:day after tomorrow|parso[n]?)\b')) != null) {
      date = _today.add(const Duration(days: 2));
    } else if (take(RegExp(r'\b(?:tomorrow|tmrw|kal)\b')) != null) {
      date = _today.add(const Duration(days: 1));
    } else if (take(RegExp(r'\b(?:today|aaj)\b')) != null) {
      date = _today;
    }
    take(
      RegExp(
        '\\b(?:on )?(?:the )?(\\d{1,2})(?:st|nd|rd|th)? (?:of )?$_monthRe\\b|\\b$_monthRe (\\d{1,2})(?:st|nd|rd|th)?\\b',
      ),
      (m) {
        final day = int.parse((m.group(1) ?? m.group(4))!);
        final mon = _months[(m.group(2) ?? m.group(3))!.substring(0, 3)]!;
        date = _nextDate(mon, day);
      },
    );
    if (date == null) {
      take(RegExp(r'\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b'), (m) {
        final day = int.parse(m.group(1)!);
        final mon = int.parse(m.group(2)!);
        final y = m.group(3) == null
            ? null
            : int.parse(m.group(3)!) % 100 + 2000;
        if (mon >= 1 && mon <= 12 && day >= 1 && day <= 31) {
          date = y == null ? _nextDate(mon, day) : DateTime.utc(y, mon, day);
        }
      });
    }
    if (date == null && rule == null) {
      take(RegExp('\\b(?:on |next |this |coming )?$_dayRe(?: ko)?\\b'), (m) {
        final word = RegExp(_dayRe).firstMatch(m.group(0)!)!.group(0)!;
        final wd =
            _weekdays[word.endsWith('var') ? word : word.substring(0, 3)]!;
        var delta = (wd - _today.weekday) % 7;
        if (delta == 0 || m.group(0)!.contains('next')) {
          delta = delta == 0 ? 7 : delta;
        }
        date = _today.add(Duration(days: delta));
      });
    }
    if (date == null) {
      take(RegExp(r'\bon (?:the )?(\d{1,2})(?:st|nd|rd|th)\b'), (m) {
        final d = int.parse(m.group(1)!);
        date = DateTime.utc(_today.year, _today.month, d);
        if (date!.isBefore(_today)) {
          date = DateTime.utc(_today.year, _today.month + 1, d);
        }
      });
    }

    // ---- part of day
    int? partHour;
    var pmHint = false;
    var nightEarly = false;
    int? partMinute;
    final dp = dayParts;
    for (final (re, m, pm, night) in [
      (RegExp(r'\b(?:after lunch|lunch ke baad)\b'), 14 * 60, true, false),
      (
        RegExp(r'\b(?:this morning|morning|subah|savere)\b'),
        dp.morning,
        false,
        false,
      ),
      (RegExp(r'\b(?:noon|midday)\b'), 12 * 60, true, false),
      (
        RegExp(r'\b(?:this afternoon|afternoon|dopahar)\b'),
        dp.afternoon,
        true,
        false,
      ),
      (
        RegExp(r'\b(?:this evening|evening|shaam|sham)\b'),
        dp.evening,
        true,
        false,
      ),
      (RegExp(r'\b(?:tonight|at night|night|raat)\b'), dp.night, true, true),
      (RegExp(r'\bmidnight\b'), 0, false, false),
    ]) {
      if (take(re) != null) {
        partHour = m ~/ 60;
        partMinute = m;
        pmHint = pm;
        nightEarly = night;
        break;
      }
    }

    // ---- clock time
    int? hour;
    var minute = 0;
    String? ampm;
    take(
      RegExp(
        r'\b(?:at |@ ?)?(\d{1,2})(?:[:.](\d{2}))? ?(am|pm|a\.m\.?|p\.m\.?)(?=\s|$)',
      ),
      (m) {
        hour = int.parse(m.group(1)!);
        minute = int.parse(m.group(2) ?? '0');
        ampm = m.group(3)!.startsWith('a') ? 'am' : 'pm';
      },
    );
    if (hour == null) {
      take(
        RegExp(r"\b(?:at )?(\d{1,2})(?:[:.](\d{2}))? ?(?:baje|o'?clock)\b"),
        (m) {
          hour = int.parse(m.group(1)!);
          minute = int.parse(m.group(2) ?? '0');
        },
      );
    }
    if (hour == null) {
      take(RegExp(r'\b(?:at|by|around) (\d{1,2})(?:[:.](\d{2}))?\b'), (m) {
        hour = int.parse(m.group(1)!);
        minute = int.parse(m.group(2) ?? '0');
      });
    }
    if (hour == null) {
      take(RegExp(r'\b(\d{1,2})[:.](\d{2})\b'), (m) {
        hour = int.parse(m.group(1)!);
        minute = int.parse(m.group(2)!);
      });
    }
    if (hour != null && (hour! > 23 || minute > 59)) {
      hour = null;
      minute = 0;
    }

    // ---- resolve
    DateTime? at;
    var allDay = false;
    if (relative != null) {
      at = relative;
    } else if (hour != null || partHour != null) {
      var h = hour ?? partHour!;
      if (hour == null) minute = partMinute! % 60;
      if (ampm == 'pm' && h < 12) h += 12;
      if (ampm == 'am' && h == 12) h = 0;
      final explicitAmPm = ampm != null;
      if (!explicitAmPm && hour != null && h < 12) {
        if (pmHint && !(nightEarly && h < 5)) {
          h += 12;
        } else if (partHour == null && h >= 1 && h <= 6) {
          h += 12; // "at 5" almost always means 5 PM
        }
      }
      var day = date ?? _today;
      var candidate = fromWall(
        DateTime.utc(day.year, day.month, day.day, h, minute),
        zone,
      );
      if (date == null && rule == null && !candidate.isAfter(now)) {
        // Bare "at 8" that has passed: try 8 PM, then tomorrow.
        if (!explicitAmPm && hour != null && h < 12) {
          final pm = fromWall(
            DateTime.utc(day.year, day.month, day.day, h + 12, minute),
            zone,
          );
          candidate = pm.isAfter(now) ? pm : candidate;
        }
        if (!candidate.isAfter(now)) {
          day = day.add(const Duration(days: 1));
          candidate = fromWall(
            DateTime.utc(day.year, day.month, day.day, h, minute),
            zone,
          );
        }
      }
      at = candidate;
    } else if (date != null || rule != null) {
      final d = date ?? _today;
      at = fromWall(DateTime.utc(d.year, d.month, d.day), zone);
      allDay = true;
    }

    // Recurring: the first occurrence must be in the future.
    if (rule != null && at != null) {
      final wall = toWall(at, zone);
      final first = rule!.nextAfter(
        wall,
        wall.subtract(const Duration(seconds: 1)),
      );
      var next = first;
      final threshold = allDay
          ? _wallNow.subtract(const Duration(days: 1))
          : _wallNow;
      if (next != null && !next.isAfter(threshold)) {
        next = rule!.nextAfter(wall, threshold);
      }
      if (next != null) at = fromWall(next, zone);
    }

    return _Extracted(
      title: _tidy(s),
      at: at,
      allDay: allDay,
      rrule: rule?.toString(),
      priority: priority,
      amount: amount,
      place: place,
      placeOn: placeOn,
    );
  }

  DateTime _nextDate(int month, int day) {
    final d = DateTime.utc(_today.year, month, day);
    return d.isBefore(_today) ? DateTime.utc(_today.year + 1, month, day) : d;
  }

  static int _minutes(String n, String unit) {
    final count = switch (n) {
      'a' || 'an' || 'one' => 1.0,
      'two' => 2.0,
      'half a' || 'half an' => 0.5,
      _ => double.parse(n),
    };
    final isHour = unit.startsWith('h') || unit.startsWith('gh');
    return (count * (isHour ? 60 : 1)).round().clamp(1, 60 * 24 * 30);
  }

  // ------------------------------------------------------------- helpers

  static final _lead = RegExp(
    r'^(?:(?:to|for|about|that|me|please|ki|ko|on|at|by|and|aur|the|every)\s+)+',
  );
  static final _trail = RegExp(
    r'(?:\s+(?:ki yaad dila(?:na|o)?|yaad dila(?:na|o)?|ke liye|please|on|at|by|for|to|ki|ka|ke|ko|from|starting|and|aur|the|every|reminder))+$',
  );

  static String _tidy(String raw) {
    var s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'^[,\-:]+|[,\-:]+$'), '').trim();
    for (var i = 0; i < 3; i++) {
      s = s.replaceFirst(_lead, '').replaceFirst(_trail, '').trim();
    }
    return _capitalise(s);
  }

  static String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static ReminderCategory categorise(String title) {
    final t = title.toLowerCase();
    bool any(List<String> w) => w.any((k) => RegExp('\\b$k').hasMatch(t));
    if (any([
      'medicine',
      'tablet',
      'pill',
      'vitamin',
      'dawai',
      'dawa',
      'doctor',
      r'dr\b',
      'insulin',
      'water',
      'paani',
      'exercise',
      'walk',
      'yoga',
      'gym',
      r'bp\b',
      'sugar',
      'checkup',
    ])) {
      return ReminderCategory.health;
    }
    if (any([
      'pay',
      'bill',
      'rent',
      'emi',
      'recharge',
      'electricity',
      'bijli',
      'insurance',
      'premium',
      'credit card',
      'fees',
      'tax',
      r'sip\b',
      'loan',
    ])) {
      return ReminderCategory.bills;
    }
    if (any([
      'call',
      'birthday',
      'anniversary',
      'mom',
      'mummy',
      'papa',
      'dad',
      'wish',
      'meet',
      'visit',
      'phone',
    ])) {
      return ReminderCategory.people;
    }
    if (any([
      'meeting',
      'office',
      'report',
      'email',
      'client',
      'deadline',
      'presentation',
      'standup',
      'submit',
    ])) {
      return ReminderCategory.work;
    }
    if (any([
      'clean',
      'plumber',
      'electrician',
      'grocery',
      'groceries',
      'milk',
      'doodh',
      'laundry',
      'garbage',
      'plants',
      'cook',
      'gas',
      'cylinder',
      'maid',
    ])) {
      return ReminderCategory.home;
    }
    return ReminderCategory.personal;
  }

  ParsedCommand _cmd(
    ParseIntent intent,
    List<ParsedItem> items, {
    QueryKind query = QueryKind.none,
    String? clarification,
  }) => ParsedCommand(
    intent: intent,
    items: items,
    query: query,
    clarification: clarification,
    source: ParseSource.rules,
  );

  ParsedCommand _clarify(
    String q, {
    ParseIntent intent = ParseIntent.createReminder,
  }) => _cmd(intent, const [], clarification: q);
}

class _Extracted {
  _Extracted({
    required this.title,
    required this.at,
    required this.allDay,
    required this.rrule,
    required this.priority,
    required this.amount,
    this.place,
    this.placeOn = PlaceTransition.arrive,
  });
  final String title;
  final String? place;
  final PlaceTransition placeOn;
  final DateTime? at;
  final bool allDay;
  final String? rrule;
  final Priority priority;
  final double? amount;
}
