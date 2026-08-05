import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every `core/*` MethodChannel has to be answered by BOTH MainActivities, and
/// nothing in Dart enforces it: core declares the names, each app implements
/// them in Kotlin, and the two sides never meet at compile time.
///
/// A miss is silent by design. Core swallows `MissingPluginException` so a ring
/// or a nudge can't die on a missing handler — which means an unanswered
/// channel, or one whose `when` falls through to `notImplemented()`, is a
/// feature that quietly stops happening on one app. So this checks the whole
/// map: for each channel core declares, the methods core invokes on THAT
/// channel must be handled under THAT channel, in both Kotlins. Everything is
/// derived from core's own source. Lives in Arunoday alone; it reads both.
void main() {
  final core = Directory('../../packages/core/lib/src');
  final activities = {
    'arunoday':
        File('android/app/src/main/kotlin/com/samyak/arunoday/MainActivity.kt'),
    'nivaat': File(
        '../nivaat/android/app/src/main/kotlin/com/samyak/nivaat/MainActivity.kt'),
  };

  /// Comment LINES dropped first, so prose naming a channel or a method can't
  /// stand in for handling it. Whole lines only: a mid-line `//` is a URL.
  String code(File f) =>
      f.readAsStringSync().replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

  final channelName = RegExp(r'''['"](core/\w+)['"]''');
  final invocation =
      RegExp(r'''invokeMethod(?:<[^>]*>)?\(\s*['"]([^'"]+)['"]''');

  /// What core asks of each channel. One channel per file is the convention
  /// here; a file that declares two would silently pool their methods, so that
  /// stops the test rather than weakening it.
  Map<String, Set<String>> coreExpectations() {
    final out = <String, Set<String>>{};
    for (final f in core.listSync().whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final source = code(f);
      final names =
          channelName.allMatches(source).map((m) => m.group(1)!).toSet();
      if (names.isEmpty) continue;
      if (names.length > 1) {
        throw StateError('${f.path} declares $names — split them, or teach '
            'this test which methods belong to which');
      }
      out[names.single] =
          invocation.allMatches(source).map((m) => m.group(1)!).toSet();
    }
    return out;
  }

  final expected = coreExpectations();

  /// The same map read out of a MainActivity: channel name -> methods handled
  /// under it. Kotlin names its channels by `val`, so resolve those first, then
  /// attribute each `when` branch to the `MethodChannel(...)` block it sits in.
  Map<String, Set<String>> handledIn(File activity) {
    final source = code(activity);
    final vars = {
      for (final m
          in RegExp(r'''val\s+(\w+)\s*=\s*"(core/\w+)"''').allMatches(source))
        m.group(1)!: m.group(2)!,
    };
    final out = <String, Set<String>>{};
    // Each handler is one `MethodChannel(messenger, someVal)` block, and they
    // are siblings — so the text from one to the next belongs to that channel.
    final blocks = source.split('MethodChannel(').skip(1);
    for (final block in blocks) {
      final head = block.split('setMethodCallHandler').first;
      final channel = vars.entries
          .where((e) => RegExp('\\b${e.key}\\b').hasMatch(head))
          .map((e) => e.value)
          .firstOrNull;
      if (channel == null) continue;
      out[channel] = RegExp(r'"([^"]+)"\s*->')
          .allMatches(block)
          .map((m) => m.group(1)!)
          .toSet();
    }
    return out;
  }

  test('core still declares the channels this test is about', () {
    // Guards the regexes: a rename that quietly matched nothing would make
    // every check below pass against an empty map. Exact, not `containsAll`,
    // so deleting a call site has to be a deliberate edit here too.
    expect(expected, {
      'core/alarm_launch': {'consumeAlarmLaunch'},
      'core/app_icon': {'get', 'set'},
      'core/app_window': {'moveTaskToBack'},
      'core/system_settings': {'openNotificationSettings'},
    });
  });

  for (final entry in activities.entries) {
    test('${entry.key} answers each core channel with its own methods', () {
      expect(entry.value.existsSync(), isTrue);
      final handled = handledIn(entry.value);
      // Exact, not `containsAll`: `handledIn` only ever resolves `core/*`
      // names, so Nivaat's own `nivaat/battery` never lands here and equality
      // is safe — which also makes a handler for a channel core no longer
      // declares fail as the dead Kotlin it is.
      expect(handled.keys.toSet(), equals(expected.keys.toSet()),
          reason: 'an unregistered channel is a silent no-op, and an extra one '
              'is a handler nothing will ever call');
      expected.forEach((channel, methods) {
        expect(handled[channel], containsAll(methods),
            reason: '$channel must handle $methods — a registered channel '
                'whose `when` misses a method fails exactly like a missing '
                'one, because core swallows notImplemented()');
      });
    });
  }
}
