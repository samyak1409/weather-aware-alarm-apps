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
    // which returns a pre-attenuated variant — a ring quietened for wind played
    // the 75% file at 75% system volume, ~56% of full: outside SPEC.md's
    // 75-100% band, and quieter than the identical ring on iOS.
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

    test('a null volume leaves the phone\'s own alarm volume alone', () {
      // Arunoday's case, device-caught: it passed 1.0, so the plugin turned
      // the system alarm volume up to maximum and — with volumeEnforced —
      // put it back every time the user tried to turn it down. A phone
      // deliberately set quiet rang at full blast. Null is the plugin's
      // documented "use the current system volume".
      final scheduler = AlarmPkgScheduler(soundAssetForVolume: (_) => 'r.wav');
      final quiet = scheduler.settingsFor(
          id: 1, at: DateTime(2026), title: 't', body: 'b', volume: null);
      expect(quiet.volumeSettings.volume, isNull);
      expect(quiet.volumeSettings.volumeEnforced, isFalse,
          reason: 'there is no volume to enforce, and pinning the user out of '
              'their own slider is not ours to do');
    });

    test('a real volume is still set and held — Nivaat\'s wind ramp', () {
      // The other half, and why this is a null rather than a removal: Nivaat's
      // loudness IS a decision the wind made (SPEC.md), so it must survive a
      // mid-ring nudge at the volume rocker.
      final scheduler = AlarmPkgScheduler(soundAssetForVolume: (_) => 'r.wav');
      final ramped = scheduler.settingsFor(
          id: 1, at: DateTime(2026), title: 't', body: 'b', volume: 0.85);
      expect(ramped.volumeSettings.volume, 0.85);
      expect(ramped.volumeSettings.volumeEnforced, isTrue);
    });

    test('the ring notification re-posts on dismiss while still ringing', () {
      // alarm 5.9.0 / #421 / #423: false restores the notification on swipe
      // instead of leaving a sounding alarm with no Stop control.
      final scheduler = AlarmPkgScheduler(soundAssetForVolume: (_) => 'r.wav');
      final settings = scheduler
          .settingsFor(
              id: 1, at: DateTime(2026), title: 'Wake', body: 'Dawn', volume: null)
          .notificationSettings;
      expect(settings.androidStopAlarmOnDismiss, isFalse);
      expect(settings.title, 'Wake');
      expect(settings.body, 'Dawn');
      expect(settings.stopButton, 'Stop');
      expect(settings.icon, kNotificationIconRes,
          reason: 'the monochrome drawable, never the launcher blob');
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
