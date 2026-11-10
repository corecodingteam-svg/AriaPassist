import 'dart:async';

import 'package:aria/core/telemetry/telemetry.dart';
import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/state_views.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/circles/domain/circle.dart';
import 'package:aria/features/places/application/places_providers.dart';
import 'package:aria/features/places/presentation/places_screen.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/reminders/domain/describe.dart';
import 'package:aria/features/reminders/domain/recurrence.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/reminders/domain/reminder_logic.dart';
import 'package:aria/features/reminders/domain/tz_utils.dart';
import 'package:aria/features/reminders/presentation/formatting.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

/// Create (id == null) or edit a reminder. One screen, chips over forms:
/// a typical reminder is title + one tap.
class ReminderEditorScreen extends ConsumerStatefulWidget {
  const ReminderEditorScreen({this.reminderId, this.draft, super.key});
  final String? reminderId;

  /// Pre-filled new reminder (e.g. from a voice confirmation card).
  final Reminder? draft;

  @override
  ConsumerState<ReminderEditorScreen> createState() =>
      _ReminderEditorScreenState();
}

class _ReminderEditorScreenState extends ConsumerState<ReminderEditorScreen> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _amount = TextEditingController();

  Reminder? _original;
  bool _loaded = false;
  bool _saving = false;
  String? _error;
  bool _showMore = false;

  // Wall-clock date/time in [_zone].
  late String _zone;
  late DateTime _date; // midnight, UTC container
  TimeOfDay? _time; // null = anytime (all-day)
  RecurrenceRule? _rule;
  ReminderCategory _category = ReminderCategory.personal;
  Priority _priority = Priority.normal;
  bool _followUp = true;
  NotifyMode? _mode;
  String? _assignee; // null = me
  LocationTrigger? _trigger; // non-null = fires at a place, not a time
  bool _placeMode = false;
  bool _shared = false;

  bool get _isNew => widget.reminderId == null;

  @override
  void initState() {
    super.initState();
    _zone = ref.read(deviceTimeZoneProvider);
    final now = toWall(ref.read(clockProvider)(), _zone);
    _date = DateTime.utc(now.year, now.month, now.day);
    // Default: the next whole hour today (tomorrow 9 AM after 10 PM).
    if (now.hour >= 22) {
      _date = _date.add(const Duration(days: 1));
      _time = const TimeOfDay(hour: 9, minute: 0);
    } else {
      _time = TimeOfDay(hour: now.hour + 1, minute: 0);
    }
    if (_isNew) {
      final prefs = ref.read(appPrefsProvider);
      _category = prefs.defaultCategory;
      _priority = prefs.defaultPriority;
      _followUp = prefs.followUpEnabled;
      _loaded = true;
      final d = widget.draft;
      if (d != null) _apply(d, asDraft: true);
    } else {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final r = await ref
        .read(reminderRepositoryProvider)
        ?.get(widget.reminderId!);
    if (!mounted) return;
    setState(() {
      _loaded = true;
      if (r == null) return;
      _apply(r);
    });
  }

  void _apply(Reminder r, {bool asDraft = false}) {
    {
      if (!asDraft) _original = r;
      _zone = r.timezone ?? _zone;
      _title.text = r.title;
      _notes.text = r.notes ?? '';
      _amount.text = r.amount == null ? '' : r.amount!.toStringAsFixed(0);
      final due = r.startAt;
      if (due != null) {
        final w = toWall(due, _zone);
        _date = DateTime.utc(w.year, w.month, w.day);
        _time = r.allDay ? null : TimeOfDay(hour: w.hour, minute: w.minute);
      }
      _rule = r.rule;
      _category = r.category;
      _priority = r.priority;
      _followUp = r.followUp.enabled;
      _mode = r.notifyMode;
      _assignee = r.assignedTo;
      _trigger = r.location;
      _placeMode = r.location != null && r.startAt == null;
      _shared = r.visibility == 'shared';
      _showMore = r.notes != null || r.amount != null;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _amount.dispose();
    super.dispose();
  }

  DateTime get _wallStart => DateTime.utc(
    _date.year,
    _date.month,
    _date.day,
    _time?.hour ?? 0,
    _time?.minute ?? 0,
  );

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = tr('What should I remind you about?'));
      return;
    }
    final now = ref.read(clockProvider)().toUtc();
    final start = fromWall(_wallStart, _zone);
    final today = toWall(now, _zone);
    if (_placeMode) {
      if (_trigger == null) {
        setState(() => _error = tr('Pick a place, or save one first.'));
        return;
      }
      if (!requireFeature(context, ref, Feature.locationReminders)) return;
    } else if (_rule == null &&
        (_time != null
            ? !start.isAfter(now)
            : _date.isBefore(
                DateTime.utc(today.year, today.month, today.day),
              ))) {
      setState(
        () => _error = tr('That time has already passed — pick a later one.'),
      );
      return;
    }

    final uid = ref.read(currentUserIdProvider);
    final circleId =
        _original?.circleId ??
        await ref
            .read(activeCircleIdProvider.future)
            .timeout(const Duration(seconds: 2), onTimeout: () => null);
    if (uid == null || circleId == null) {
      setState(
        () => _error = tr(
          'Still setting up your account — try again in a moment.',
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final amount = double.tryParse(
      _amount.text.replaceAll(RegExp('[^0-9.]'), ''),
    );
    final base =
        _original ??
        Reminder(
          id: const Uuid().v4(),
          circleId: circleId,
          createdBy: uid,
          title: title,
          followUp: ref.read(appPrefsProvider).followUp,
          createdAt: now,
        );
    final r = base.copyWith(
      title: title,
      category: _category,
      priority: _priority,
      startAt: () => _placeMode ? null : start,
      allDay: !_placeMode && _time == null,
      rrule: () => _placeMode ? null : _rule?.toString(),
      location: () => _placeMode ? _trigger : null,
      timezone: _zone,
      notifyMode: () => _mode,
      followUp: _followUp ? base.followUp.copyWithEnabled() : FollowUp.off,
      amount: () => amount,
      notes: () => _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      snoozedUntil: () => null,
      status: ReminderStatus.active,
      assignedTo: () => _assignee == uid ? null : _assignee,
      // Assigned reminders are visible to creator + assignee via RLS.
      visibility: _shared ? 'shared' : 'private',
    );

    await ref.read(reminderServiceProvider)?.save(r);
    if (_isNew) {
      ref.read(telemetryProvider).event(TelemetryEvent.reminderCreated, {
        'source': widget.draft == null ? 'tap' : 'voice_edit',
        'recurring': r.rrule != null ? 1 : 0,
      });
    }
    if (_isNew && r.assignedTo != null) {
      ref.read(telemetryProvider).event(TelemetryEvent.reminderAssigned);
    }
    await _ensurePermission();
    if (!mounted) return;
    unawaited(HapticFeedback.lightImpact());
    final due = ReminderLogic.normalize(r).startAt;
    final when = due == null
        ? (r.location?.describe().replaceFirst(tr('When I'), tr('when you')) ??
              'later')
        : formatWhen(context, due, _zone, now: now, allDay: r.allDay);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isNew ? tr('Done! I’ll remind you {0}', [when]) : tr('Saved'),
        ),
      ),
    );
    context.pop();
  }

  /// Ask for notification permission in context, the first time it matters.
  Future<void> _ensurePermission() async {
    final gateway = ref.read(notificationGatewayProvider);
    final status = await gateway.status();
    if (status.notificationsAllowed || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Allow notifications?')),
        content: Text(
          tr('So I can remind you on time — even when the app is closed.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Not now')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Allow')),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await gateway.requestPermissions();
      ref.invalidate(notificationStatusProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep the active-circle query alive (Riverpod disposes unwatched
    // providers) so it's resolved by the time the user taps Save.
    ref.watch(activeCircleIdProvider);
    if (!_loaded) return const Scaffold(body: LoadingState());
    if (!_isNew && _original == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(emoji: '🤔', title: tr('Reminder not found')),
      );
    }
    final text = Theme.of(context).textTheme;
    final now = ref.read(clockProvider)().toUtc();
    final today = toWall(now, _zone);
    final todayDate = DateTime.utc(today.year, today.month, today.day);
    final isToday = _date == todayDate;
    final isTomorrow = _date == todayDate.add(const Duration(days: 1));
    final preset = RepeatPreset.match(_rule?.toString());

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? tr('New reminder') : tr('Edit reminder')),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(tr('Save')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AriaTokens.s4,
          AriaTokens.s2,
          AriaTokens.s4,
          AriaTokens.s6,
        ),
        children: [
          TextField(
            key: const Key('title-field'),
            controller: _title,
            autofocus: _isNew,
            textCapitalization: TextCapitalization.sentences,
            style: text.titleLarge,
            decoration: InputDecoration(
              hintText: tr('e.g. Pay electricity bill'),
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
          _Label(tr('When')),
          SegmentedButton<bool>(
            key: const Key('when-mode'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, label: Text(tr('⏰ At a time'))),
              ButtonSegment(value: true, label: Text(tr('📍 At a place'))),
            ],
            selected: {_placeMode},
            onSelectionChanged: (v) => setState(() => _placeMode = v.first),
          ),
          const SizedBox(height: AriaTokens.s2),
          if (_placeMode)
            ..._placeSection()
          else ...[
            Wrap(
              spacing: AriaTokens.s2,
              runSpacing: AriaTokens.s2,
              children: [
                ChoiceChip(
                  label: Text(tr('Today')),
                  selected: isToday,
                  onSelected: (_) => setState(() => _date = todayDate),
                ),
                ChoiceChip(
                  label: Text(tr('Tomorrow')),
                  selected: isTomorrow,
                  onSelected: (_) => setState(
                    () => _date = todayDate.add(const Duration(days: 1)),
                  ),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                  label: Text(
                    isToday || isTomorrow
                        ? tr('Pick date')
                        : DateFormat('EEE d MMM').format(_date),
                  ),
                  selected: !isToday && !isTomorrow,
                  onSelected: (_) async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: DateTime(_date.year, _date.month, _date.day),
                      firstDate: DateTime(
                        todayDate.year,
                        todayDate.month,
                        todayDate.day,
                      ),
                      lastDate: DateTime(todayDate.year + 5),
                    );
                    if (d != null) {
                      setState(
                        () => _date = DateTime.utc(d.year, d.month, d.day),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: AriaTokens.s2),
            Wrap(
              spacing: AriaTokens.s2,
              runSpacing: AriaTokens.s2,
              children: [
                for (final (label, minute) in _parts)
                  ChoiceChip(
                    label: Text('$label · ${_fmtMinute(context, minute)}'),
                    selected: _time == _tod(minute),
                    onSelected: (_) => setState(() => _time = _tod(minute)),
                  ),
                ChoiceChip(
                  label: Text(tr('Anytime')),
                  selected: _time == null,
                  onSelected: (_) => setState(() => _time = null),
                ),
                ChoiceChip(
                  key: const Key('custom-time'),
                  avatar: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(
                    _time != null && !_isDayPart(_time!)
                        ? _time!.format(context)
                        : tr('Pick time'),
                  ),
                  selected: _time != null && !_isDayPart(_time!),
                  onSelected: (_) async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: _time ?? TimeOfDay.now(),
                    );
                    if (t != null) setState(() => _time = t);
                  },
                ),
              ],
            ),
          ],
          if (!_placeMode) _Label(tr('Repeat')),
          if (!_placeMode)
            Wrap(
              spacing: AriaTokens.s2,
              runSpacing: AriaTokens.s2,
              children: [
                for (final p in RepeatPreset.values)
                  ChoiceChip(
                    label: Text(p.label),
                    selected: preset == p,
                    onSelected: (_) => setState(() => _rule = p.rule),
                  ),
                ChoiceChip(
                  label: Text(
                    preset == null && _rule != null
                        ? describeRule(_rule!, _wallStart)
                        : tr('Custom…'),
                  ),
                  selected: preset == null && _rule != null,
                  onSelected: (_) async {
                    final r = await showDialog<RecurrenceRule>(
                      context: context,
                      builder: (_) => _CustomRepeatDialog(
                        initial: _rule ?? RecurrenceRule.weekly,
                        anchor: _wallStart,
                      ),
                    );
                    if (r != null) setState(() => _rule = r);
                  },
                ),
              ],
            ),
          _Label(tr('Category')),
          Wrap(
            spacing: AriaTokens.s2,
            runSpacing: AriaTokens.s2,
            children: [
              for (final c in ReminderCategory.values)
                ChoiceChip(
                  label: Text('${c.emoji} ${c.label}'),
                  selected: _category == c,
                  onSelected: (_) => setState(() {
                    _category = c;
                    if (c == ReminderCategory.bills) _showMore = true;
                  }),
                ),
            ],
          ),
          ..._circleSection(),
          _Label(tr('Priority')),
          SegmentedButton<Priority>(
            showSelectedIcon: false,
            segments: [
              for (final p in Priority.values)
                ButtonSegment(value: p, label: Text(p.label)),
            ],
            selected: {_priority},
            onSelectionChanged: (s) => setState(() => _priority = s.first),
          ),
          const SizedBox(height: AriaTokens.s2),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Follow up if I miss it')),
            subtitle: Text(tr('Nudge every 10 min, up to 3 times')),
            value: _followUp,
            onChanged: (v) => setState(() => _followUp = v),
          ),
          if (!_showMore)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _showMore = true),
                icon: const Icon(Icons.expand_more_rounded),
                label: Text(tr('More options')),
              ),
            )
          else ...[
            const SizedBox(height: AriaTokens.s2),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: tr('Amount (for bills)'),
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: AriaTokens.s3),
            TextField(
              controller: _notes,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(labelText: tr('Notes')),
            ),
            _Label(tr('Remind me with')),
            Wrap(
              spacing: AriaTokens.s2,
              runSpacing: AriaTokens.s2,
              children: [
                for (final (mode, label) in [
                  (null, tr('Default')),
                  (NotifyMode.text, tr('💬 Notification')),
                  (NotifyMode.vibrate, tr('📳 Vibrate only')),
                  (NotifyMode.silent, tr('🔕 Silent')),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _mode == mode,
                    onSelected: (_) => setState(() => _mode = mode),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AriaTokens.s5),
          FilledButton(
            key: const Key('save-reminder'),
            onPressed: _saving ? null : _save,
            child: Text(_isNew ? tr('Set reminder') : tr('Save changes')),
          ),
        ],
      ),
    );
  }

  /// Saved places + arrive/leave. Places are added in Settings › Places.
  List<Widget> _placeSection() {
    final places = ref.watch(placesProvider);
    final on = _trigger?.on ?? PlaceTransition.arrive;
    return [
      SegmentedButton<PlaceTransition>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: PlaceTransition.arrive,
            label: Text(tr('When I arrive')),
          ),
          ButtonSegment(
            value: PlaceTransition.leave,
            label: Text(tr('When I leave')),
          ),
        ],
        selected: {on},
        onSelectionChanged: (v) => setState(() {
          final t = _trigger;
          if (t != null) {
            _trigger = LocationTrigger(
              placeId: t.placeId,
              placeName: t.placeName,
              lat: t.lat,
              lng: t.lng,
              radiusM: t.radiusM,
              on: v.first,
            );
          }
          _placeOn = v.first;
        }),
      ),
      const SizedBox(height: AriaTokens.s2),
      Wrap(
        spacing: AriaTokens.s2,
        runSpacing: AriaTokens.s2,
        children: [
          for (final p in places)
            ChoiceChip(
              key: Key('place-${p.name}'),
              label: Text('${p.emoji} ${p.name}'),
              selected: _trigger?.placeId == p.id,
              onSelected: (_) => setState(
                () => _trigger = p.trigger(_trigger?.on ?? _placeOn),
              ),
            ),
          ActionChip(
            key: const Key('new-place'),
            avatar: const Icon(Icons.add_location_alt_rounded, size: 18),
            label: Text(tr('Save a place')),
            onPressed: () async {
              final p = await showAddPlaceSheet(context, ref);
              if (p != null) {
                setState(() => _trigger = p.trigger(_trigger?.on ?? _placeOn));
              }
            },
          ),
        ],
      ),
    ];
  }

  PlaceTransition _placeOn = PlaceTransition.arrive;

  /// "Assign to" chips + "Share with Circle" when the active circle allows.
  List<Widget> _circleSection() {
    final circle = ref.watch(activeCircleProvider);
    if (circle == null || circle.isPersonal) return const [];
    final me = ref.watch(currentUserIdProvider);
    final members = ref.watch(membersProvider(circle.id)).value ?? const [];
    // Editing a reminder someone else created: show who it's from instead.
    final mine = _original == null || _original!.createdBy == me;
    final others = members.where((m) => m.userId != me).toList();
    final planAllows = planOfCircle(
      ref.watch(plansProvider),
      circle,
    ).has(Feature.assignReminders);
    return [
      if (circle.canAssign && mine && others.isNotEmpty && !planAllows)
        ListTile(
          key: const Key('assign-locked'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_outline_rounded),
          title: Text(tr('Remind someone else')),
          subtitle: Text(
            tr('Assign reminders to people in {0} with Family', [circle.name]),
          ),
          onTap: () => requireCircleFeature(
            context,
            ref,
            circle,
            Feature.assignReminders,
          ),
        ),
      if (circle.canAssign && mine && others.isNotEmpty && planAllows) ...[
        _Label(tr('For')),
        Wrap(
          spacing: AriaTokens.s2,
          runSpacing: AriaTokens.s2,
          children: [
            ChoiceChip(
              key: const Key('assign-me'),
              label: Text(tr('Me')),
              selected: _assignee == null || _assignee == me,
              onSelected: (_) => setState(() => _assignee = null),
            ),
            for (final m in others)
              ChoiceChip(
                key: Key('assign-${m.userId}'),
                label: Text(
                  m.role == CircleRole.dependent ? '${m.name} 💜' : m.name,
                ),
                selected: _assignee == m.userId,
                onSelected: (_) => setState(() => _assignee = m.userId),
              ),
          ],
        ),
      ],
      if (_assignee == null || _assignee == me)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Share with {0}', [circle.name])),
          subtitle: Text(tr('Everyone in the Circle can see it')),
          value: _shared,
          onChanged: (v) => setState(() => _shared = v),
        ),
    ];
  }

  /// The user's times of day (Settings › Simplify › Default times).
  List<(String, int)> get _parts {
    final d = ref.read(appPrefsProvider).dayParts;
    return [
      (tr('Morning'), d.morning),
      (tr('Afternoon'), d.afternoon),
      (tr('Evening'), d.evening),
      (tr('Night'), d.night),
    ];
  }

  static TimeOfDay _tod(int minute) =>
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60);

  bool _isDayPart(TimeOfDay t) => _parts.any((p) => _tod(p.$2) == t);

  String _fmtMinute(BuildContext context, int m) => _tod(m).format(context);
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AriaTokens.s5, bottom: AriaTokens.s2),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _CustomRepeatDialog extends StatefulWidget {
  const _CustomRepeatDialog({required this.initial, required this.anchor});
  final RecurrenceRule initial;
  final DateTime anchor;

  @override
  State<_CustomRepeatDialog> createState() => _CustomRepeatDialogState();
}

