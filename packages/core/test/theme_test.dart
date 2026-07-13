import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildOledTheme is dark, true-black, and uses the accent', () {
    final theme = buildOledTheme(AppPalette.dawn);
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppPalette.trueBlack);
    expect(theme.colorScheme.primary, AppPalette.dawn);
    expect(theme.useMaterial3, isTrue);
    // The Nivaat accent produces a distinct primary.
    expect(buildOledTheme(AppPalette.wind).colorScheme.primary, AppPalette.wind);
  });
}
