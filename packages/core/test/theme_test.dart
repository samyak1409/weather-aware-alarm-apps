import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildOledTheme is dark, true-black scaffolds, and uses the accent', () {
    final theme = buildOledTheme(AppPalette.dawn);
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppPalette.trueBlack);
    expect(theme.appBarTheme.backgroundColor, AppPalette.trueBlack);
    // colorScheme.surface is the scaffold role (true-black), not the elevated
    // gray [AppPalette.surface] — easy to confuse by name alone.
    expect(theme.colorScheme.surface, AppPalette.trueBlack);
    expect(theme.colorScheme.primary, AppPalette.dawn);
    expect(theme.useMaterial3, isTrue);
    // The Nivaat accent produces a distinct primary.
    expect(buildOledTheme(AppPalette.wind).colorScheme.primary, AppPalette.wind);
  });

  test('elevated overlays share AppPalette.surface (not a true-black hole)', () {
    // Sheets / dialogs / snackbars / DropdownButton menus (via canvasColor —
    // Flutter paints open menus with `dropdownColor ?? theme.canvasColor`).
    final theme = buildOledTheme(AppPalette.wind);
    expect(theme.canvasColor, AppPalette.surface);
    expect(theme.dialogTheme.backgroundColor, AppPalette.surface);
    expect(theme.bottomSheetTheme.backgroundColor, AppPalette.surface);
    expect(theme.snackBarTheme.backgroundColor, AppPalette.surface);
    // Home scaffolds stay pure black — only the elevated family is gray.
    expect(theme.scaffoldBackgroundColor, AppPalette.trueBlack);
    expect(theme.canvasColor, isNot(AppPalette.trueBlack));
    // No accent wash on elevated fills.
    expect(theme.colorScheme.surfaceTint, Colors.transparent);
    expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
    expect(theme.bottomSheetTheme.surfaceTintColor, Colors.transparent);
  });

  test('showTimePicker path matches elevated gray (ignores dialogTheme)', () {
    // SDK: time picker reads TimePickerTheme + ColorScheme.surfaceContainer*,
    // not DialogTheme — without these pins it renders true-black.
    final theme = buildOledTheme(AppPalette.dawn);
    expect(theme.timePickerTheme.backgroundColor, AppPalette.surface);
    expect(theme.timePickerTheme.dialBackgroundColor, AppPalette.surface);
    final scheme = theme.colorScheme;
    expect(scheme.surfaceContainerLowest, AppPalette.surface);
    expect(scheme.surfaceContainerLow, AppPalette.surface);
    expect(scheme.surfaceContainer, AppPalette.surface);
    expect(scheme.surfaceContainerHigh, AppPalette.surface);
    expect(scheme.surfaceContainerHighest, AppPalette.surface);
    // Dual-surface contract: scaffold role stays black; containers are gray.
    expect(scheme.surface, AppPalette.trueBlack);
    expect(scheme.surfaceContainerHigh, isNot(scheme.surface));
  });
}
