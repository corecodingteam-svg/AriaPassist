import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';

/// Shared empty / loading / error / offline states used by every screen.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.emoji,
    required this.title,
    this.message,
    this.action,
    super.key,
  });

  final String emoji;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Scrolls rather than overflowing at very large text sizes.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AriaTokens.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Text(emoji, style: const TextStyle(fontSize: 56)),
            ),
            const SizedBox(height: AriaTokens.s4),
            Text(title, style: text.titleLarge, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: AriaTokens.s2),
              Text(
                message!,
                style: text.bodyMedium?.copyWith(color: context.palette.muted),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AriaTokens.s5),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class LoadingState extends StatelessWidget {
  const LoadingState({this.label = 'Loading', super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      label: tr(label),
      child: const CircularProgressIndicator(),
    ),
  );
}

class ErrorState extends StatelessWidget {
  const ErrorState({required this.message, this.onRetry, super.key});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    emoji: '😕',
    title: tr('Something went wrong'),
    message: message,
    action: onRetry == null
        ? null
        : FilledButton(onPressed: onRetry, child: Text(tr('Try again'))),
  );
}

/// Slim banner shown above content when the device is offline. Content keeps
/// working from the local DB — this only sets expectations about sync.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: p.warning,
        padding: const EdgeInsets.symmetric(
          horizontal: AriaTokens.s4,
          vertical: AriaTokens.s2,
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 18, color: p.onWarning),
            const SizedBox(width: AriaTokens.s2),
            Expanded(
              child: Text(
                tr(
                  "You're offline — reminders still work. Changes will sync later.",
                ),
                style: TextStyle(
                  color: p.onWarning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
