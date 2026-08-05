import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  group('who opened the app', () {
    const channel = MethodChannel('core/alarm_launch');
    final calls = <MethodCall>[];
    int? pending;

    void handleWith(Future<Object?>? Function(MethodCall)? handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
    }

    setUp(() {
      calls.clear();
      pending = null;
      handleWith((call) async {
        calls.add(call);
        final id = pending;
        pending = null; // consumed, exactly as MainActivity does
        return id;
      });
    });

    tearDown(() => handleWith(null));

    test('an alarm launch is reported once, then gone', () async {
      // This replaced `kRingForegroundGrace` + `alarmOpenedTheApp` on
      // 2026-08-05. The old pair guessed from how recently the app had
      // resumed, because the plugin opened the launcher intent and Dart had
      // nothing else to go on; declaring the plugin's RING action (alarm
      // 5.7.0+) makes it a fact the OS hands over. Consuming is the whole
      // contract — a second ring must not inherit the first one's answer.
      await onPlatform(TargetPlatform.android, () async {
        pending = 42;
        expect(await consumeAlarmLaunch(), 42);
        expect(await consumeAlarmLaunch(), isNull);
        expect(calls.map((c) => c.method), ['consumeAlarmLaunch', 'consumeAlarmLaunch']);
      });
    });

    test('the user opening the app reports nothing', () async {
      await onPlatform(TargetPlatform.android, () async {
        expect(await consumeAlarmLaunch(), isNull);
      });
    });

    test('iOS never touches the channel — no ring ever opens the app',
        () async {
      // AlarmKit alerts are system-rendered and open nothing, so there is no
      // launch to attribute. Same reason sendAppToBackground is Android-only.
      await onPlatform(TargetPlatform.iOS, () async {
        pending = 42;
        expect(await consumeAlarmLaunch(), isNull);
        expect(calls, isEmpty);
      });
    });

    test('a host that forgot the channel, or refuses, reads as the user',
        () async {
      // Failing closed matters: a null leaves the app on screen, which is
      // what it always used to do. Guessing "the alarm" would hide an app the
      // user had opened themselves.
      for (final handler in <Future<Object?>? Function(MethodCall)?>[
        null,
        (call) async => throw PlatformException(code: 'boom'),
      ]) {
        handleWith(handler);
        await onPlatform(TargetPlatform.android, () async {
          expect(await consumeAlarmLaunch(), isNull);
        });
      }
    });
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
