import 'package:aria_admin/core/env.dart';
import 'package:aria_admin/core/providers.dart';
import 'package:aria_admin/core/router.dart';
import 'package:aria_admin/data/admin_api.dart';
import 'package:aria_admin/data/admin_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Env.configured) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Run with --dart-define-from-file=../env/dev.json'),
          ),
        ),
      ),
    );
    return;
  }
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
  );
  final db = Supabase.instance.client;
  runApp(
    ProviderScope(
      overrides: [
        adminAuthProvider.overrideWithValue(SupabaseAdminAuth(db)),
        adminApiProvider.overrideWithValue(SupabaseAdminApi(db)),
      ],
      child: const AdminApp(),
    ),
  );
}

ThemeData adminTheme(Brightness b) => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF7848FF),
    brightness: b,
  ),
  cardTheme: const CardThemeData(margin: EdgeInsets.zero),
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
  ),
);

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Aria Admin',
    debugShowCheckedModeBanner: false,
    theme: adminTheme(Brightness.light),
    darkTheme: adminTheme(Brightness.dark),
    routerConfig: ref.watch(routerProvider),
  );
}
