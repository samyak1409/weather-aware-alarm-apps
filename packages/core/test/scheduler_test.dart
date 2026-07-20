import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The permission banner must never appear off-iOS: on Android (and the test
  // host) there is no AlarmKit, so scheduling is never "denied" and the plugin
  // is never even queried. Guards the AlarmKit-only-on-iOS contract.
  test('alarmSchedulingDenied is false when not on iOS', () async {
    if (Platform.isIOS) return; // the iOS path needs the plugin/device
    expect(await alarmSchedulingDenied(), isFalse);
  });

  test('createAlarmScheduler yields the alarm-package scheduler off iOS',
      () async {
    if (Platform.isIOS) return;
    final scheduler = await createAlarmScheduler(
      soundAssetForVolume: (_) => 'a.wav',
      tintColor: '#000000',
    );
    expect(scheduler, isA<AlarmPkgScheduler>());
  });

  group('NoOpAlarmScheduler', () {
    const scheduler = NoOpAlarmScheduler();

    test('ensureInitialized completes', () async {
      await scheduler.ensureInitialized();
    });

    test('scheduleRing / cancel leave scheduledIds empty and never ringing',
        () async {
      await scheduler.scheduleRing(
        id: 1,
        at: DateTime.now().add(const Duration(hours: 1)),
        title: 't',
        body: 'b',
        volume: 1,
      );
      await scheduler.scheduleRing(
        id: 2,
        at: DateTime.now().add(const Duration(hours: 2)),
        title: 't',
        body: 'b',
        volume: 0.5,
      );
      expect(await scheduler.scheduledIds(), isEmpty);
      expect(await scheduler.isRinging(1), isFalse);
      expect(await scheduler.isRinging(2), isFalse);
      await scheduler.cancel(1);
      await scheduler.cancel(1); // idempotent
      expect(await scheduler.scheduledIds(), isEmpty);
      expect(await scheduler.isRinging(1), isFalse);
    });
  });
}
