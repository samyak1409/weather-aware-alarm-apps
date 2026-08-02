import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The full-screen intent opens the app to show the ring screen, so stopping
/// the ring has to put it away again — otherwise you unlock at 6:05 and find
/// your alarm app on top of whatever you were doing. Two halves: WHO opened
/// the app (pure, here) and the platform call that hides it (Android only).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Reset INSIDE the body: the binding asserts every foundation debug var is
  /// null BEFORE tearDowns run, so `addTearDown` is too late.
  Future<void> onPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  test('only a settled foreground counts as the user opening the app', () {
    // Everything else reads as the alarm's doing, including `resumed` — the
    // intent resumes the activity and the ring event reaches Dart at about the
    // same time, in no fixed order, so being resumed proves nothing this early.
    final cases = <(String, AppLifecycleState?, Duration?, bool)>[
      ('paused', AppLifecycleState.paused, null, true),
      ('inactive', AppLifecycleState.inactive, null, true),
      ('hidden', AppLifecycleState.hidden, null, true),
      ('detached', AppLifecycleState.detached, null, true),
      ('resumed, never seen begin', AppLifecycleState.resumed, null, true),
      ('a hair inside the grace', AppLifecycleState.resumed,
          kRingForegroundGrace - const Duration(milliseconds: 1), true),
      // A floor, not a window that reopens: at the grace it is already theirs.
      ('exactly at the grace', AppLifecycleState.resumed,
          kRingForegroundGrace, false),
      ('a hair past it', AppLifecycleState.resumed,
          kRingForegroundGrace + const Duration(milliseconds: 1), false),
      ('long settled', AppLifecycleState.resumed,
          const Duration(minutes: 10), false),
    ];

    for (final (name, lifecycle, since, alarmDidIt) in cases) {
      expect(
        alarmOpenedTheApp(lifecycle: lifecycle, sinceForeground: since),
        alarmDidIt,
        reason: '$name should read as ${alarmDidIt ? "the alarm" : "the user"}',
      );
    }
  });

  test('the grace stays short on purpose', () {
    // Samyak's call (2026-08-02, down from 5s): the window is a guess either
    // way, and hiding an app someone had just opened themselves is the worse
    // half of it. Pinned so an "it sometimes stays open" report gets fixed at
    // the cause — the missing launch-intent extra, tracked upstream — rather
    // than by quietly widening this back out.
    expect(kRingForegroundGrace, const Duration(seconds: 1));
  });

  group('sending the app to the back', () {
    const channel = MethodChannel('core/app_window');
    final calls = <MethodCall>[];

    void handleWith(Future<Object?>? Function(MethodCall)? handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
    }

    setUp(() {
      calls.clear();
      handleWith((call) async {
        calls.add(call);
        return true;
      });
    });

    tearDown(() => handleWith(null));

    test('Android asks the activity to hide itself', () async {
      await onPlatform(TargetPlatform.android, () async {
        await sendAppToBackground();
        expect(calls.map((c) => c.method), ['moveTaskToBack']);
      });
    });

    test('iOS never touches the channel — there is no such API to call',
        () async {
      // Not just "the call fails on iOS": AlarmKit rings without ever opening
      // the app, so there is nothing to hide, and Apple ships no way to.
      await onPlatform(TargetPlatform.iOS, () async {
        await sendAppToBackground();
        expect(calls, isEmpty);
      });
    });

    test('a host that forgot the channel, or refuses, still ends the ring',
        () async {
      for (final handler in <Future<Object?>? Function(MethodCall)?>[
        null,
        (call) async => throw PlatformException(code: 'no task'),
      ]) {
        handleWith(handler);
        await onPlatform(TargetPlatform.android, () async {
          await expectLater(sendAppToBackground(), completes);
        });
      }
    });
  });
}
