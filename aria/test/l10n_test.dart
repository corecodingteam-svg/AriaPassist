import 'dart:io';

import 'package:aria/core/router/app_router.dart';
import 'package:aria/core/theme/presets.dart';
import 'package:aria/features/circles/domain/circle.dart';
import 'package:aria/features/places/domain/place.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/preferences/domain/app_prefs.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/today_sections.dart';
import 'package:aria/features/settings/settings_screen.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:aria/features/voice/domain/voice_settings.dart';
import 'package:aria/l10n/hi.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';
import 'helpers/pump_app.dart';

/// Every `tr('…')` / `tr("…")` literal in lib/ (first argument).
Set<String> trKeys() {
  final keys = <String>{};
  final single = RegExp(r"""\btr\(\s*'((?:[^'\\]|\\.)*)'""");
  final double = RegExp(r'''\btr\(\s*"((?:[^"\\]|\\.)*)"''');
  for (final f in Directory(
    'lib',
  ).listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart') || f.path.endsWith('hi.dart')) continue;
    final s = f.readAsStringSync();
    for (final m in single.allMatches(s)) {
      keys.add(_unescape(m.group(1)!.replaceAll(r"\'", "'")));
    }
    for (final m in double.allMatches(s)) {
      keys.add(_unescape(m.group(1)!.replaceAll(r'\"', '"')));
    }
  }
  return keys;
}

String _unescape(String s) => s.replaceAll(r'\n', '\n').replaceAll(r'\$', r'$');

Set<String> _ph(String s) =>
    RegExp(r'\{\d\}').allMatches(s).map((m) => m[0]!).toSet();

void main() {
  tearDown(() => L10n.lang = 'en');

  test(
    'every tr() string has a Hindi translation with the same placeholders',
    () {
      final keys = trKeys();
      expect(keys.length, greaterThan(700));
      final missing = keys.where((k) => !kHindi.containsKey(k)).toList()
        ..sort();
      expect(missing, isEmpty, reason: 'add these to lib/l10n/hi.dart');
      final broken = [
        for (final k in keys)
          if (kHindi[k] case final v? when !_ph(k).containsAll(_ph(v)))
            '$k → $v',
      ];
      expect(
        broken,
        isEmpty,
        reason: 'Hindi uses a placeholder the English lacks',
      );
    },
  );

  test('labels from enums and tables translate', () {
    String both(String Function() label) {
      L10n.lang = 'en';
      final en = label();
      L10n.lang = 'hi';
      final hi = label();
      return '$en|$hi';
    }

    final all = <String>[
      for (final c in ReminderCategory.values) both(() => c.label),
      for (final p in Priority.values) both(() => p.label),
      for (final s in TodaySection.values) both(() => s.label),
      for (final r in CircleRole.values) ...[
        both(() => r.label),
        both(() => r.description),
      ],
      for (final f in Feature.values) ...[
        both(() => f.title),
        both(() => f.blurb),
      ],
      for (final p in Personality.values) both(() => p.label),
      for (final t in ThemePresets.all) both(() => t.label),
      for (final g in kSettingsGroups) ...[
        both(() => g.title),
        both(() => g.subtitle),
      ],
    ];
    final untranslated = all.where((s) {
      final [en, hi] = s.split('|');
      return en == hi && RegExp('[A-Za-z]{3}').hasMatch(en) && en != 'Aria';
    }).toList();
    expect(untranslated, isEmpty);
  });

  test('tr fills placeholders and falls back to English', () {
    L10n.lang = 'hi';
    expect(tr('Join {0}', ['Rao family']), 'Rao family से जुड़ें');
    expect(tr('Not a known string {0}', [1]), 'Not a known string 1');
    expect(L10n.resolve('system', const Locale('hi')), 'hi');
    expect(L10n.resolve('system', const Locale('en')), 'en');
    expect(L10n.resolve('en', const Locale('hi')), 'en');
  });

  test('a Hindi-named place still matches spoken English/Hinglish', () {
    const places = [
      SavedPlace(id: 'h', name: 'घर', lat: 0, lng: 0),
      SavedPlace(id: 'w', name: 'ऑफ़िस', lat: 0, lng: 0),
    ];
    expect(matchPlace(places, 'home')?.id, 'h');
    expect(matchPlace(places, 'ghar')?.id, 'h');
    expect(matchPlace(places, 'work')?.id, 'w');
    expect(matchPlace(places, 'the office')?.id, 'w');
  });

  testWidgets('switching to हिन्दी translates the screens in place', (t) async {
    final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
    expect(find.text('Nothing planned yet'), findsOneWidget);
    app.container
        .read(appPrefsProvider.notifier)
        .update((p) => p.copyWith(appLanguage: AppLanguage.hi));
    await t.pumpAndSettle();
    expect(find.text('अभी कुछ तय नहीं'), findsOneWidget);
    expect(find.text('Nothing planned yet'), findsNothing);
    expect(find.text('आज'), findsWidgets, reason: 'tab label');

    app.container.read(routerProvider).push('/settings').ignore();
    await t.pumpAndSettle();
    expect(find.text('सेटिंग्स'), findsOneWidget);
    expect(find.text('रंग-रूप और थीम'), findsOneWidget);

    // Back to English without losing the screen.
    app.container
        .read(appPrefsProvider.notifier)
        .update((p) => p.copyWith(appLanguage: AppLanguage.en));
    await t.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('Hindi reminder editor end to end', (t) async {
    final app = await pumpApp(
      t,
      auth: FakeAuthRepository(userId: 'u1'),
      prefs: {'app_language': 'hi'},
    );
    await t.tap(find.byTooltip('नया रिमाइंडर'));
    await t.pumpAndSettle();
    expect(find.text('नया रिमाइंडर'), findsOneWidget);
    await t.enterText(find.byKey(const Key('title-field')), 'दवा लेना');
    await t.tap(find.text('कल'));
    await t.tap(find.text('सेव करें'));
    await t.pumpAndSettle();
    expect(
      (await app.db.select(app.db.reminders).getSingle()).title,
      'दवा लेना',
    );
    expect(find.textContaining('हो गया! मैं'), findsOneWidget);
  });
}
