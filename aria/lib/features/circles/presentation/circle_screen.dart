import 'dart:async';

import 'package:aria/core/telemetry/telemetry.dart';
import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/core/widgets/aria_card.dart';
import 'package:aria/core/widgets/prompts.dart';
import 'package:aria/core/widgets/state_views.dart';
import 'package:aria/data/providers.dart';
import 'package:aria/features/auth/data/auth_repository.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/circles/domain/circle.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/reminders/domain/reminder.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/subscription/domain/plan.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// Runs a server operation, syncs, and shows friendly errors.
Future<bool> runCircleOp(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() op, {
  String? done,
}) async {
  try {
    await op();
    await ref.read(syncEngineProvider)?.syncNow();
    if (done != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    }
    return true;
  } on Object catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(circleErrorMessage(e))));
    }
    return false;
  }
}

/// Circle management (spec 6.7) + switcher.
class CircleScreen extends ConsumerWidget {
  const CircleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circles = ref.watch(myCirclesProvider);
    final active = ref.watch(activeCircleProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Circle'))),
      body: circles.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(message: '$e'),
        data: (all) => ListView(
          padding: const EdgeInsets.fromLTRB(
            AriaTokens.s4,
            AriaTokens.s2,
            AriaTokens.s4,
            120,
          ),
          children: [
            Text(tr('Your Circles'), style: text.titleMedium),
            const SizedBox(height: AriaTokens.s2),
            for (final c in all)
              Padding(
                padding: const EdgeInsets.only(bottom: AriaTokens.s2),
                child: AriaCard(
                  onTap: () => ref
                      .read(appPrefsProvider.notifier)
                      .update(
                        (p) => p.copyWith(
                          activeCircleId: () => c.isPersonal ? null : c.id,
                        ),
                      ),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: Text(
                          c.type.emoji,
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                      const SizedBox(width: AriaTokens.s3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name, style: text.titleMedium),
                            Text(
                              c.isPersonal
                                  ? tr('Just you')
                                  : tr('{0} people · you’re {1}', [
                                      c.memberCount,
                                      c.myRole.label.toLowerCase(),
                                    ]),
                              style: TextStyle(color: context.palette.muted),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        c.id == active?.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: context.palette.primary,
                        semanticLabel: c.id == active?.id
                            ? tr('Active')
                            : tr('Switch to {0}', [c.name]),
                      ),
                    ],
                  ),
                ),
              ),
            Wrap(
              spacing: AriaTokens.s2,
              children: [
                OutlinedButton.icon(
                  key: const Key('create-circle'),
                  onPressed: () => _create(context, ref),
                  icon: const Icon(Icons.group_add_rounded),
                  label: Text(tr('Create a Circle')),
                ),
                OutlinedButton.icon(
                  key: const Key('join-code'),
                  onPressed: () async {
                    final code = await promptText(
                      context,
                      title: tr('Join with a code'),
                      hint: tr('Paste the code or link'),
                      action: tr('Next'),
                    );
                    if (code == null || code.isEmpty || !context.mounted) {
                      return;
                    }
                    final token = code.split('/').last.trim();
                    unawaited(context.push('/join/$token'));
                  },
                  icon: const Icon(Icons.login_rounded),
                  label: Text(tr('Join with a code')),
                ),
              ],
            ),
            if (active != null && !active.isPersonal) ...[
              const Divider(height: AriaTokens.s6),
              _CircleDetails(circle: active),
            ] else ...[
              const SizedBox(height: AriaTokens.s5),
              AriaCard(
                child: Text(
                  tr(
                    '👪  Create a family Circle to share lists, remind each other, and look after parents — one plan for up to 5 people.',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<(String, CircleType)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CreateCircleSheet(),
    );
    if (result == null || !context.mounted) return;
    String? id;
    final ok = await runCircleOp(context, ref, () async {
      id = await ref.read(circleApiProvider).createCircle(result.$1, result.$2);
      ref.read(telemetryProvider).event(TelemetryEvent.circleCreated, {
        'type': result.$2.name,
      });
    });
    if (ok && id != null) {
      ref
          .read(appPrefsProvider.notifier)
          .update((p) => p.copyWith(activeCircleId: () => id));
    }
  }
}

class _CreateCircleSheet extends StatefulWidget {
  const _CreateCircleSheet();

  @override
  State<_CreateCircleSheet> createState() => _CreateCircleSheetState();
}

class _CreateCircleSheetState extends State<_CreateCircleSheet> {
  final _name = TextEditingController(text: tr('My family'));
  CircleType _type = CircleType.family;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      AriaTokens.s5,
      0,
      AriaTokens.s5,
      AriaTokens.s5 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('Create a Circle'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AriaTokens.s3),
        SegmentedButton<CircleType>(
          segments: [
            ButtonSegment(
              value: CircleType.family,
              label: Text(tr('👪 Family')),
            ),
            ButtonSegment(value: CircleType.team, label: Text(tr('💼 Team'))),
          ],
          selected: {_type},
          onSelectionChanged: (v) => setState(() {
            _type = v.first;
            if (_name.text == 'My family' || _name.text == 'My team') {
              _name.text = _type == CircleType.family
                  ? tr('My family')
                  : tr('My team');
            }
          }),
        ),
        const SizedBox(height: AriaTokens.s3),
        TextField(
          key: const Key('circle-name'),
          controller: _name,
          decoration: InputDecoration(labelText: tr('Name')),
        ),
        const SizedBox(height: AriaTokens.s2),
        Text(
          tr(
            'On the free plan a Circle has just you. Upgrade to Family (5) or Team (15) to add people.',
          ),
          style: TextStyle(color: context.palette.muted),
        ),
        const SizedBox(height: AriaTokens.s4),
        FilledButton(
          key: const Key('create-circle-go'),
          onPressed: () => _name.text.trim().isEmpty
              ? null
              : Navigator.pop(context, (_name.text.trim(), _type)),
          child: Text(tr('Create')),
        ),
      ],
    ),
  );
}

class _CircleDetails extends ConsumerWidget {
  const _CircleDetails({required this.circle});
  final Circle circle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members =
        ref.watch(membersProvider(circle.id)).value ?? const <Member>[];
    final me = ref.watch(currentUserIdProvider);
    final text = Theme.of(context).textTheme;
    final api = ref.read(circleApiProvider);
    final manage = circle.myRole.canManage;
    final assigned =
        ref.watch(assignedByMeProvider(circle.id)).value ?? const <Reminder>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(circle.name, style: text.titleLarge)),
            if (manage)
              IconButton(
                tooltip: tr('Rename Circle'),
                onPressed: () async {
                  final n = await promptText(
                    context,
                    title: tr('Rename Circle'),
                    initial: circle.name,
                  );
                  if (n != null && n.isNotEmpty && context.mounted) {
                    await runCircleOp(
                      context,
                      ref,
                      () => api.renameCircle(circle.id, n),
                    );
                  }
                },
                icon: const Icon(Icons.edit_rounded),
              ),
          ],
        ),
        const SizedBox(height: AriaTokens.s2),
        if (manage)
          FilledButton.icon(
            key: const Key('invite'),
            onPressed: () {
              final plan = planOfCircle(ref.read(plansProvider), circle);
              if (circle.memberCount >= plan.maxSeats) {
                requireCircleFeature(
                  context,
                  ref,
                  circle,
                  Feature.sharedCircle,
                );
                if (plan.has(Feature.sharedCircle)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        tr('{0} is full ({1} people on {2}).', [
                          circle.name,
                          plan.maxSeats,
                          plan.name,
                        ]),
                      ),
                    ),
                  );
                }
                return;
              }
              unawaited(showInviteSheet(context, ref, circle));
            },
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: Text(tr('Invite someone')),
          ),
        const SizedBox(height: AriaTokens.s3),
        Text(tr('Members'), style: text.titleMedium),
        for (final m in members)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Text(m.name.characters.first)),
            title: Text(m.name),
            subtitle: Text(
              [
                m.role.label,
                if (m.simpleLock != null) tr('Simple Mode locked 🔒'),
              ].join(' · '),
            ),
            trailing: manage && m.userId != me && m.role != CircleRole.owner
                ? PopupMenuButton<String>(
                    tooltip: tr('Manage {0}', [m.name]),
                    onSelected: (v) => _memberAction(context, ref, m, v),
                    itemBuilder: (_) => [
                      for (final r in [
                        CircleRole.admin,
                        CircleRole.member,
                        CircleRole.dependent,
                      ])
                        if (r != m.role &&
                            (r != CircleRole.admin ||
                                circle.myRole == CircleRole.owner))
                          PopupMenuItem(
                            value: 'role:${r.name}',
                            child: Text(
                              tr('Make {0}', [r.label.toLowerCase()]),
                            ),
                          ),
                      if (m.role == CircleRole.dependent)
                        PopupMenuItem(
                          value: m.simpleLock == null ? 'lock' : 'unlock',
                          child: Text(
                            m.simpleLock == null
                                ? tr('Lock Simple Mode with a PIN')
                                : tr('Remove Simple Mode lock'),
                          ),
                        ),
                      if (circle.myRole == CircleRole.owner)
                        PopupMenuItem(
                          value: 'owner',
                          child: Text(tr('Make owner')),
                        ),
                      PopupMenuItem(
                        value: 'remove',
                        child: Text(tr('Remove from Circle')),
                      ),
                    ],
                  )
                : null,
          ),
        if (assigned.isNotEmpty) ...[
          const SizedBox(height: AriaTokens.s3),
          Text(tr('Reminders you assigned'), style: text.titleMedium),
          for (final r in assigned)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                r.status == ReminderStatus.done ||
                        r.lastDoneAt != null && r.isRecurring && _doneToday(r)
                    ? Icons.check_circle_rounded
                    : r.status == ReminderStatus.missed
                    ? Icons.error_rounded
                    : Icons.schedule_rounded,
                color: r.status == ReminderStatus.missed
                    ? context.palette.danger
                    : context.palette.primary,
              ),
              title: Text(r.title),
              subtitle: Text(
                tr('for {0} · {1}', [
                  members
                          .where((m) => m.userId == r.assignedTo)
                          .firstOrNull
                          ?.name ??
                      'someone',
                  _statusText(r),
                ]),
              ),
              onTap: () => context.push('/reminder/${r.id}'),
            ),
        ],
        if (manage) ...[
          const SizedBox(height: AriaTokens.s3),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Members can assign reminders')),
            subtitle: Text(tr('Owners and admins always can')),
            value: circle.membersCanAssign,
            onChanged: (v) => runCircleOp(
              context,
              ref,
              () => api.updateCircleSettings(circle.id, {
                ...circle.settings,
                'members_can_assign': v,
              }),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history_rounded),
            title: Text(tr('Activity log')),
            subtitle: Text(tr('Who added, removed or assigned what')),
            onTap: () {
              if (requireCircleFeature(
                context,
                ref,
                circle,
                Feature.auditLog,
              )) {
                unawaited(context.push('/circle/${circle.id}/audit'));
              }
            },
          ),
        ],
        const SizedBox(height: AriaTokens.s3),
        if (circle.myRole != CircleRole.owner)
          TextButton.icon(
            key: const Key('leave-circle'),
            onPressed: () async {
              final ok = await runCircleOp(
                context,
                ref,
                () => api.leave(circle.id),
                done: tr('You left {0}', [circle.name]),
              );
              if (ok) {
                ref
                    .read(appPrefsProvider.notifier)
                    .update((p) => p.copyWith(activeCircleId: () => null));
              }
            },
            icon: Icon(Icons.logout_rounded, color: context.palette.danger),
            label: Text(
              tr('Leave {0}', [circle.name]),
              style: TextStyle(color: context.palette.danger),
            ),
          ),
      ],
    );
  }

  static bool _doneToday(Reminder r) {
    final d = r.lastDoneAt!.toLocal();
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  static String _statusText(Reminder r) {
    if (r.status == ReminderStatus.done) return tr('done ✓');
    if (r.status == ReminderStatus.missed) return 'missed';
    if (r.isRecurring && r.lastDoneAt != null && _doneToday(r)) {
      return tr('done today ✓');
    }
    return 'pending';
  }

  Future<void> _memberAction(
    BuildContext context,
    WidgetRef ref,
    Member m,
    String v,
  ) async {
    final api = ref.read(circleApiProvider);
    if (v.startsWith('role:')) {
      await runCircleOp(
        context,
        ref,
        () =>
            api.setRole(circle.id, m.userId, CircleRole.parse(v.substring(5))),
      );
    } else if (v == 'remove') {
      await runCircleOp(
        context,
        ref,
        () => api.removeMember(circle.id, m.userId),
        done: tr('{0} was removed', [m.name]),
      );
    } else if (v == 'owner') {
      await runCircleOp(
        context,
        ref,
        () => api.transferOwnership(circle.id, m.userId),
        done: tr('{0} is now the owner', [m.name]),
      );
    } else if (v == 'lock') {
      if (!requireCircleFeature(context, ref, circle, Feature.dependents)) {
        return;
      }
      final pin = await promptText(
        context,
        title: tr('Set a 4-digit PIN'),
        hint: tr('Needed to leave Simple Mode'),
        action: tr('Lock'),
      );
      if (pin == null ||
          !RegExp(r'^\d{4}$').hasMatch(pin) ||
          !context.mounted) {
        return;
      }
      await runCircleOp(
        context,
        ref,
        () => api.updateMemberSettings(circle.id, m.userId, {
          ...m.settings,
          'simple_lock': SimpleLock.create(pin).toJson(),
        }),
        done: tr('Simple Mode is locked for {0}', [m.name]),
      );
    } else if (v == 'unlock') {
      await runCircleOp(
        context,
        ref,
        () => api.updateMemberSettings(
          circle.id,
          m.userId,
          {...m.settings}..remove('simple_lock'),
        ),
      );
    }
  }
}

