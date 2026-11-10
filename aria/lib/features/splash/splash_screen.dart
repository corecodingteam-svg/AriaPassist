import 'package:aria/core/theme/aria_tokens.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';

/// Shown only for the instant between first frame and router redirect.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: t.primaryGradient,
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: t.palette.onPrimary,
                size: 40,
              ),
            ),
            const SizedBox(height: AriaTokens.s4),
            Text(tr('Aria'), style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
      ),
    );
  }
}
