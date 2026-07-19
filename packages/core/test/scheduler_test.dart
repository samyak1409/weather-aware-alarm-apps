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
}
