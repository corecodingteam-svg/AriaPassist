// Realtime shared-list updates and semantic note search, end to end.
//   supabase start && supabase functions serve
//   flutter test integration_test/organize_test.dart -d <device> \
//     --dart-define-from-file=env/dev.json
import 'package:aria/app.dart';
import 'package:aria/core/config/env.dart';
import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/data/providers.dart';
import 'package:aria/features/lists/organize_providers.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const _phone = '+919888888888';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('another device adds to the list → appears here via realtime; '
      'notes are found by meaning', (tester) async {
    ensureTimeZones();
    SharedPreferences.setMockInitialValues({
      'aria.prefs.v1': '{"onboarded":true}',
    });
    final prefs = await SharedPreferences.getInstance();
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
    );
    final supabase = Supabase.instance.client;
    await supabase.auth.signOut();
    await supabase.auth.signInWithOtp(phone: _phone);
    await supabase.auth.verifyOTP(
      phone: _phone,
      token: '123456',
      type: OtpType.sms,
    );
    final userId = supabase.auth.currentUser!.id;

    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const AriaApp()),
    );
    await tester.pumpAndSettle();
    final engine = c.read(syncEngineProvider)!;
    await engine.syncNow();
    final sub = c.listen(activeCircleIdProvider, (_, _) {});
    addTearDown(sub.close);
    final circle = (await c.read(activeCircleIdProvider.future))!;

    // 1. Create a list here and push it.
    final lists = c.read(listsRepositoryProvider)!;
    final listId = await lists.createList('E2E Grocery', circleId: circle);
    await lists.addItems(listId, ['Milk']);
    await engine.syncNow();

    // Give the realtime channel a moment to finish subscribing.
    await Future<void>.delayed(const Duration(seconds: 2));

    // 2. "Another device" adds an item straight on the server.
    final remoteItem = const Uuid().v4();
    await supabase.from('list_items').insert({
      'id': remoteItem,
      'list_id': listId,
      'text': 'Atta (from another phone)',
      'added_by': userId,
      'position': 2,
    });

    // 3. Realtime → pull, with no manual sync call.
    var arrived = false;
    for (var i = 0; i < 20 && !arrived; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();
      final items = await lists.watchItems(listId).first;
      arrived = items.any((x) => x.id == remoteItem);
    }
    expect(
      arrived,
      isTrue,
      reason: 'realtime change should arrive within 10 s',
    );

    // 4. Semantic search through the notes-search Edge Function.
    final notes = c.read(notesRepositoryProvider)!;
    await notes.add('The wifi password is sunflower42', circleId: circle);
    await engine.syncNow();
    // The embedding model has a cold start; the app falls back to keyword
    // search meanwhile. Warm it up, then check the semantic path.
    for (var i = 0; i < 6; i++) {
      final warm = await notes.search('warm up');
      if (warm.isNotEmpty || i == 5) break;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    final hits = await notes.search("what's the internet code");
    expect(hits.first.text, contains('sunflower42'));
    expect(
      hits.first.score,
      greaterThan(0.78),
      reason: 'semantic, not keyword',
    );

    // Cleanup.
    await supabase.from('lists').delete().eq('id', listId);
    await supabase.from('notes').delete().eq('created_by', userId);
    await supabase.auth.signOut();
  });
}
