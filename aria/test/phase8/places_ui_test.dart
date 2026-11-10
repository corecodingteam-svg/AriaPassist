import 'package:aria/core/router/app_router.dart';
import 'package:aria/features/places/domain/place.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

Future<void> go(TestApp app, WidgetTester t, String path) async {
  app.container.read(routerProvider).push(path).ignore();
  await t.pumpAndSettle();
}

void main() {
  testWidgets('save Home from the current location', (t) async {
    final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
    await go(app, t, '/settings/places');
    await t.tap(find.byKey(const Key('add-place')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('save-place')));
    await t.pumpAndSettle();
    final places = app.container.read(appPrefsProvider).places;
    expect(
      [places.single.name, places.single.lat, places.single.radiusM],
      ['Home', 12.9716, 150],
    );
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('no location permission → explains, saves nothing', (t) async {
    final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
    app.location.perm = 'denied';
    await go(app, t, '/settings/places');
    await t.tap(find.byKey(const Key('add-place')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('save-place')));
    await t.pumpAndSettle();
    expect(app.location.requests, 1, reason: 'asks in context');
    expect(find.textContaining('couldn’t get your location'), findsOneWidget);
    expect(app.container.read(appPrefsProvider).places, isEmpty);
  });

  testWidgets(
    'editor: “when I leave Work” → geofence registered, Today section',
    (t) async {
      final app = await pumpApp(t, auth: FakeAuthRepository(userId: 'u1'));
      app.container
          .read(appPrefsProvider.notifier)
          .update(
            (p) => p.copyWith(
              places: [
                const SavedPlace(
                  id: 'w',
                  name: 'Work',
                  emoji: '🏢',
                  lat: 12.93,
                  lng: 77.62,
                ),
              ],
            ),
          );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('New reminder'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('title-field')), 'Buy milk');
      await t.tap(find.text('📍 At a place'));
      await t.pumpAndSettle();
      await t.tap(find.text('When I leave'));
      await t.tap(find.byKey(const Key('place-Work')));
      await t.pumpAndSettle();
      expect(find.text('Repeat'), findsNothing);
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();

      final row = await app.db.select(app.db.reminders).getSingle();
      expect(row.startAt, isNull);
      final r = Reminder(
        id: row.id,
        circleId: '',
        createdBy: '',
        title: '',
        location: LocationTrigger.fromJson({
          'lat': 12.93,
          'lng': 77.62,
          'place': 'Work',
          'on': 'leave',
        }),
      );
      expect(r.location!.describe(), 'When I leave Work');
      expect(row.locationJson, contains('"on":"leave"'));
      expect(find.text('📍 Location-based · 1'), findsOneWidget);
      expect(find.text('When I leave Work'), findsOneWidget);

      await t.pump(const Duration(seconds: 1));
      final f = app.location.fences.single;
      expect(
        [f['id'], f['on'], f['lat'], f['title']],
        [row.id, 'leave', 12.93, '📍 Buy milk'],
      );
    },
  );

  testWidgets('free plan: location reminders open the paywall', (t) async {
    final app = await pumpApp(
      t,
      auth: FakeAuthRepository(userId: 'u1'),
      plan: 'free',
    );
    app.container
        .read(appPrefsProvider.notifier)
        .update(
          (p) => p.copyWith(
            places: [const SavedPlace(id: 'h', name: 'Home', lat: 1, lng: 2)],
          ),
        );
    await t.tap(find.byTooltip('New reminder'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('title-field')), 'Call mum');
    await t.tap(find.text('📍 At a place'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('place-Home')));
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('Location reminders'), findsWidgets);
    expect(await app.db.select(app.db.reminders).get(), isEmpty);
  });

  test('spoken place names match saved places', () {
    const places = [
      SavedPlace(id: 'h', name: 'Home', lat: 0, lng: 0),
      SavedPlace(id: 'w', name: 'Work', lat: 0, lng: 0),
      SavedPlace(id: 'p', name: 'Pharmacy', lat: 0, lng: 0),
    ];
    expect(matchPlace(places, 'home')?.id, 'h');
    expect(matchPlace(places, 'the office')?.id, 'w');
    expect(matchPlace(places, 'ghar')?.id, 'h');
    expect(matchPlace(places, 'medical store')?.id, 'p');
    expect(matchPlace(places, 'gym'), isNull);
  });
}
