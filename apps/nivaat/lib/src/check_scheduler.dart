import 'dart:io';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:workmanager/workmanager.dart';

/// Schedules the background wind checks of the cascade.
///
/// Android: exact wakeups via AlarmManager — the ladder runs as designed.
/// iOS: BGAppRefresh via Workmanager — ladder times are wishes; iOS grants
/// slots opportunistically, and the evening/app-open checks carry the rest
/// (locked design, SPEC.md).
abstract class CheckScheduler {
  Future<void> initialize();

  Future<void> scheduleCheck(int alarmId, DateTime at);

  Future<void> cancelCheck(int alarmId);

  /// [androidEntrypoint] must be a top-level @pragma('vm:entry-point')
  /// function: it runs in a fresh background isolate where main() never ran.
  static CheckScheduler forPlatform({required Function androidEntrypoint}) =>
      Platform.isAndroid
          ? AndroidCheckScheduler(entrypoint: androidEntrypoint)
          : IosCheckScheduler();
}

/// Offset added to alarm ids to build AlarmManager request codes, so check
/// wakeups never collide with ring ids.
const int _checkIdOffset = 50000;

class AndroidCheckScheduler implements CheckScheduler {
  AndroidCheckScheduler({required this.entrypoint});

  final Function entrypoint;

  @override
  Future<void> initialize() async {
    await AndroidAlarmManager.initialize();
  }

  @override
  Future<void> scheduleCheck(int alarmId, DateTime at) async {
    await AndroidAlarmManager.oneShotAt(
      at,
      _checkIdOffset + alarmId,
      entrypoint,
      exact: true,
      wakeup: true,
      allowWhileIdle: true,
      rescheduleOnReboot: true,
    );
  }

  @override
  Future<void> cancelCheck(int alarmId) async {
    await AndroidAlarmManager.cancel(_checkIdOffset + alarmId);
  }
}

class IosCheckScheduler implements CheckScheduler {
  static const String refreshTaskId = 'com.samyak.nivaat.refresh';

  @override
  Future<void> initialize() async {
    // Single periodic BGAppRefresh registration; iOS decides actual timing.
    await Workmanager().registerPeriodicTask(
      refreshTaskId,
      refreshTaskId,
      frequency: const Duration(minutes: 30),
    );
  }

  @override
  Future<void> scheduleCheck(int alarmId, DateTime at) async {
    // No exact background wakeups on iOS — the periodic refresh plus
    // app-open evaluations cover the cascade (see SPEC.md).
  }

  @override
  Future<void> cancelCheck(int alarmId) async {}
}
