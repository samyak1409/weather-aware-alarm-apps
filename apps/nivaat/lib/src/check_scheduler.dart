import 'dart:io';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

/// Schedules the background wind checks of the cascade.
///
/// Android: exact wakeups via AlarmManager — the ladder runs as designed.
/// iOS: two opportunistic Workmanager triggers — a periodic BGAppRefresh plus a
/// BGProcessingTask whose earliestBeginDate is nudged to the next cascade rung;
/// ladder times are wishes (iOS grants slots opportunistically), and app-open
/// checks carry the rest (locked design, SPEC.md).
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

/// Reports a check-scheduling failure without letting it abort the batch.
/// Booking/cancel hit platform plugins (AlarmManager / BGTaskScheduler); one
/// that throws must never stop `evaluateAll` from evaluating the other alarms —
/// the next wakeup (and, on iOS, the periodic refresh) re-drives the cascade.
/// Logged, never swallowed silently, so a genuine setup error stays visible.
void _logCheckError(String op, Object error, {int? alarmId}) {
  final where = alarmId == null ? op : '$op(alarm $alarmId)';
  debugPrint('nivaat CheckScheduler.$where failed (non-fatal): $error');
}

class AndroidCheckScheduler implements CheckScheduler {
  AndroidCheckScheduler({
    required this.entrypoint,
    /// Override in tests — production uses [AndroidAlarmManager.initialize].
    Future<bool> Function()? initializePlugin,
  }) : _initializePlugin =
            initializePlugin ?? AndroidAlarmManager.initialize;

  final Function entrypoint;
  final Future<bool> Function() _initializePlugin;

  @override
  Future<void> initialize() async {
    // Must never abort app launch: a native/R8 failure here used to turn into
    // "Nivaat keeps stopping" before runApp (release-only; debug doesn't minify).
    // Catch Exception only — programming Errors still surface.
    try {
      await _initializePlugin();
    } on Exception catch (e) {
      _logCheckError('initialize', e);
    }
  }

  @override
  Future<void> scheduleCheck(int alarmId, DateTime at) async {
    try {
      await AndroidAlarmManager.oneShotAt(
        at,
        _checkIdOffset + alarmId,
        entrypoint,
        exact: true,
        wakeup: true,
        allowWhileIdle: true,
        rescheduleOnReboot: true,
      );
    } on Exception catch (e) {
      _logCheckError('scheduleCheck', e, alarmId: alarmId);
    }
  }

  @override
  Future<void> cancelCheck(int alarmId) async {
    try {
      await AndroidAlarmManager.cancel(_checkIdOffset + alarmId);
    } on Exception catch (e) {
      _logCheckError('cancelCheck', e, alarmId: alarmId);
    }
  }
}

class IosCheckScheduler implements CheckScheduler {
  static const String refreshTaskId = 'com.samyak.nivaat.refresh';
  static const String processingTaskId = 'com.samyak.nivaat.processing';

  @override
  Future<void> initialize() async {
    // Two opportunistic iOS triggers = widest net (SPEC.md): a periodic
    // BGAppRefresh (usage-driven, daytime) here + a BGProcessingTask
    // (idle window, charging-or-not) scheduled per cascade rung in
    // [scheduleCheck]. iOS decides if/when either actually runs.
    await Workmanager().registerPeriodicTask(
      refreshTaskId,
      refreshTaskId,
      frequency: const Duration(minutes: 30),
    );
  }

  @override
  Future<void> scheduleCheck(int alarmId, DateTime at) async {
    // iOS can't wake at an exact time, but a BGProcessingTask's earliestBeginDate
    // can be nudged to the next cascade rung ([at]), so a granted (opportunistic)
    // wakeup lands near T instead of being burned early. `requiresCharging:false`
    // → runs charging-or-not (our check is one tiny HTTP call, not intensive);
    // network required. Re-registered every evaluateAll, so it walks the ladder
    // toward T. One shared task: with several alarms the last-scheduled rung
    // wins — the periodic refresh backstops the rest. earliestBeginDate is a
    // floor, not a schedule (Apple), so this improves odds, not guarantees.
    final delay = at.difference(DateTime.now());
    // Routine BGTaskScheduler.submit failures (simulator, throttling, id not
    // registered) are already caught + logged natively by workmanager and do
    // NOT throw here; this catch is for the setup-error paths (Workmanager not
    // initialised, plugin missing) so one bad booking can't abort the batch.
    try {
      await Workmanager().registerProcessingTask(
        processingTaskId,
        processingTaskId,
        initialDelay: delay.isNegative ? Duration.zero : delay,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresCharging: false,
        ),
      );
    } on Exception catch (e) {
      _logCheckError('scheduleCheck', e, alarmId: alarmId);
    }
  }

  @override
  Future<void> cancelCheck(int alarmId) async {
    // Best-effort; a stale processing task just no-ops on its next run.
    try {
      await Workmanager().cancelByUniqueName(processingTaskId);
    } on Exception catch (e) {
      _logCheckError('cancelCheck', e, alarmId: alarmId);
    }
  }
}
