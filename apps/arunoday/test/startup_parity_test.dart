import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Core's persisted app-wide switches are loaded by each app's `main()`, and
/// nothing in Dart makes that happen — core declares a `ValueNotifier` with a
/// default, each app decides whether to fill it from disk before `runApp`.
///
/// Forget the call and there is no error anywhere: the notifier keeps its
/// default, so the switch reads OFF and silently resets on every launch —
/// `Appearance` loses the type choice, `DevMode` makes the seven-tap gate
/// something you redo each time. Both are shared, so a miss in ONE app is the
/// parity break that matters.
///
/// Lives in Arunoday alone; it reads both mains, the same way
/// `channel_parity_test` reads both MainActivities.
void main() {
  final mains = {
    'arunoday': File('lib/main.dart'),
    'nivaat': File('../nivaat/lib/main.dart'),
  };

  /// Comment LINES dropped first, so prose naming a loader can't stand in for
  /// calling it. Whole lines only: a mid-line `//` is a URL.
  String code(File f) =>
      f.readAsStringSync().replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

  for (final entry in mains.entries) {
    test('${entry.key} loads every shared switch before runApp', () {
      expect(entry.value.existsSync(), isTrue);
      final source = code(entry.value);
      final beforeRunApp = source.split('runApp(').first;

      for (final loader in ['Appearance.load()', 'DevMode.load()']) {
        // `await X` implies X, so one assertion covers both failures: missing
        // entirely, and called without awaiting.
        expect(beforeRunApp, contains('await $loader'),
            reason: 'missing, the switch reads as its default and quietly '
                'resets every launch; unawaited, the first frame draws '
                'against that default and changes under the user');
      }
    });
  }
}
