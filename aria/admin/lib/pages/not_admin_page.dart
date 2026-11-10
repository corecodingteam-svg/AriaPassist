import 'dart:async';

import 'package:aria_admin/core/providers.dart';
import 'package:aria_admin/pages/sign_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotAdminPage extends ConsumerWidget {
  const NotAdminPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => authCard(
    title: 'No admin access',
    subtitle: 'This account isn’t an Aria admin. Ask a super-admin to add you.',
    children: [
      FilledButton(
        onPressed: () => unawaited(ref.read(adminAuthProvider).signOut()),
        child: const Text('Sign out'),
      ),
    ],
  );
}
