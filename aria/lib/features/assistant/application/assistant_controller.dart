import 'dart:async';

import 'package:aria/core/connectivity.dart';
import 'package:aria/core/telemetry/telemetry.dart';
import 'package:aria/data/providers.dart';
import 'package:aria/features/assistant/data/parser_service.dart';
import 'package:aria/features/assistant/domain/parse_result.dart';
import 'package:aria/features/assistant/domain/rule_parser.dart';
import 'package:aria/features/assistant/domain/when_text.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/lists/data/lists_repository.dart';
import 'package:aria/features/lists/organize_providers.dart';
import 'package:aria/features/places/domain/place.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/alert_plan.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/reminder_logic.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:aria/features/voice/application/voice_engine.dart';
import 'package:aria/features/voice/application/voice_providers.dart';
import 'package:aria/features/voice/domain/phrases.dart';
import 'package:aria/features/voice/domain/voice_settings.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

enum TalkPhase { idle, listening, thinking, confirming, answered }

@immutable
class TalkState {
  const TalkState({
    this.phase = TalkPhase.idle,
    this.transcript = '',
    this.level = 0,
    this.drafts = const [],
    this.reply,
    this.speechAvailable = true,
    this.navigateTo,
  });

  final TalkPhase phase;
  final String transcript;

  /// 0..1 microphone level for the orb.
  final double level;

  /// Reminders waiting for the user's ✓.
  final List<ParsedItem> drafts;

  /// What Aria said (also spoken when spoken confirmations are on).
  final String? reply;
  final bool speechAvailable;

  /// Where the sheet should go next (e.g. a routine runner), if anywhere.
  final String? navigateTo;

  TalkState copyWith({
    TalkPhase? phase,
    String? transcript,
    double? level,
    List<ParsedItem>? drafts,
    String? Function()? reply,
    bool? speechAvailable,
    String? Function()? navigateTo,
  }) => TalkState(
    phase: phase ?? this.phase,
    transcript: transcript ?? this.transcript,
    level: level ?? this.level,
    drafts: drafts ?? this.drafts,
    reply: reply != null ? reply() : this.reply,
    speechAvailable: speechAvailable ?? this.speechAvailable,
    navigateTo: navigateTo != null ? navigateTo() : this.navigateTo,
  );
}

final parserServiceProvider = Provider<ParserService>((ref) {
  RemoteParse? remote;
  try {
    remote = supabaseRemoteParse(ref.watch(supabaseClientProvider));
  } on Object {
    remote = null; // Supabase not initialised (tests)
  }
  return ParserService(
    remote: remote,
    online: () => ref.read(isOnlineProvider).value ?? true,
  );
});

/// The "Talk to Aria" conversation. One per open sheet (autoDispose).
class AssistantController extends Notifier<TalkState> {
  bool _submitted = false;

  @override
  TalkState build() {
    // Captured now: providers can't be read inside onDispose.
    final speech = ref.read(speechInputProvider);
    final speaker = ref.read(speakerProvider);
    ref.onDispose(() {
      unawaited(speech.stop());
      unawaited(speaker.stop());
    });
    return const TalkState();
  }

  VoiceSettings get _settings => ref.read(voiceSettingsProvider);
  Phrases get _phrases => Phrases(_settings);
  String get _zone => ref.read(deviceTimeZoneProvider);
  DateTime get _now => ref.read(clockProvider)().toUtc();

  // ------------------------------------------------------------- input

  Future<void> listen() async {
    await ref.read(speakerProvider).stop();
    final speech = ref.read(speechInputProvider);
    if (!await speech.init()) {
      state = state.copyWith(speechAvailable: false, phase: TalkPhase.idle);
      return;
    }
    _submitted = false;
    state = state.copyWith(
      phase: TalkPhase.listening,
      transcript: '',
      level: 0,
    );
    final locale = VoiceProfile.of(_settings).locale;
    await speech.listen(
      localeId: locale,
      onLevel: (l) => state = state.copyWith(level: (l / 10).clamp(0.0, 1.0)),
      onResult: (text, {required isFinal}) {
        state = state.copyWith(transcript: text);
        if (isFinal && !_submitted && text.trim().isNotEmpty) {
          _submitted = true;
          unawaited(submit(text));
        }
      },
    );
  }

  Future<void> stopListening() async {
    await ref.read(speechInputProvider).stop();
    if (!_submitted && state.transcript.trim().isNotEmpty) {
      _submitted = true;
      await submit(state.transcript);
    } else if (state.phase == TalkPhase.listening) {
      state = state.copyWith(phase: TalkPhase.idle, level: 0);
    }
  }

