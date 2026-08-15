import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **The same component must be spaced the same in both apps** (2026-08-15,
/// Samyak, on a device: "check spacing for similar components, same or not").
///
/// Every claim here is about two apps at once, which is the kind no widget
/// test can make — each app's tests can only see its own screens, and that
/// blind spot is how three spacings drifted: one settings section break was
/// 4pt tighter than its siblings, the home top bar had 8pt under it in one app
/// and none in the other, and the shared home banners were given `top: 16,
/// bottom: 4` in one app against the component's own `bottom: 12`.
///
/// **The settings half of that is gone from here, and that is the point.** Its
/// furniture moved into core's `SettingsPage` / `SettingsSection`, so there is
/// one copy of the gutter, the `4 / rule / 8` break and the empty-section pad —
/// drift is unrepresentable rather than merely detected. What is left below is
/// the check that both pages still USE that furniture, plus the home screens,
/// which are genuinely separate widgets and have to be compared by reading.
///
/// Reads Nivaat off disk from Arunoday, the same way `channel_parity_test`
/// reads both MainActivities and `startup_parity_test` reads both mains.
void main() {
  /// Comment lines dropped first, so prose quoting a number cannot stand in
  /// for the code using it. Whole lines only: a mid-line `//` is a URL.
  String code(String path) => File(path)
      .readAsStringSync()
      .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

  /// Collapses runs of whitespace so a matcher can be written the way the code
  /// reads rather than the way `dart format` happened to wrap it.
  String flat(String source) => source.replaceAll(RegExp(r'\s+'), ' ');

  final settings = {
    'arunoday': 'lib/src/settings_sheet.dart',
    'nivaat': '../nivaat/lib/src/settings_sheet.dart',
  };
  final homes = {
    'arunoday': 'lib/src/home_screen.dart',
    'nivaat': '../nivaat/lib/src/home_screen.dart',
  };

  group('settings page', () {
    for (final entry in settings.entries) {
      test('${entry.key} is built from the shared furniture', () {
        final source = flat(code(entry.value));
        expect(source, contains('SettingsPage('),
            reason: 'the shell carries the gutter, the one scroll surface and '
                'the pinned mark');
        expect(source, contains('SettingsSection('),
            reason: 'the section break and its heading');
        // Re-inlining is the drift this replaced, and it would otherwise be
        // silent: a page that spells the furniture out again still renders
        // correctly on the day it is written.
        for (final inlined in const [
          'EdgeInsets.fromLTRB(20, 8, 20, 24)',
          'const Divider()',
          'EdgeInsets.symmetric(vertical: 16)',
        ]) {
          expect(source, isNot(contains(inlined)),
              reason: '`$inlined` belongs to core now — spelling it here again '
                  'is how the two pages come apart');
        }
      });
    }
  });

  group('home screen', () {
    for (final entry in homes.entries) {
      test('${entry.key} puts 8pt under the top bar', () {
        // **Anchored to the top bar itself**, not to the number appearing
        // anywhere in the file — a bare `contains` would be satisfied by any
        // unrelated widget that happens to pad 8. Arunoday's column is already
        // inset 28 so it pads only the bottom; Nivaat's children inset
        // themselves. Different expressions, one number, so the padding is
        // captured and only its tail asserted.
        final label = entry.key == 'arunoday' ? 'ARUNODAY' : 'NIVAAT';
        final bar = RegExp("Padding\\( padding: const (EdgeInsets\\.[^;]*?), "
                "child: Row\\( children: \\[ Text\\('$label'")
            .firstMatch(flat(code(entry.value)));
        expect(bar, isNotNull,
            reason: 'could not find the $label top bar — if its shape changed, '
                'this test is no longer looking at anything');
        expect(bar!.group(1), endsWith('8)'),
            reason: 'the gap between the app label and whatever follows it');
      });

      test('${entry.key} gives every home banner a 12pt bottom margin', () {
        // Only the app that OVERRIDES the shared default has margins to check
        // here; the other relies on `NudgeBanner`'s own, which the test below
        // pins. Both halves are needed — this loop alone was silently vacuous
        // for Nivaat, which passes no margin at all, so a two-app claim was
        // being made while only one app was examined.
        final margins = RegExp(r'margin:\s*(?:const\s*)?(EdgeInsets\.[^,)]*(?:\([^)]*\))?)')
            .allMatches(flat(code(entry.value)))
            .map((m) => m.group(1)!)
            .toList();
        expect(margins, entry.key == 'arunoday' ? isNotEmpty : isEmpty,
            reason: entry.key == 'arunoday'
                ? 'this column is pre-inset, so it must pass its own margins — '
                    'with none, the assertion below checks nothing'
                : 'these banners are supposed to take the shared default; an '
                    'override here means the rhythm now lives in two places');
        for (final margin in margins) {
          expect(margin, contains('bottom: 12'),
              reason: 'banner margin $margin breaks the rhythm');
        }
      });
    }
  });

  group('the shared banner default', () {
    // Nivaat's home passes no margin, so its 12pt comes from here rather than
    // from its own source — assert the default itself, or that app's rhythm is
    // pinned by nothing at all.
    const banners = {
      'nudge_banner': '../../packages/core/lib/src/nudge_banner.dart',
      'alarm_permission_banner':
          '../../packages/core/lib/src/alarm_permission_banner.dart',
      'notification_permission_banner':
          '../../packages/core/lib/src/notification_permission_banner.dart',
      'background_banner': '../nivaat/lib/src/background_banner.dart',
    };
    for (final entry in banners.entries) {
      test('${entry.key} defaults to the 28/12 inset', () {
        expect(flat(code(entry.value)),
            contains('const EdgeInsets.fromLTRB(28, 0, 28, 12)'),
            reason: 'the default every un-overridden banner takes');
      });
    }
  });
}
