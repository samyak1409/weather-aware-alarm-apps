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

  group('AlarmPkgScheduler applies the loudness ramp exactly once', () {
    // Regression (2026-07-26): this scheduler passed the ring volume to the
    // asset resolver AND set the system volume to it. With Nivaat's resolver —
    // which returns a pre-attenuated variant — a windy-morning ring played the
    // 75% file at 75% system volume, ~56% of full: outside SPEC.md's 75-100%
    // band, and quieter than the identical ring on iOS.
    test('the tone is resolved at full volume, never pre-attenuated', () {
      final askedFor = <double>[];
      final scheduler = AlarmPkgScheduler(soundAssetForVolume: (v) {
        askedFor.add(v);
        return 'ring_${(v * 100).round()}.wav';
      });
      expect(scheduler.ringAsset, 'ring_100.wav');
      expect(askedFor, [1.0],
          reason: 'the ramp belongs to VolumeSettings on Android, not the file');
    });

    test('a user-selected tone still wins', () {
      // The resolver is also how the tone picker takes effect, so full volume
      // must not mean "always the default".
      final scheduler =
          AlarmPkgScheduler(soundAssetForVolume: (_) => '/tones/temple.ogg');
      expect(scheduler.ringAsset, '/tones/temple.ogg');
    });
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
