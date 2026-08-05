import 'dart:io';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'ids.dart';

/// Schedules the background wind checks of the cascade.
///
/// Android: exact wakeups via AlarmManager — the ladder runs as designed.
/// iOS: two opportunistic Workmanager triggers — a periodic BGAppRefresh plus a
/// BGProcessingTask whose earliestBeginDate is nudged to the next cascade rung;
/// ladder times are wishes (iOS grants slots opportunistically), and app-open
/// checks carry the rest (locked design, SPEC.md).
abstract class CheckScheduler {
  Future<void> initialize();

  /// Books the next wind check, and reports whether it is really booked.
  ///
  /// **A caller that goes on as though a wakeup exists must check this.** On
  /// Android nothing else re-books the cascade — checks only ever reschedule
  /// themselves — so a swallowed failure ends the morning outright: no check
  /// at T, no retries, no card, and no ring unless an earlier rung had
  /// already found calm air (REVIEW #22). iOS is softer: the periodic refresh
  /// re-drives everything within half an hour whatever this returns.
  Future<bool> scheduleCheck(int alarmId, DateTime at);

  Future<void> cancelCheck(int alarmId);

  /// [androidEntrypoint] must be a top-level @pragma('vm:entry-point')
  /// function: it runs in a fresh background isolate where main() never ran.
  static CheckScheduler forPlatform({required Function androidEntrypoint}) =>
      Platform.isAndroid
          ? AndroidCheckScheduler(entrypoint: androidEntrypoint)
          : IosCheckScheduler();
}

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
  Future<bool> scheduleCheck(int alarmId, DateTime at) async {
    if (await _book(alarmId, at, exact: true)) return true;
    // Coarse rather than nothing. The likeliest cause of an exact booking
    // being refused is a SecurityException over exact-alarm permission, and an
    // inexact alarm needs none — so it can succeed where the exact one did
    // not. A check that runs a few minutes late still decides the morning;
    // a cascade that stopped booking decides nothing ever again. Same
    // strategy the `alarm` plugin uses for its own rings.
    final coarse = await _book(alarmId, at, exact: false);
    debugPrint(
      coarse
          ? 'nivaat scheduleCheck(alarm $alarmId) fell back to an INEXACT '
              'wakeup near $at — the ladder still runs, just not on the dot'
          : 'nivaat scheduleCheck(alarm $alarmId) FAILED for $at — nothing '
              'will re-drive this alarm until the app is opened',
    );
    return coarse;
  }

  Future<bool> _book(int alarmId, DateTime at, {required bool exact}) async {
    try {
      return await AndroidAlarmManager.oneShotAt(
        at,
        // Its own block, so a check wakeup can never land on a ring id.
        NivaatIds.check(alarmId),
        entrypoint,
        exact: exact,
        wakeup: true,
        allowWhileIdle: true,
        rescheduleOnReboot: true,
      );
    } on Exception catch (e) {
      _logCheckError(exact ? 'scheduleCheck' : 'scheduleCheck(inexact)', e,
          alarmId: alarmId);
      return false;
    }
  }

  @override
  Future<void> cancelCheck(int alarmId) async {
    try {
      await AndroidAlarmManager.cancel(NivaatIds.check(alarmId));
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
  Future<bool> scheduleCheck(int alarmId, DateTime at) async {
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
      return true;
    } on Exception catch (e) {
      _logCheckError('scheduleCheck', e, alarmId: alarmId);
      // Softer here than on Android: the periodic BGAppRefresh re-drives the
      // whole cascade within half an hour regardless, so a refused
      // BGProcessing submit costs precision, not the morning.
      return false;
    }
  }

  /// **Deliberately does nothing, and must stay that way** (REVIEW #8).
  ///
  /// One BGProcessing task serves the whole app — iOS task ids are fixed in
  /// Info.plist, so they cannot be per-alarm — so cancelling it for one alarm
  /// cancelled every other alarm's next check too. It costs nothing to skip:
  /// the submission is one-shot, so an unwanted task fires once, finds no work
  /// and dies. A reference count is not the fix either (a fresh isolate starts
  /// empty and would cancel anyway) — full argument in CLAUDE.md. Android is
  /// genuinely per-alarm and still cancels.
  @override
  Future<void> cancelCheck(int alarmId) async {}
}
