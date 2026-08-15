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

ThemeData buildOledTheme(Color accent, {bool heavyType = false}) {
  final scheme = ColorScheme.dark(
    primary: accent,
    secondary: accent,
    // Home / scaffold role — OLED black. Distinct from [AppPalette.surface]
    // (elevated gray). Naming collision is Flutter's; keep both intentional.
    surface: AppPalette.trueBlack,
    onSurface: AppPalette.textPrimary,
    // No M3 elevation tint wash (would stain gray sheets with the accent).
    surfaceTint: Colors.transparent,
    // Elevated M3 tones (time-picker dial/chips, etc.). Unset, these fall
    // back to colorScheme.surface (= true-black) and punch holes in gray
    // sheets/dialogs — same gap showTimePicker had vs dialogTheme.
    surfaceContainerLowest: AppPalette.surface,
    surfaceContainerLow: AppPalette.surface,
    surfaceContainer: AppPalette.surface,
    surfaceContainerHigh: AppPalette.surface,
    surfaceContainerHighest: AppPalette.surface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppPalette.trueBlack,
    // Elevated overlays share [AppPalette.surface]: sheets / dialogs /
    // snackbars (explicit themes below) and DropdownButton menus (Flutter
    // paints them with `dropdownColor ?? theme.canvasColor`).
    canvasColor: AppPalette.surface,
    dialogTheme: const DialogThemeData(
      backgroundColor: AppPalette.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppPalette.surface,
      contentTextStyle: TextStyle(color: AppPalette.textPrimary),
      behavior: SnackBarBehavior.floating,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppPalette.surface,
      surfaceTintColor: Colors.transparent,
    ),
    // Tooltips are an elevated overlay too, and were the one that got missed
    // (2026-08-15, Samyak — the ⓘ's long-press label was the first tooltip
    // either app rendered). Material's default paints a light box with dark
    // text in a dark theme, which is the only pale rectangle in either app.
    // Same grey and same text colour as every other overlay here.
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      textStyle: TextStyle(color: AppPalette.textPrimary, fontSize: 12),
    ),
    // showTimePicker ignores dialogTheme (SDK) — pin it to the same elevated
    // gray as sheets/dialogs.
    timePickerTheme: const TimePickerThemeData(
      backgroundColor: AppPalette.surface,
      dialBackgroundColor: AppPalette.surface,
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
    // [heavyType] (2026-07-20, Samyak, settings toggle "Bold clocks &
    // titles" — the SETTING ships ON since 2026-08-13, see `Appearance`; this
    // parameter still defaults to the thin look, which is what a caller that
    // passes nothing — i.e. a test — is asking for): the premium look = bold
    // display text against quiet w400
    // body/labels, so only the CLOCK styles gain weight; everything else
    // stays untouched in both modes. Heavy mode also uses tabular figures so
    // the ticking clocks don't shift width per minute (SF Pro's default
    // digits are proportional). OFF must stay EXACTLY the original thin look.
    //
    // A third size since 2026-08-13: `displayMedium` (40) is the list and
    // second-clock size — Nivaat's alarm rows and Arunoday's bedtime, both of
    // which were 28 and read as captions beside the hero (Samyak, inspired by
    // iOS's own alarm list). Both intros went the other way, to `displayLarge`.
    // It follows `headlineMedium`'s weights rather than `displayLarge`'s: at
    // 40px w200 is too fine to read at a glance in a list.
    textTheme: TextTheme(
      displayLarge: heavyType
          ? const TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.w700,
              letterSpacing: -2.0,
              fontFeatures: [FontFeature.tabularFigures()],
              color: AppPalette.textPrimary,
            )
          : const TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.w200,
              letterSpacing: -1.5,
              color: AppPalette.textPrimary,
            ),
      displayMedium: heavyType
          ? const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w600,
              letterSpacing: -1.0,
              fontFeatures: [FontFeature.tabularFigures()],
              color: AppPalette.textPrimary,
            )
          : const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w300,
              letterSpacing: -0.5,
              color: AppPalette.textPrimary,
            ),
      headlineMedium: heavyType
          ? const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              fontFeatures: [FontFeature.tabularFigures()],
              color: AppPalette.textPrimary,
            )
          : const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w300,
              color: AppPalette.textPrimary,
            ),
      // The ring screen's STOP, and the only label outside the home screens
      // that answers to "Bold clocks & titles" (2026-08-13). It lives here
      // rather than in `RingScreen` so the switch reaches it the way it
      // reaches the clocks — through the theme — instead of a shared widget
      // reading the global notifier for itself.
      //
      // 20: a button label a step above Material's default 14, which is what
      // it was until today. 22, 28 and 40 were all tried on a real phone and
      // all read as a headline sitting in a button (Samyak).
      //
      // **No colour, deliberately.** It is a BUTTON label: the FilledButton
      // supplies the foreground (black on the accent), and naming a colour
      // here overrode it and turned STOP white on blue — device-caught the
      // day this style was added.
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: heavyType ? FontWeight.w700 : FontWeight.w500,
      ),
      titleMedium: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppPalette.textPrimary,
      ),
      bodyMedium: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppPalette.textSecondary,
      ),
      labelSmall: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        letterSpacing: 1.2,
        color: AppPalette.textSecondary,
      ),
    ),
  );
}
