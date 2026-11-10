import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SettingsGroup {
  const SettingsGroup(
    this.id,
    this.emoji,
    this._title,
    this._subtitle,
    this.phase,
  );
  final String id;
  final String emoji;
  final String _title;
  String get title => tr(_title);
  final String _subtitle;
  String get subtitle => tr(_subtitle);

  /// Phase the group's screen is built in (Appearance is live now).
  final int phase;
}

/// Section 6 groups. Each opens /settings/:id.
const kSettingsGroups = <SettingsGroup>[
  SettingsGroup(
    'voice',
    '🗣️',
    'Voice & personality',
    'Choose and preview Aria’s voice',
    3,
  ),
  SettingsGroup(
    'reminder-style',
    '🔔',
    'Reminder style',
    'Voice, text, both, vibrate or silent',
    4,
  ),
  SettingsGroup(
    'appearance',
    '🎨',
    'Appearance & theme',
    'Colours, dark mode, text size',
    1,
  ),
  SettingsGroup(
    'simplify',
    '✨',
    'Simplify the app',
    'Simple Mode, defaults, gestures',
    4,
  ),
  SettingsGroup(
    'routines',
    '🌅',
    'Routines & briefings',
    'Morning briefing, night wrap-up',
    4,
  ),
  SettingsGroup(
    'quiet-hours',
    '🌙',
    'Quiet hours & focus',
    'When Aria stays quiet',
    4,
  ),
  SettingsGroup('circle', '👪', 'Circle', 'Family or team members', 6),
  SettingsGroup(
    'places',
    '📍',
    'Places',
    'Home, work — for “remind me when I get home”',
    8,
  ),
  SettingsGroup(
    'connected-apps',
    '🔗',
    'Connected apps',
    'Calendar, contacts, WhatsApp',
    8,
  ),
  SettingsGroup(
    'privacy',
    '🔒',
    'Privacy & security',
    'App lock, export, delete account',
    4,
  ),
  SettingsGroup(
    'subscription',
    '⭐',
    'Subscription & account',
    'Plan, billing, restore',
    7,
  ),
  SettingsGroup(
    'help',
    '❓',
    'Help & about',
    'FAQ, “Reminders not ringing?”',
    4,
  ),
];

/// Individual settings, so search finds "snooze" or "dark mode" directly.
const kSettingsKeywords = <String, List<String>>{
  'voice': [
    'voice',
    'speed',
    'pitch',
    'personality',
    'language',
    'hindi',
    'hinglish',
    'rename',
    'name',
    'spoken confirmations',
    'silent',
    'wake phrase',
    'meera',
    'arjun',
  ],
  'reminder-style': [
    'notification',
    'text only',
    'vibrate',
    'silent',
    'category',
    'follow-up',
    'nudge',
    'full-screen',
    'urgent',
    'summary',
    'auto-fallback',
    'driving',
    'meeting',
  ],
  'appearance': [
    'theme',
    'dark mode',
    'light',
    'colour',
    'color',
    'font',
    'text size',
    'high contrast',
    'reduce motion',
  ],
  'simplify': [
    'simple mode',
    'elderly',
    'default time',
    'morning',
    'snooze',
    'category',
    'priority',
    'quick actions',
    'swipe',
    'gesture',
    'one-handed',
    'confirm delete',
    'undo',
    'haptics',
    'sounds',
    'suggestions',
    'week starts',
    '24 hour',
    'time format',
    'date format',
    'reset',
    'tips',
  ],
  'routines': ['morning briefing', 'night wrap-up', 'routine', 'briefing time'],
  'quiet-hours': [
    'quiet hours',
    'night',
    'do not disturb',
    'focus',
    'calendar',
    'driving',
  ],
  'circle': ['family', 'team', 'members', 'invite', 'share'],
  'connected-apps': ['calendar', 'whatsapp', 'email', 'contacts', 'birthdays'],
  'privacy': [
    'privacy',
    'app lock',
    'fingerprint',
    'face',
    'pin',
    'lock screen',
    'hide',
    'export',
    'delete account',
    'recordings',
    'data',
  ],
  'subscription': [
    'plan',
    'premium',
    'billing',
    'restore',
    'upgrade',
    'cancel subscription',
  ],
  'help': [
    'faq',
    'not ringing',
    'troubleshoot',
    'support',
    'contact',
    'rate',
    'version',
    'battery',
  ],
};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final groups = kSettingsGroups
        .where(
          (g) =>
              q.isEmpty ||
              g.title.toLowerCase().contains(q) ||
              g.subtitle.toLowerCase().contains(q) ||
              (kSettingsKeywords[g.id] ?? const []).any((k) => k.contains(q)),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(tr('Settings'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AriaTokens.s2),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AriaTokens.s4,
              vertical: AriaTokens.s2,
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: tr('Search settings'),
                prefixIcon: const Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          for (final g in groups)
            ListTile(
              minTileHeight: AriaTokens.minTap + 12,
              leading: ExcludeSemantics(
                child: Text(g.emoji, style: const TextStyle(fontSize: 24)),
              ),
              title: Text(g.title),
              subtitle: Text(g.subtitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(switch (g.id) {
                'circle' => '/circle',
                'subscription' => '/subscription',
                final id => '/settings/$id',
              }),
            ),
        ],
      ),
    );
  }
}
