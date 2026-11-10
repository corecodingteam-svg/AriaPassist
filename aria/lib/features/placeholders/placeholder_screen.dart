import 'package:aria/core/widgets/state_views.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';

/// Stand-in for screens built in later phases, so every route and deep
/// link already resolves.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    required this.title,
    required this.phase,
    this.emoji = '🚧',
    this.detail,
    super.key,
  });

  final String title;
  final int phase;
  final String emoji;
  final String? detail;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: EmptyState(
      emoji: emoji,
      title: title,
      message: [
        ?detail,
        tr('Coming in Phase {0}.', [phase]),
      ].join('\n'),
    ),
  );
}
