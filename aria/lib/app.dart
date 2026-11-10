import 'package:aria/core/router/app_router.dart';
import 'package:aria/core/theme/app_theme.dart';
import 'package:aria/core/theme/theme_controller.dart';
import 'package:aria/core/theme/theme_settings.dart';
import 'package:aria/data/providers.dart';
import 'package:aria/features/account/application/app_lock.dart';
import 'package:aria/features/circles/circle_providers.dart';
import 'package:aria/features/lists/organize_providers.dart';
import 'package:aria/features/places/application/places_providers.dart';
import 'package:aria/features/preferences/application/prefs_providers.dart';
import 'package:aria/features/preferences/application/prefs_scope.dart';
import 'package:aria/features/preferences/application/settings_sync.dart';
import 'package:aria/features/preferences/domain/app_prefs.dart';
import 'package:aria/features/reminders/application/reminder_providers.dart';
import 'package:aria/features/subscription/application/subscription_providers.dart';
import 'package:aria/features/widgets/home_widgets.dart';
import 'package:aria/l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class AriaApp extends ConsumerWidget {
  const AriaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeControllerProvider);
    final router = ref.watch(routerProvider);
    final prefs = ref.watch(appPrefsProvider);
    // Keep the sync engine and reminder scheduler alive while signed in.
    ref
      ..watch(syncEngineProvider)
      ..watch(reminderServiceProvider)
      // Kept resolved app-wide: saving a reminder needs it instantly, and
      // Riverpod pauses providers nobody listens to.
      ..watch(activeCircleIdProvider)
      ..watch(settingsSyncProvider)
      ..watch(homeWidgetSyncProvider)
      ..watch(realtimeSyncProvider)
      ..watch(storeBillingProvider)
      ..watch(downgradeGuardProvider)
      ..watch(ownerBillingWatchProvider)
      ..watch(telemetryConsentProvider)
      ..watch(geofenceSyncProvider);

    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    // UI language: the setting, or the phone's language for "system".
    final lang = L10n.resolve(
      prefs.appLanguage.name,
      WidgetsBinding.instance.platformDispatcher.locale,
    );
    if (lang != L10n.lang) {
      final first = L10n.lang == 'en' && lang == 'en';
      L10n.lang = lang;
      Intl.defaultLocale = lang == 'hi' ? 'hi_IN' : 'en_US';
      // Rebuild already-built screens in place (navigation is kept).
      if (!first) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) rebuildAll(context);
        });
      }
    }

    return MaterialApp.router(
      locale: Locale(lang, 'IN'),
      supportedLocales: L10n.supported,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      title: tr('Aria'),
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: settings.mode,
      theme: AppTheme.build(
        settings,
        Brightness.light,
        platformDisablesAnimations: disableAnimations,
      ),
      darkTheme: AppTheme.build(
        settings,
        Brightness.dark,
        platformDisablesAnimations: disableAnimations,
      ),
      themeAnimationDuration: settings.reduceMotion || disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 200),
      // App text size multiplies the system scale (respects OS settings);
      // Simple Mode forces extra-large text. The 12/24 h choice overrides
      // the OS when set.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final factor = ref.watch(simpleModeProvider)
            ? FontSizeOption.xl.factor
            : settings.fontSize.factor;
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(mq.textScaler.scale(1) * factor),
            alwaysUse24HourFormat: switch (prefs.timeFormat) {
              TimeFormat.system => mq.alwaysUse24HourFormat,
              TimeFormat.h12 => false,
              TimeFormat.h24 => true,
            },
          ),
          child: PrefsScope(
            prefs: prefs,
            child: AppLockGate(child: child!),
          ),
        );
      },
    );
  }
}