  /// Handles typed or recognised text.
  Future<void> submit(String input) async {
    final text = input.trim();
    if (text.isEmpty) return;
    state = state.copyWith(transcript: text, level: 0);
    if (state.drafts.isNotEmpty && await _followUp(text)) return;

    state = state.copyWith(phase: TalkPhase.thinking);
    final cmd = await ref
        .read(parserServiceProvider)
        .parse(
          text,
          now: _now,
          zone: _zone,
          refs: await _refs(),
          dayParts: ref.read(appPrefsProvider).dayParts,
        );
    await _dispatch(cmd);
  }

  /// "yes" / "no" / "make it 8 pm" while drafts are on screen.
  Future<bool> _followUp(String text) async {
    final t = RuleParser.normalise(text);
    if (RegExp(
      r'^(yes|yeah|yep|ok|okay|sure|haan|ha|han|theek hai|thik hai|done|add (it|them)|confirm)\b',
    ).hasMatch(t)) {
      await confirm();
      return true;
    }
    if (RegExp(r'^(no|nope|cancel|nahi|mat karo|rehne do)\b').hasMatch(t)) {
      cancelDrafts();
      return true;
    }
    final when = RuleParser(
      now: _now,
      zone: _zone,
      dayParts: ref.read(appPrefsProvider).dayParts,
    ).whenOf(text);
    final isTimeOnly =
        RuleParser(now: _now, zone: _zone).parse(text).items.isEmpty ||
        RegExp('^(change|make it|set it|move it|at |kal|tomorrow|today|in )')
            .hasMatch(t);
    if (when.at != null && isTimeOnly) {
      final drafts = [
        for (final d in state.drafts)
          d.copyWith(
            at: () => when.at,
            allDay: when.allDay,
            rrule: () => when.rrule ?? d.rrule,
          ),
      ];
      state = state.copyWith(drafts: drafts);
      await _say(_confirmQuestion(drafts));
      state = state.copyWith(phase: TalkPhase.confirming);
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------- dispatch

  Future<void> _dispatch(ParsedCommand c) async {
    final service = ref.read(reminderServiceProvider);
    final repo = ref.read(reminderRepositoryProvider);
    final p = _phrases;

    switch (c.intent) {
      case ParseIntent.createReminder:
        if (c.items.isEmpty) {
          state = state.copyWith(phase: TalkPhase.answered);
          await _say(c.clarification ?? p.notUnderstood());
          return;
        }
        state = state.copyWith(drafts: c.items, phase: TalkPhase.confirming);
        await _say(c.clarification ?? _confirmQuestion(c.items));
      case ParseIntent.createListItem:
        final lists = ref.read(listsRepositoryProvider);
        final circle = await _circle();
        if (lists == null || circle == null || c.items.isEmpty) {
          await _clarify(c);
          return;
        }
        final listName = c.items.first.listName ?? 'Grocery';
        final String listId;
        try {
          listId = await lists.findOrCreate(
            listName,
            circleId: circle,
            maxLists: ref.read(entitlementProvider).plan.maxLists,
          );
        } on ListLimitReached catch (e) {
          state = state.copyWith(phase: TalkPhase.answered);
          await _say(
            'The free plan includes ${e.max} lists. Add it to one of those, '
            'or upgrade for unlimited lists.',
          );
          return;
        }
        await lists.addItems(listId, [for (final i in c.items) i.title]);
        state = state.copyWith(phase: TalkPhase.answered);
        await _say(
          p.listAdded([
            for (final i in c.items) i.title.toLowerCase(),
          ], listName.toLowerCase().replaceAll(RegExp(r'\s*list$'), '')),
        );
      case ParseIntent.createNote:
        final notes = ref.read(notesRepositoryProvider);
        final circle = await _circle();
        if (notes == null || circle == null || c.items.isEmpty) {
          await _clarify(c);
          return;
        }
        await notes.add(c.items.first.title, circleId: circle);
        state = state.copyWith(phase: TalkPhase.answered);
        await _say("Got it, I'll remember that.");
      case ParseIntent.forgetNote:
        final notes = ref.read(notesRepositoryProvider);
        final last = await notes?.latest();
        state = state.copyWith(phase: TalkPhase.answered);
        if (last == null) {
          await _say("You don't have any notes yet.");
          return;
        }
        await notes!.forget(last.id);
        await _say('Okay, I forgot “${last.text}”.');
      case ParseIntent.startRoutine:
        final routine = await ref
            .read(routinesRepositoryProvider)
            ?.findByName(c.items.firstOrNull?.title ?? '');
        state = state.copyWith(phase: TalkPhase.answered);
        if (routine == null) {
          await _say(
            "I couldn't find that routine. You can create one in Lists › Routines.",
          );
          return;
        }
        await _say("Let's start ${routine.name}.");
        state = state.copyWith(navigateTo: () => '/routine/${routine.id}');
      case ParseIntent.query:
        state = state.copyWith(phase: TalkPhase.answered);
        await _say(await _answer(c));
      case ParseIntent.complete:
        final id = c.items.firstOrNull?.targetId;
        if (id == null || service == null) {
          await _clarify(c);
          return;
        }
        await service.complete(id);
        state = state.copyWith(phase: TalkPhase.answered);
        await _say(p.done());
      case ParseIntent.snooze:
        final item = c.items.firstOrNull;
        if (item?.targetId == null || service == null) {
          await _clarify(c);
          return;
        }
        final until = _now.add(Duration(minutes: item!.snoozeMinutes ?? 10));
        await service.snooze(item.targetId!, until);
        state = state.copyWith(phase: TalkPhase.answered);
        await _say(p.snoozed(_when(until, false, null)));
      case ParseIntent.delete:
        final item = c.items.firstOrNull;
        final r = item?.targetId == null
            ? null
            : await repo?.get(item!.targetId!);
        if (r == null || service == null) {
          await _clarify(c);
          return;
        }
        await service.delete(r);
        state = state.copyWith(phase: TalkPhase.answered);
        await _say(p.deleted(r.title));
      case ParseIntent.update:
        final item = c.items.firstOrNull;
        final r = item?.targetId == null
            ? null
            : await repo?.get(item!.targetId!);
        if (r == null || service == null || item!.at == null) {
          await _clarify(c);
          return;
        }
        await service.save(
          r.copyWith(
            startAt: () => item.at,
            allDay: item.allDay,
            rrule: () => item.rrule ?? r.rrule,
            snoozedUntil: () => null,
            status: ReminderStatus.active,
          ),
        );
        state = state.copyWith(phase: TalkPhase.answered);
        await _say(
          p.created(1, _when(item.at, item.allDay, item.rrule ?? r.rrule)),
        );
    }
  }

  Future<void> _clarify(ParsedCommand c) async {
    state = state.copyWith(phase: TalkPhase.answered);
    await _say(c.clarification ?? 'Which reminder do you mean?');
  }

  Future<String> _answer(ParsedCommand c) async {
    final uid = ref.read(currentUserIdProvider) ?? '';
    final active =
        await ref.read(reminderRepositoryProvider)?.activeMine() ?? [];
    final p = _phrases;
    String time(DateTime i) => DateFormat.jm().format(toWall(i, _zone));
    switch (c.query) {
      case QueryKind.today:
        final a = agendaFor(active, userId: uid, day: _now, zone: _zone);
        return p.daySummary(
          dayWord: 'today',
          items: [
            for (final e in a.entries)
              e.allDay ? e.title : tr('{0} at {1}', [e.title, time(e.at)]),
          ],
          bills: a.bills,
          birthdays: a.birthdays,
        );
      case QueryKind.missed:
        final missed = await ref.read(missedProvider.future);
        if (missed.isEmpty) return "You haven't missed anything. 🎉";
        final titles = missed
            .map((m) => m.reminder.title)
            .toSet()
            .take(3)
            .join(', ');
        return 'You missed ${missed.length}: $titles. Want me to reschedule them? Open the Missed list.';
      case QueryKind.lookup:
        final q = c.items.firstOrNull?.title ?? '';
        final noteHits =
            await ref.read(notesRepositoryProvider)?.search(q) ?? const [];
        if (noteHits.isNotEmpty) return noteHits.first.text;
        final hits =
            await ref
                .read(reminderRepositoryProvider)
                ?.search(
                  q.split(' ').where((w) => w.length > 2).firstOrNull ?? q,
                ) ??
            [];
        if (hits.isEmpty) return "I couldn't find anything about “$q” yet.";
        final h = hits.first;
        final extra = h.notes == null ? '' : ' — ${h.notes}';
        return '${h.title}$extra${h.dueAt == null ? '' : ', ${_when(h.dueAt, h.allDay, h.rrule)}'}.';
      case QueryKind.none:
        return p.notUnderstood();
    }
  }

  // ----------------------------------------------------------- drafts

  String _confirmQuestion(List<ParsedItem> drafts) {
    if (drafts.length == 1) {
      final d = drafts.single;
      return '${d.title}, ${_when(d.at, d.allDay, d.rrule)}. Shall I add it?';
    }
    return '${drafts.length} reminders. Shall I add them?';
  }

  String _when(DateTime? at, bool allDay, String? rrule) => describeWhen(
    at: at,
    allDay: allDay,
    rrule: rrule,
    now: _now,
    zone: _zone,
  );

  void removeDraft(int i) {
    final d = [...state.drafts]..removeAt(i);
    state = state.copyWith(
      drafts: d,
      phase: d.isEmpty ? TalkPhase.idle : state.phase,
    );
  }

  void cancelDrafts() {
    state = state.copyWith(
      drafts: const [],
      phase: TalkPhase.answered,
      reply: () => 'Okay, cancelled.',
    );
  }

  /// Builds a Reminder from a draft (also used by "Edit" on a card).
  Future<Reminder?> reminderFor(ParsedItem d) async {
    final uid = ref.read(currentUserIdProvider);
    final circle = await ref
        .read(activeCircleIdProvider.future)
        .timeout(const Duration(seconds: 2), onTimeout: () => null);
    if (uid == null || circle == null) return null;
    return ReminderLogic.normalize(
      Reminder(
        id: const Uuid().v4(),
        circleId: circle,
        createdBy: uid,
        title: d.title,
        category: d.category,
        priority: d.priority,
        startAt: d.at,
        allDay: d.allDay,
        rrule: d.rrule,
        timezone: _zone,
        amount: d.amount,
        notes: d.notes,
        location: d.place == null
            ? null
            : matchPlace(
                ref.read(appPrefsProvider).places,
                d.place!,
              )?.trigger(d.placeOn),
        followUp: ref.read(appPrefsProvider).followUp,
        createdAt: _now,
      ),
    );
  }

  /// ✓ — saves every draft that has a time or a place.
  Future<int> confirm() async {
    final service = ref.read(reminderServiceProvider);
    final ready = state.drafts.where((d) => d.hasTrigger).toList();
    if (service == null) return 0;
    if (ready.isEmpty) {
      await _say('When should I remind you?');
      return 0;
    }
    // Location reminders: plan + a saved place with that name.
    for (final d in ready.where((d) => d.place != null)) {
      if (!ref.read(entitlementProvider).can(Feature.locationReminders)) {
        await _say(
          'Location reminders come with the Personal plan. You can try it free from Me › Subscription.',
        );
        return 0;
      }
      if (matchPlace(ref.read(appPrefsProvider).places, d.place!) == null) {
        await _say(
          'I don’t know where “${d.place}” is yet. Stand there and save it in Settings › Places, then ask me again.',
        );
        return 0;
      }
    }
    var saved = 0;
    for (final d in ready) {
      final r = await reminderFor(d);
      if (r == null) continue;
      await service.save(r);
      saved++;
      ref.read(telemetryProvider).event(TelemetryEvent.reminderCreated, {
        'source': 'voice',
      });
    }
    final first = ready.first;
    state = state.copyWith(
      drafts: state.drafts.where((d) => !d.hasTrigger).toList(),
      phase: TalkPhase.answered,
    );
    await _say(
      saved == 0
          ? 'Still setting up your account — try again in a moment.'
          : first.place != null && first.at == null
          ? 'Done! I’ll remind you ${first.placeOn == PlaceTransition.arrive ? 'when you get to' : 'when you leave'} ${first.place}.'
          : _phrases.created(saved, _when(first.at, first.allDay, first.rrule)),
    );
    return saved;
  }

  // ------------------------------------------------------------ voice

  Future<void> _say(String text) async {
    state = state.copyWith(reply: () => text);
    if (!_settings.spokenConfirmations) return;
    try {
      await ref.read(speakerProvider).speak(text, VoiceProfile.of(_settings));
    } on Object catch (e) {
      debugPrint('speak failed: $e');
    }
  }

  Future<String?> _circle() => ref
      .read(activeCircleIdProvider.future)
      .timeout(const Duration(seconds: 2), onTimeout: () => null);

  /// Reminders the parser can match commands against, current ones first.
  Future<List<ReminderRef>> _refs() async {
    final active =
        await ref.read(reminderRepositoryProvider)?.activeMine() ?? [];
    final now = _now;
    active.sort((a, b) {
      Duration d(Reminder r) => r.dueAt == null
          ? const Duration(days: 9999)
          : r.dueAt!.difference(now).abs();
      return d(a).compareTo(d(b));
    });
    return [for (final r in active) (id: r.id, title: r.title)];
  }
}

final NotifierProvider<AssistantController, TalkState> assistantProvider =
    NotifierProvider.autoDispose<AssistantController, TalkState>(
      AssistantController.new,
    );
