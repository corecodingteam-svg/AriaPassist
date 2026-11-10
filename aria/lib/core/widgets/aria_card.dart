import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';

class AriaCard extends StatelessWidget {
  const AriaCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AriaTokens.s4),
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// Top-right avatar on every main screen; opens Me.
class ProfileAvatarButton extends StatelessWidget {
  const ProfileAvatarButton({required this.onPressed, super.key});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(right: AriaTokens.s2),
      child: IconButton(
        tooltip: tr('Profile and settings'),
        onPressed: onPressed,
        icon: CircleAvatar(
          radius: 18,
          backgroundColor: p.primary.withValues(alpha: 0.15),
          child: Icon(Icons.person_rounded, color: p.primary),
        ),
      ),
    );
  }
}
