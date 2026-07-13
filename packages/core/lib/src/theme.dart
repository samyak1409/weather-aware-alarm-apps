import 'package:flutter/material.dart';

/// Pitch-black minimal theme shared by both apps. Dark-only by design.
class AppPalette {
  AppPalette._();

  /// Arunoday accent: first light of dawn.
  static const Color dawn = Color(0xFFFFB067);

  /// Nivaat accent: clear-sky blue (a calm, windless morning).
  static const Color wind = Color(0xFF6FB7EC);

  static const Color trueBlack = Color(0xFF000000);
  static const Color surface = Color(0xFF0E0E0E);
  static const Color hairline = Color(0xFF222222);
  static const Color textPrimary = Color(0xFFF2F2F2);
  static const Color textSecondary = Color(0xFF8A8A8A);
}

ThemeData buildOledTheme(Color accent) {
  final scheme = ColorScheme.dark(
    primary: accent,
    secondary: accent,
    surface: AppPalette.trueBlack,
    onSurface: AppPalette.textPrimary,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppPalette.trueBlack,
    canvasColor: AppPalette.trueBlack,
    dialogTheme: const DialogThemeData(backgroundColor: AppPalette.surface),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppPalette.surface,
      contentTextStyle: TextStyle(color: AppPalette.textPrimary),
      behavior: SnackBarBehavior.floating,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppPalette.surface,
      surfaceTintColor: Colors.transparent,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppPalette.trueBlack,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    dividerTheme: const DividerThemeData(
      color: AppPalette.hairline,
      thickness: 0.5,
      space: 0.5,
    ),
    scrollbarTheme: ScrollbarThemeData(
      // Dull grey, not the bright default white.
      thumbColor:
          WidgetStatePropertyAll(AppPalette.textSecondary.withValues(alpha: 0.4)),
      thickness: const WidgetStatePropertyAll(4),
      radius: const Radius.circular(4),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppPalette.textSecondary,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(accent),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? accent.withValues(alpha: 0.35)
            : AppPalette.hairline,
      ),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 64,
        fontWeight: FontWeight.w200,
        letterSpacing: -1.5,
        color: AppPalette.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w300,
        color: AppPalette.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppPalette.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppPalette.textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        letterSpacing: 1.2,
        color: AppPalette.textSecondary,
      ),
    ),
  );
}
