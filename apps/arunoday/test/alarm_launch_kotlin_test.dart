import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The alarm-launch token lives entirely in Kotlin — set from an `ACTION_RING`
/// intent, read once by core's `consumeAlarmLaunch`, and cleared. Nothing in
/// Dart references any of it and only a device can exercise it, so the rules it
/// has to obey are checked by reading `MainActivity.kt`.
///
/// Both apps are asserted BYTE-IDENTICAL first, which is what lets everything
/// below check one file and cover both. Lives in Arunoday alone; it reads both,
/// like `channel_parity_test`.
void main() {
  final files = {
    'arunoday':
        File('android/app/src/main/kotlin/com/samyak/arunoday/MainActivity.kt'),
    'nivaat': File(
        '../nivaat/android/app/src/main/kotlin/com/samyak/nivaat/MainActivity.kt'),
  };

  /// Comment lines dropped first, so prose describing a rule can't stand in for
  /// implementing it.
  String code(File f) =>
      f.readAsStringSync().replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

  /// Everything from the token field to the next unrelated member.
  String launchPart(File f) {
    final s = code(f);
    final start = s.indexOf('private var alarmLaunchId');
    final end = s.indexOf('private fun iconComponents');
    expect(start, isNot(-1), reason: '${f.path} has no launch token');
    expect(end, greaterThan(start));
    return s.substring(start, end);
  }

  /// The body of a named override, so a statement can be attributed to the
  /// lifecycle callback it actually sits in.
  String bodyOf(String source, String signature) {
    final start = source.indexOf(signature);
    expect(start, isNot(-1), reason: '$signature is missing');
    var depth = 0;
    for (var i = source.indexOf('{', start); i < source.length; i++) {
      if (source[i] == '{') depth++;
      if (source[i] == '}' && --depth == 0) return source.substring(start, i);
    }
    fail('$signature is never closed');
  }

  test('both apps implement it identically', () {
    // Two copies of one mechanism, and only one gets read when something goes
    // wrong. Divergence here is a bug in whichever app you are not looking at —
    // and it is also what makes the single-file checks below sufficient.
    expect(launchPart(files['arunoday']!), launchPart(files['nivaat']!));
  });

  group('the launch token', () {
    final source = code(files['nivaat']!);

    test('dies when the app leaves the screen', () {
      // Recents delivers NO intent, so anything that clears on an incoming one
      // never runs on the way back. Without a clear in onStop the token
      // outlives its ring, and the NEXT ring's stop hides an app the user
      // opened themselves (device review, 2026-08-05).
      expect(bodyOf(source, 'override fun onStop()'),
          contains('alarmLaunchId = null'),
          reason: 'onStop is the one path every return route passes through');
    });

    test('is only taken from the alarm, and only while off screen', () {
      final body = bodyOf(source, 'private fun handleAlarmIntent');
      expect(body, contains('if (visible) return'),
          reason: 'an ACTION_RING arriving while we are already on screen means '
              'the user got here first — hiding on stop would then cost them '
              'the screen they chose');
      expect(body, contains('AlarmService.ACTION_RING'),
          reason: 'the action is what separates an alarm launch from a launcher '
              'tap; extras alone would not');
    });

    test('tracks visibility across onStart/onStop, not resume/pause', () {
      // A system dialog over the activity pauses it without hiding it, and
      // treating that as "not visible" would read the next alarm as having
      // opened the app.
      expect(source, isNot(contains('override fun onResume()')),
          reason: 'onResume would fire for a dialog dismissal too');
      expect(bodyOf(source, 'override fun onStart()'), contains('visible = true'));
      expect(bodyOf(source, 'override fun onStop()'), contains('visible = false'));
    });
  });
}
