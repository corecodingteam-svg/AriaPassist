import 'dart:async';

import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/core/widgets/state_views.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/lists/organize_providers.dart';
import 'package:aria/features/people/domain/person.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Call / WhatsApp / SMS buttons. Calling counts as "keeping in touch".
class ContactActions extends ConsumerWidget {
  const ContactActions({required this.person, this.wish, super.key});
  final Person person;

  /// Pre-filled message (e.g. birthday wish) for WhatsApp/SMS.
  final String? wish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = wish ?? tr('Hi {0}!', [person.name]);
    final call = person.callUri;
    final wa = person.whatsappUri(text);
    final sms = person.smsUri(text);
    if (call == null) {
      return Text(
        tr('Add a phone number to call or message {0}.', [person.name]),
        style: TextStyle(color: context.palette.muted),
      );
    }
    return Wrap(
      spacing: AriaTokens.s2,
      children: [
        FilledButton.icon(
          onPressed: () async {
            await launchUrl(call);
            await ref
                .read(peopleRepositoryProvider)
                ?.markContacted(person.id, ref.read(clockProvider)().toUtc());
          },
          icon: const Icon(Icons.call_rounded),
          label: Text(tr('Call')),
        ),
        OutlinedButton.icon(
          onPressed: () => launchUrl(wa!, mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.chat_rounded),
          label: Text(tr('WhatsApp')),
        ),
        OutlinedButton.icon(
          onPressed: () => launchUrl(sms!),
          icon: const Icon(Icons.sms_outlined),
          label: Text(tr('SMS')),
        ),
      ],
    );
  }
}