class _CustomRepeatDialogState extends State<_CustomRepeatDialog> {
  late Freq _freq = widget.initial.freq;
  late int _interval = widget.initial.interval;
  late final Set<int> _days = {...widget.initial.byDay};

  static const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  RecurrenceRule get _rule => RecurrenceRule(
    freq: _freq,
    interval: _interval,
    byDay: _freq == Freq.weekly ? _days : const {},
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Repeat')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(tr('Every')),
            IconButton(
              tooltip: tr('Less often'),
              onPressed: _interval > 1
                  ? () => setState(() => _interval--)
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$_interval', style: Theme.of(context).textTheme.titleMedium),
            IconButton(
              tooltip: tr('More'),
              onPressed: _interval < 99
                  ? () => setState(() => _interval++)
                  : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
            DropdownButton<Freq>(
              value: _freq,
              onChanged: (f) => setState(() => _freq = f!),
              items: [
                for (final f in Freq.values)
                  DropdownMenuItem(
                    value: f,
                    child: Text(switch (f) {
                      Freq.daily => _interval == 1 ? 'day' : 'days',
                      Freq.weekly => _interval == 1 ? 'week' : 'weeks',
                      Freq.monthly => _interval == 1 ? 'month' : 'months',
                      Freq.yearly => _interval == 1 ? 'year' : 'years',
                    }),
                  ),
              ],
            ),
          ],
        ),
        if (_freq == Freq.weekly) ...[
          const SizedBox(height: AriaTokens.s3),
          Wrap(
            spacing: AriaTokens.s1,
            children: [
              for (var d = 1; d <= 7; d++)
                Semantics(
                  label: _dayNames[d - 1],
                  child: FilterChip(
                    showCheckmark: false,
                    label: Text(_dayLetters[d - 1]),
                    selected: _days.contains(d),
                    onSelected: (on) =>
                        setState(() => on ? _days.add(d) : _days.remove(d)),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: AriaTokens.s3),
        Text(
          describeRule(_rule, widget.anchor),
          style: TextStyle(color: context.palette.muted),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('Cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _rule),
        child: Text(tr('Done')),
      ),
    ],
  );
}
