import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Android resolves this icon by NAME at runtime (core's
/// [kNotificationIconRes]), so nothing in Dart ties the two together. Lose the
/// drawable and the ring silently falls back to the launcher blob while
/// flutter_local_notifications rejects `initialize` with `invalid_icon`; lose
/// keep.xml and the resource shrinker drops it from RELEASE builds only.
/// Neither shows up in an ordinary test, so this one reads the files.
void main() {
  final drawable = File(
    'android/app/src/main/res/drawable/$kNotificationIconRes.xml',
  );
  final keep = File('android/app/src/main/res/raw/keep.xml');

  /// Comments stripped: the headers spell out what NOT to do (`@mipmap`,
  /// strokes), and a commented-out `pathData` must not count as a shape.
  String markup(File f) =>
      f.readAsStringSync().replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

  test('the drawable core names actually ships in this app', () {
    expect(drawable.existsSync(), isTrue,
        reason: 'core posts notifications with icon "$kNotificationIconRes"');
  });

  test('keep.xml pins the drawable against the resource shrinker', () {
    expect(keep.existsSync(), isTrue,
        reason: 'without it release builds drop drawable/$kNotificationIconRes');
    expect(keep.readAsStringSync(),
        contains('tools:keep="@drawable/$kNotificationIconRes"'));
  });

  test('it is a silhouette, not the launcher art', () {
    final xml = markup(drawable);
    // Alpha-masked, so an opaque full-canvas background renders as exactly the
    // white blob this replaced. No text check can PROVE transparent ground —
    // only a device can — but it bars the two ways in: pointing back at the
    // launcher art, and a rect behind the shape (every encoding of which
    // starts a subpath at the origin). Fills only: stroked feathers went wispy
    // at 18px and read as a trident.
    expect(xml, contains('<vector'));
    expect(xml, contains('android:viewportWidth="24"'));
    expect(xml, isNot(contains('@mipmap')));
    expect(xml, isNot(contains('<bitmap')));
    expect(xml, isNot(matches(RegExp(r'M\s*0[,\s]\s*0'))));
    expect(xml, contains('android:fillColor'));
    expect(xml, isNot(contains('android:strokeColor')));
  });

  test('the two apps do not share a silhouette', () {
    // The state this all started from was both apps showing one white ball.
    // These drawables are identical apart from their paths, so a copy-paste
    // between them is the realistic regression. Asserted in this suite only —
    // the fact is symmetric, so checking it from both sides is the same check.
    //
    // Compared as TOKENS: in path data commas and whitespace are
    // interchangeable separators and 12 / 12.0 / 1.2e1 are one number, so a
    // reformatted copy still counts as the same shape. Two genuinely different
    // paths that merely LOOK alike is tools/preview_notif_icons.py territory.
    final other = File(
      '../nivaat/android/app/src/main/res/drawable/$kNotificationIconRes.xml',
    );
    expect(other.existsSync(), isTrue, reason: 'sibling app moved or renamed');
    String canon(String d) => RegExp(r'[A-Za-z]|-?\d*\.?\d+(?:[eE][-+]?\d+)?')
        .allMatches(d)
        .map((t) => double.tryParse(t[0]!)?.toString() ?? t[0]!)
        .join(' ');
    List<String> paths(File f) => RegExp(r'android:pathData="([^"]+)"')
        .allMatches(markup(f))
        .map((m) => canon(m.group(1)!))
        .toList();
    expect(paths(drawable), isNot(equals(paths(other))));
  });
}