/// Invite: pick a role → QR code + share + copy.
Future<void> showInviteSheet(
  BuildContext context,
  WidgetRef ref,
  Circle circle,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _InviteSheet(circle: circle),
);

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet({required this.circle});
  final Circle circle;

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  CircleRole _role = CircleRole.member;
  String? _token;
  String? _error;
  bool _busy = false;

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await ref
          .read(circleApiProvider)
          .createInvite(widget.circle.id, _role);
      setState(() => _token = t);
    } on Object catch (e) {
      setState(() => _error = circleErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final link = _token == null ? null : inviteLink(_token!);
    final message = tr(
      'Join {0} on Aria 💜\n{1}\nOr open Aria › Circle › Join with a code: {2}',
      [widget.circle.name, link, _token],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AriaTokens.s5,
        0,
        AriaTokens.s5,
        AriaTokens.s5,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('Invite to {0}', [widget.circle.name]),
            style: text.titleLarge,
          ),
          const SizedBox(height: AriaTokens.s3),
          if (_token == null) ...[
            for (final r in [
              CircleRole.member,
              CircleRole.dependent,
              if (widget.circle.myRole == CircleRole.owner) CircleRole.admin,
            ])
              RadioListTile<CircleRole>(
                // ignore: deprecated_member_use -- small, self-contained group
                groupValue: _role,
                value: r,
                // ignore: deprecated_member_use -- see above
                onChanged: (v) => setState(() => _role = v!),
                title: Text(r.label),
                subtitle: Text(r.description),
              ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: context.palette.danger)),
            const SizedBox(height: AriaTokens.s2),
            FilledButton(
              key: const Key('make-invite'),
              onPressed: _busy ? null : _create,
              child: Text(tr('Create invite')),
            ),
          ] else ...[
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(AriaTokens.s3),
                child: QrImageView(
                  data: link!,
                  size: 200,
                  semanticsLabel: tr('Invite QR code'),
                ),
              ),
            ),
            const SizedBox(height: AriaTokens.s2),
            SelectableText(
              tr('Code: {0}', [_token]),
              key: const Key('invite-code'),
              textAlign: TextAlign.center,
            ),
            Text(
              tr('Works once · expires in 7 days · joins as {0}', [
                _role.label.toLowerCase(),
              ]),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.muted),
            ),
            const SizedBox(height: AriaTokens.s3),
            FilledButton.icon(
              onPressed: () =>
                  SharePlus.instance.share(ShareParams(text: message)),
              icon: const Icon(Icons.share_rounded),
              label: Text(tr('Share via WhatsApp, SMS…')),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _token!));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(tr('Code copied'))));
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: Text(tr('Copy code')),
            ),
          ],
        ],
      ),
    );
  }
}

