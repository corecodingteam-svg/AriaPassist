import 'package:aria/l10n/hi.dart';
import 'package:flutter/widgets.dart';

/// UI language. English strings are the keys; [kHindi] maps them to Hindi.
/// A missing entry falls back to English (never a blank screen).
abstract final class L10n {
  static String lang = 'en';

  static const supported = [Locale('en', 'IN'), Locale('hi', 'IN')];

  /// 'en' | 'hi' from the setting, or the phone's language for "system".
  static String resolve(String setting, Locale? device) => setting == 'system'
      ? (device?.languageCode == 'hi' ? 'hi' : 'en')
      : setting;
}

/// Translates [en]; `{0}`, `{1}`… are replaced by [args] in order.
String tr(String en, [List<Object?> args = const []]) {
  var s = L10n.lang == 'hi' ? (kHindi[en] ?? en) : en;
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}

/// Language switched: rebuild every element in place (keeps navigation).
void rebuildAll(BuildContext context) {
  void mark(Element e) {
    e
      ..markNeedsBuild()
      ..visitChildren(mark);
  }

  (context as Element).visitChildren(mark);
}