class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(peopleProvider);
    final now = (ref.watch(nowProvider).value ?? DateTime.now()).toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(tr('People'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-person',
        onPressed: () => context.push('/people/new'),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(tr('Add')),
      ),
      body: people.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(message: '$e'),
        data: (all) => all.isEmpty
            ? EmptyState(
                emoji: '👪',
                title: tr('Remember the people who matter'),
                message: tr(
                  'Birthdays, anniversaries, and a gentle nudge when you haven’t called in a while.',
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AriaTokens.s4,
                  AriaTokens.s2,
                  AriaTokens.s4,
                  120,
                ),
                children: [
                  for (final person in all)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AriaTokens.s2),
                      child: AriaCard(
                        onTap: () => context.push('/people/${person.id}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              person.relation == null
                                  ? person.name
                                  : '${person.name} · ${person.relation}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            ...[
                              if (Person.nextOccurrence(person.birthday, today)
                                  case final b?)
                                '🎂 ${b == today ? 'Birthday today!' : DateFormat('d MMM').format(b)}',
                              if (person.callEveryDays != null)
                                person.dueForCall(now)
                                    ? tr('📞 Time to call — {0}', [
                                        person.daysSinceContact(now) == null
                                            ? tr('not called yet')
                                            : tr(
                                                '{0} days since your last call',
                                                [person.daysSinceContact(now)],
                                              ),
                                      ])
                                    : tr('📞 Called {0} days ago', [
                                        person.daysSinceContact(now),
                                      ]),
                            ].map(
                              (l) => Text(
                                l,
                                style: TextStyle(
                                  color:
                                      l.contains('Time to call') ||
                                          l.contains('today')
                                      ? p.primary
                                      : p.muted,
                                ),
                              ),
                            ),
                            const SizedBox(height: AriaTokens.s2),
                            ContactActions(
                              person: person,
                              wish:
                                  Person.nextOccurrence(
                                        person.birthday,
                                        today,
                                      ) ==
                                      today
                                  ? person.wish(birthday: true)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Add / edit a person. Saving keeps their birthday, anniversary and
/// "call every N days" reminders in step.
class PersonEditorScreen extends ConsumerStatefulWidget {
  const PersonEditorScreen({this.personId, super.key});
  final String? personId;

  @override
  ConsumerState<PersonEditorScreen> createState() => _PersonEditorScreenState();
}

class _PersonEditorScreenState extends ConsumerState<PersonEditorScreen> {
  final _name = TextEditingController();
  final _relation = TextEditingController();
  final _phone = TextEditingController();
  Person? _original;
  DateTime? _birthday;
  DateTime? _anniversary;
  int? _every;
  bool _shared = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.personId == null) {
      _loaded = true;
    } else {
      unawaited(() async {
        final p = await ref
            .read(peopleRepositoryProvider)
            ?.get(widget.personId!);
        if (!mounted) return;
        setState(() {
          _loaded = true;
          _original = p;
          _name.text = p?.name ?? '';
          _relation.text = p?.relation ?? '';
          _phone.text = p?.phone ?? '';
          _birthday = p?.birthday;
          _anniversary = p?.anniversary;
          _every = p?.callEveryDays;
          _shared = p?.visibility == 'shared';
        });
      }());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _relation.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = ref.read(peopleRepositoryProvider);
    final name = _name.text.trim();
    if (repo == null || name.isEmpty) return;
    final circle =
        _original?.circleId ?? await ref.read(activeCircleIdProvider.future);
    if (circle == null) return;
    final base = _original ?? repo.newPerson(name, circleId: circle);
    final person = base.copyWith(
      name: name,
      relation: () =>
          _relation.text.trim().isEmpty ? null : _relation.text.trim(),
      phone: () => _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      birthday: () => _birthday,
      anniversary: () => _anniversary,
      callEveryDays: () => _every,
      visibility: _shared ? 'shared' : 'private',
    );
    await repo.save(person, now: ref.read(clockProvider)().toUtc());
    if (mounted) context.pop();
  }

  bool get _canShare {
    final circle = ref.watch(activeCircleProvider);
    final me = ref.watch(currentUserIdProvider);
    return circle != null &&
        !circle.isPersonal &&
        (_original == null || _original!.createdBy == me);
  }

  Future<DateTime?> _pickDate(DateTime? initial) => showDatePicker(
    context: context,
    initialDate: initial ?? DateTime(1990),
    firstDate: DateTime(1900),
    lastDate: DateTime.now(),
  );

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold(body: LoadingState());
    final person = _original;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          person == null ? tr('Add person') : tr('Edit {0}', [person.name]),
        ),
        actions: [
          if (person != null)
            IconButton(
              tooltip: tr('Delete'),
              onPressed: () async {
                await ref.read(peopleRepositoryProvider)?.delete(person);
                if (context.mounted) context.pop();
              },
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          TextButton(onPressed: _save, child: Text(tr('Save'))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AriaTokens.s4),
        children: [
          TextField(
            key: const Key('person-name'),
            controller: _name,
            autofocus: person == null,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tr('Name')),
          ),
          const SizedBox(height: AriaTokens.s3),
          TextField(
            controller: _relation,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: tr('Relation (optional)'),
              hintText: tr('Dad, best friend…'),
            ),
          ),
          const SizedBox(height: AriaTokens.s3),
          TextField(
            key: const Key('person-phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: tr('Phone (for Call / WhatsApp)'),
              prefixText: '+91 ',
            ),
          ),
          if (_canShare)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Share with Circle')),
              subtitle: Text(tr('Everyone can see birthdays & call reminders')),
              value: _shared,
              onChanged: (v) => setState(() => _shared = v),
            ),
          const SizedBox(height: AriaTokens.s4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Text('🎂', style: TextStyle(fontSize: 22)),
            title: Text(tr('Birthday')),
            subtitle: Text(
              _birthday == null
                  ? tr('Not set')
                  : DateFormat('d MMMM').format(_birthday!),
            ),
            trailing: _birthday == null
                ? null
                : IconButton(
                    tooltip: tr('Clear birthday'),
                    onPressed: () => setState(() => _birthday = null),
                    icon: const Icon(Icons.clear),
                  ),
            onTap: () async {
              final d = await _pickDate(_birthday);
              if (d != null) setState(() => _birthday = d);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Text('💍', style: TextStyle(fontSize: 22)),
            title: Text(tr('Anniversary')),
            subtitle: Text(
              _anniversary == null
                  ? tr('Not set')
                  : DateFormat('d MMMM').format(_anniversary!),
            ),
            trailing: _anniversary == null
                ? null
                : IconButton(
                    tooltip: tr('Clear anniversary'),
                    onPressed: () => setState(() => _anniversary = null),
                    icon: const Icon(Icons.clear),
                  ),
            onTap: () async {
              final d = await _pickDate(_anniversary);
              if (d != null) setState(() => _anniversary = d);
            },
          ),
          const SizedBox(height: AriaTokens.s3),
          Text(
            tr('Keep in touch'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            tr('Aria nudges you when you haven’t called in a while.'),
            style: TextStyle(color: context.palette.muted),
          ),
          const SizedBox(height: AriaTokens.s2),
          Wrap(
            spacing: AriaTokens.s2,
            children: [
              for (final (label, days) in [
                (tr('Off'), null),
                (tr('Every week'), 7),
                (tr('Every 2 weeks'), 14),
                (tr('Every month'), 30),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _every == days,
                  onSelected: (_) => setState(() => _every = days),
                ),
            ],
          ),
          if (person != null) ...[
            const SizedBox(height: AriaTokens.s5),
            ContactActions(person: person),
          ],
        ],
      ),
    );
  }
}
