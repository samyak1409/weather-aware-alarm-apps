import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `showWhenLocked` was added on 2026-08-02 so a cold-start ring would reach
/// the keyguard, and removed hours later: it applies to ANY launch while the
/// lockscreen is up, so tapping a notification there opened the whole app with
/// no PIN (device-confirmed). The ring never needed it — the `alarm` plugin
/// sets the same flag itself for exactly as long as an alarm sounds.
///
/// Nothing in Dart references these attributes, and re-adding one looks like a
/// harmless fix for a lock-screen ring, so this reads the manifest. Same file in
/// Arunoday: both manifests must stay clean, so both suites check their own.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');

  /// Comments stripped: the header above `<activity>` names both attributes to
  /// explain their absence, and must not read as their presence.
  String markup() => manifest
      .readAsStringSync()
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

  test('nothing in this app may show over the lock screen', () {
    // Whole manifest, not just MainActivity: an activity-alias inherits an
    // unset attribute from its target, so a stray one anywhere is the hole.
    expect(markup(), isNot(contains('showWhenLocked')),
        reason: 'a notification tap would then open the app without a PIN');
    expect(markup(), isNot(contains('turnScreenOn')),
        reason: 'only ever useful alongside showWhenLocked');
  });

  test('the full screen intent is permitted at all', () {
    expect(markup(), contains('android.permission.USE_FULL_SCREEN_INTENT'),
        reason: 'without it every ring is a notification, locked or not');
  });

  test('every launcher component declares the alarm RING action', () {
    // The plugin resolves RING with `queryIntentActivities(intent, 0)`, which
    // SKIPS disabled components — and picking an alternate app icon disables
    // MainActivity and enables an alias in its place (core/app_icon). So the
    // filter has to sit on all three launcher components, or the alarm-launch
    // signal silently stops working for anyone not on icon 1, and the app
    // starts staying on screen after a ring it opened.
    final launchers = RegExp(r'android.intent.category.LAUNCHER')
        .allMatches(markup())
        .length;
    expect(launchers, 3, reason: 'MainActivity + IconTwo + IconThree');
    expect(
      RegExp(r'com\.gdelataillade\.alarm\.action\.RING')
          .allMatches(markup())
          .length,
      launchers,
      reason: 'one RING filter per launcher component, no more and no fewer — '
          'two enabled at once makes the plugin pick arbitrarily',
    );
  });
}