/// `aria:///join/<token>` — preview, then join.
class JoinCircleScreen extends ConsumerStatefulWidget {
  const JoinCircleScreen({required this.token, super.key});
  final String token;

  @override
  ConsumerState<JoinCircleScreen> createState() => _JoinCircleScreenState();
}

class _JoinCircleScreenState extends ConsumerState<JoinCircleScreen> {
  late final Future<InvitePreview?> _preview = ref
      .read(circleApiProvider)
      .previewInvite(widget.token);
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Join a Circle'))),
      body: FutureBuilder<InvitePreview?>(
        future: _preview,
        builder: (context, snap) {
          if (snap.hasError) {
            return ErrorState(message: circleErrorMessage(snap.error!));
          }
          if (snap.connectionState != ConnectionState.done) {
            return const LoadingState();
          }
          final p = snap.data;
          if (p == null) {
            return EmptyState(
              emoji: '🤔',
              title: tr('Invite not found'),
              message: tr('Check the code and try again.'),
            );
          }
          final problem = p.alreadyMember
              ? tr('You’re already in {0}.', [p.circleName])
              : p.expired
              ? tr('This invite has expired. Ask for a new one.')
              : p.used
              ? tr('This invite was already used. Ask for a new one.')
              : null;
          return ListView(
            padding: const EdgeInsets.all(AriaTokens.s5),
            children: [
              Text(
                p.circleType.emoji,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 64),
              ),
              Text(
                p.circleName,
                textAlign: TextAlign.center,
                style: text.headlineSmall,
              ),
              const SizedBox(height: AriaTokens.s2),
              Text(
                tr('{0} invited you to join as {1}.', [
                  p.inviterName ?? tr('Someone'),
                  p.role.label.toLowerCase(),
                ]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AriaTokens.s2),
              Text(
                p.role.description,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.palette.muted),
              ),
              const SizedBox(height: AriaTokens.s5),
              if (problem != null)
                Text(
                  problem,
                  key: const Key('join-problem'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.palette.danger),
                )
              else
                FilledButton(
                  key: const Key('accept-invite'),
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          String? id;
                          final ok = await runCircleOp(context, ref, () async {
                            id = await ref
                                .read(circleApiProvider)
                                .acceptInvite(widget.token);
                            ref
                                .read(telemetryProvider)
                                .event(TelemetryEvent.inviteAccepted);
                          });
                          if (!mounted) return;
                          setState(() => _busy = false);
                          if (ok && id != null) {
                            ref
                                .read(appPrefsProvider.notifier)
                                .update(
                                  (x) => x.copyWith(
                                    activeCircleId: () => id,
                                    // Dependents start in the simple app.
                                    simpleMode:
                                        p.role == CircleRole.dependent ||
                                        x.simpleMode,
                                  ),
                                );
                            if (context.mounted) context.go('/circle');
                          }
                        },
                  child: Text(tr('Join {0}', [p.circleName])),
                ),
              TextButton(
                onPressed: () => context.go('/today'),
                child: Text(tr('Not now')),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Activity log for owners/admins.
class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({required this.circleId, super.key});
  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(tr('Activity log'))),
    body: FutureBuilder(
      future: ref
          .read(memberNamesProvider.future)
          .then(
            (names) =>
                ref.read(circleApiProvider).auditLog(circleId, names: names),
          ),
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorState(message: circleErrorMessage(snap.error!));
        }
        if (!snap.hasData) return const LoadingState();
        final entries = snap.data!;
        if (entries.isEmpty) {
          return EmptyState(emoji: '🗒️', title: tr('Nothing yet'));
        }
        return ListView(
          padding: const EdgeInsets.all(AriaTokens.s4),
          children: [
            for (final e in entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e.describe()),
                subtitle: Text(
                  MaterialLocalizations.of(context)
                      .formatMediumDate(e.at.toLocal()),
                ),
              ),
          ],
        );
      },
    ),
  );
}
