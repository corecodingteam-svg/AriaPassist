import 'package:flutter/material.dart';

/// The Neon admin look: a dark slate sidebar, a light grey page with white bordered panels, squared corners, solid
/// colour stat tiles and Noto Sans. Dark mode is Neon's Black skin.
abstract final class Neon {
  static const sidebar = Color(0xFF303641);
  static const sidebarActive = Color(0xFF373E4A);
  static const sidebarText = Color(0xFFAAABAE);
  static const accent = Color(0xFF21A9E1);

  static const page = Color(0xFFF3F3F3);
  static const panel = Color(0xFFFFFFFF);
  static const border = Color(0xFFEBEBEB);
  static const text = Color(0xFF2B303A);
  static const muted = Color(0xFF5F6570);

  static const darkSidebar = Color(0xFF222222);
  static const darkSidebarActive = Color(0xFF2E2E2E);
  static const darkPage = Color(0xFF1A1E24);
  static const darkPanel = Color(0xFF262B33);
  static const darkBorder = Color(0xFF353B45);
  static const darkText = Color(0xFFECEEF1);
  static const darkMuted = Color(0xFFA8ADB5);

  /// Stat tiles: Neon's tile hues, deep enough for their white numbers and labels to keep AA contrast.
  static const tiles = [
    Color(0xFF0073B7), // blue
    Color(0xFF007338), // green
    Color(0xFF7B3F97), // purple
    Color(0xFF00796B), // teal
    Color(0xFFB85C00), // orange
    Color(0xFFCC2424), // red
  ];

  static const radius = 3.0;
  static const font = 'NotoSans';
}

ThemeData neonTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final page = dark ? Neon.darkPage : Neon.page;
  final panel = dark ? Neon.darkPanel : Neon.panel;
  final border = dark ? Neon.darkBorder : Neon.border;
  final text = dark ? Neon.darkText : Neon.text;
  final muted = dark ? Neon.darkMuted : Neon.muted;
  final sidebar = dark ? Neon.darkSidebar : Neon.sidebar;
  final sidebarActive = dark ? Neon.darkSidebarActive : Neon.sidebarActive;
  final primary = dark ? const Color(0xFF5CC0EA) : Neon.sidebar;
  final squared = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Neon.radius));
  final scheme = ColorScheme(
    brightness: b,
    primary: primary,
    onPrimary: dark ? Neon.darkPage : Colors.white,
    secondary: Neon.accent,
    onSecondary: Neon.text,
    primaryContainer: Color.alphaBlend(primary.withValues(alpha: 0.14), panel),
    onPrimaryContainer: text,
    secondaryContainer: Color.alphaBlend(Neon.accent.withValues(alpha: 0.16), panel),
    onSecondaryContainer: text,
    error: const Color(0xFFCC2424),
    onError: Colors.white,
    errorContainer: dark ? const Color(0xFF4A1C1C) : const Color(0xFFFBE3E3),
    onErrorContainer: text,
    surface: panel,
    onSurface: text,
    onSurfaceVariant: muted,
    surfaceContainerLowest: page,
    surfaceContainerLow: page,
    surfaceContainer: panel,
    surfaceContainerHigh: panel,
    surfaceContainerHighest: panel,
    outline: muted,
    outlineVariant: border,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b, fontFamily: Neon.font);
  return base.copyWith(
    scaffoldBackgroundColor: page,
    appBarTheme: AppBarTheme(
      backgroundColor: panel,
      foregroundColor: text,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: border)),
    ),
    cardTheme: CardThemeData(
      color: panel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Neon.radius), side: BorderSide(color: border)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: sidebar,
      indicatorColor: sidebarActive,
      indicatorShape: squared,
      selectedIconTheme: const IconThemeData(color: Colors.white),
      unselectedIconTheme: const IconThemeData(color: Neon.sidebarText),
      selectedLabelTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFamily: Neon.font),
      unselectedLabelTextStyle: const TextStyle(color: Neon.sidebarText, fontFamily: Neon.font),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: sidebar, shape: const RoundedRectangleBorder()),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: squared)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: squared, side: BorderSide(color: border))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: squared)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: panel,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Neon.radius), borderSide: BorderSide(color: border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Neon.radius), borderSide: BorderSide(color: border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Neon.radius), borderSide: BorderSide(color: primary, width: 1.5)),
    ),
    chipTheme: base.chipTheme.copyWith(shape: squared, side: BorderSide(color: border), backgroundColor: panel),
    dialogTheme: DialogThemeData(backgroundColor: panel, shape: squared),
    dividerTheme: DividerThemeData(color: border, space: 1),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(page),
      headingTextStyle: TextStyle(fontWeight: FontWeight.w700, color: muted, fontFamily: Neon.font),
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: squared),
  );
}
