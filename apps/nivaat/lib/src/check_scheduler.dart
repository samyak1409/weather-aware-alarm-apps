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

  /// Books wind-check wakeups — **rung index -> when** — and reports whether
  /// every one of them really landed.
  ///
  /// Takes a map rather than one time because the pre-T ladder is booked ALL
  /// AT ONCE (see [NivaatIds.check]): the rungs are known the moment the
  /// occurrence is, and booking them independently means no rung can take its
  /// successors down with it. Post-T retries pass a single entry keyed on the
  /// last rung, which is the locker they share.
  ///
  /// **A caller that goes on as though a wakeup exists must check this.** On
  /// Android nothing else re-books the ladder, so a swallowed failure ends the
  /// morning outright: no check at T, no retries, no card, and no ring unless
  /// an earlier rung had already found calm air (REVIEW #22). iOS is softer:
  /// the periodic refresh re-drives everything within
  /// [IosCheckScheduler.refreshFrequency] whatever this returns.
  Future<bool> scheduleChecks(int alarmId, Map<int, DateTime> rungs);

  /// Every rung locker for [alarmId] — an edit or a delete must clear them all,
  /// or a stale rung fires for an occurrence that has moved.
  Future<void> cancelChecks(int alarmId);

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

  /// **There is no inexact fallback, and re-adding one would be dead code**
  /// (2026-08-15, Samyak — verified in the plugin's own Java, not inferred).
  ///
  /// There used to be one: an exact booking that came back `false` was retried
  /// with `exact: false`, on the reasoning that the likeliest refusal is the
  /// exact-alarm permission and an inexact alarm needs none. **The retry could
  /// never run.** `android_alarm_manager_plus 5.1.0` hands the request to
  /// `AlarmService.setOneShot`, which returns `void` — and when
  /// `canScheduleExactAlarms()` is false it logs and books *nothing*
  /// (`AlarmService.java:163`). The method-channel handler then answers
  /// `result.success(true)` unconditionally (`AndroidAlarmManagerPlugin.java:121`),
  /// so `oneShotAt` reports success for an alarm it never scheduled and the
  /// old first branch returned before the fallback was reached. The only way
  /// `false` ever arrived here was the plugin being absent altogether, and a
  /// second call into an absent plugin fails the same way.
  ///
  /// **So this `bool` is the plugin's word, and on Android it is worth less
  /// than REVIEW #2 assumes** — `true` means "the channel accepted the call",
  /// not "an alarm exists". Closing that would mean asking
  /// `canScheduleExactAlarms()` ourselves, which needs a MethodChannel, and
  /// **a MainActivity channel cannot answer here**: most `scheduleChecks` calls
  /// run in the background isolate `android_alarm_manager_plus` spawns, where
  /// no Activity is attached. It would have to be a real `FlutterPlugin` so
  /// the registrant reaches every engine.
  ///
  /// **Not built, deliberately.** Both apps declare `USE_EXACT_ALARM`, which
  /// Android grants automatically and the user cannot revoke (it is the
  /// alarm-clock permission, and these are alarm clocks), and `minSdk` is 33 —
  /// the API level that added it. So `canScheduleExactAlarms()` is true on
  /// every version either app runs on, the refusal branch is unreachable, and
  /// a banner for it could never render — the exact "documented alternative
  /// that no state can render" this repo deleted outright on 2026-08-15.
  /// **What changes the answer:** `USE_EXACT_ALARM` is subject to a Google
  /// Play policy limited to alarm/calendar apps. If it ever has to come off
  /// the manifest, this silently books nothing — build the plugin-side check
  /// and the banner in the same change, and don't reach for the fallback.
  @override
  Future<bool> scheduleChecks(int alarmId, Map<int, DateTime> rungs) async {
    // Each booking is guarded on its own: one rung the platform refuses must
    // not cost the other eight, which is the whole reason they stopped being
    // a chain.
    var all = true;
    for (final e in rungs.entries) {
      if (!await _book(alarmId, e.key, e.value)) all = false;
    }
    return all;
  }

  Future<bool> _book(int alarmId, int rung, DateTime at) async {
    try {
      final booked = await AndroidAlarmManager.oneShotAt(
        at,
        // Its own block per rung, so a check wakeup can never land on a ring
        // id and no two rungs share a locker.
        NivaatIds.check(alarmId, rung),
        entrypoint,
        exact: true,
        wakeup: true,
        allowWhileIdle: true,
        rescheduleOnReboot: true,
      );
      if (!booked) {
        debugPrint('nivaat check rung $rung (alarm $alarmId) FAILED for $at');
      }
      return booked;
    } on Exception catch (e) {
      _logCheckError('scheduleChecks[rung $rung]', e, alarmId: alarmId);
      return false;
    }
  }

  @override
  Future<void> cancelChecks(int alarmId) async {
    for (final id in NivaatIds.allChecks(alarmId)) {
      try {
        await AndroidAlarmManager.cancel(id);
      } on Exception catch (e) {
        _logCheckError('cancelChecks', e, alarmId: alarmId);
      }
    }
  }
}

class IosCheckScheduler implements CheckScheduler {
  static const String refreshTaskId = 'com.samyak.nivaat.refresh';
  static const String processingTaskId = 'com.samyak.nivaat.processing';

  /// How often we ASK iOS to run the periodic BGAppRefresh backstop.
  ///
  /// **The number that reaches iOS is the one in `AppDelegate.swift`, not this
  /// one** (2026-08-30, caught in review by Cursor Grok 4.6). Passing
  /// `frequency:` to `Workmanager().registerPeriodicTask` does nothing on iOS —
  /// the plugin's own dartdoc says "you cannot set frequency for iOS here
  /// rather you have to set in AppDelegate.swift", and the Swift agrees: the
  /// pigeon path submits with `initialDelaySeconds`, while the frequency
  /// captured at REGISTRATION is what each re-submission uses. So this constant
  /// spent a fortnight reading 15 while iOS went on asking for 30, and the test
  /// that "pinned" it only ever read this side. It now reads the Swift.
  ///
  /// **15 minutes, and both halves of that are derived** (2026-08-15, Samyak —
  /// it was an undocumented 30 with no reason recorded anywhere). It is
  /// `workmanager_apple`'s own default when a caller passes no frequency
  /// (`WorkmanagerPlugin.swift:45`, `earliestBeginInSeconds ?? (15 * 60)`), so
  /// it is the floor the plugin itself considers sane; and it matches the
  /// **15-minute grid Open-Meteo's wind data actually moves on** (`current`
  /// carries `interval: 900` and snaps to `HH:00/:15/:30/:45`), so asking more
  /// often could not surface a number that had changed.
  ///
  /// **Lowering it does not make iOS run more often.** The plugin sets it as
  /// `BGAppRefreshTaskRequest.earliestBeginDate` (`WorkmanagerPlugin.swift:96`),
  /// which Apple treats as a floor, not a schedule — iOS may run it late or
  /// never, and it learns from when the user actually opens the app, which for
  /// a 6am alarm is the worst possible prior. All this buys is that we stop
  /// asking for less than we could. The real iOS backstop is the **pre-arm**:
  /// any successful check puts a live AlarmKit alarm on the OS, which then
  /// fires with no background work at all.
  ///
  /// "Periodic" is also a Dart-side fiction — the handler re-submits itself on
  /// each run (`WorkmanagerPlugin.swift:45`), so a task that never runs never
  /// re-books either.
  static const Duration refreshFrequency = Duration(minutes: 15);

  @override
  Future<void> initialize() async {
    // Two opportunistic iOS triggers = widest net (SPEC.md): a periodic
    // BGAppRefresh (usage-driven, daytime) here + a BGProcessingTask
    // (idle window, charging-or-not) scheduled per cascade rung in
    // [scheduleChecks]. iOS decides if/when either actually runs.
    //
    // **This call still matters even though `frequency:` does nothing here.**
    // `AppDelegate.swift` only REGISTERS the handler; this is what first
    // *submits* the task (at delay 0, since we pass no initial delay), and
    // every re-submit after a run takes its floor from the Swift. So don't
    // delete it on the grounds that the cadence lives in the Swift — deleting
    // it means the task is never submitted at all. The argument is left in
    // place for the two reasons `check_scheduler_test` now enforces: it states
    // the floor we intend, and it has to keep matching the Swift.
    await Workmanager().registerPeriodicTask(
      refreshTaskId,
      refreshTaskId,
      frequency: refreshFrequency,
    );
  }

  @override
  Future<bool> scheduleChecks(int alarmId, Map<int, DateTime> rungs) async {
    // One BGProcessing task serves the whole app, so "book every rung" cannot
    // mean nine submissions here — it means aiming the single task at the
    // SOONEST one. The rest are covered by the periodic refresh and by the
    // pre-arm, which is what actually saves an iOS morning.
    if (rungs.isEmpty) return true;
    final at = rungs.values.reduce((a, b) => a.isBefore(b) ? a : b);
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
      _logCheckError('scheduleChecks', e, alarmId: alarmId);
      // Softer here than on Android: the periodic BGAppRefresh re-drives the
      // whole cascade on its own cadence ([refreshFrequency]) regardless, so a
      // refused BGProcessing submit costs precision, not the morning. (That
      // cadence is what we ASK for, never a guarantee — see the constant.)
      return false;
    }
  }

  /// **Deliberately does nothing, and must stay that way** (REVIEW #8).
  ///
  /// (Per-rung lockers changed nothing here: iOS task ids are a fixed list in
  /// Info.plist, so there is still exactly one task to cancel and cancelling it
  /// still takes away every other alarm's wakeup.)
  ///
  /// One BGProcessing task serves the whole app — iOS task ids are fixed in
  /// Info.plist, so they cannot be per-alarm — so cancelling it for one alarm
  /// cancelled every other alarm's next check too. It costs nothing to skip:
  /// the submission is one-shot, so an unwanted task fires once, finds no work
  /// and dies. A reference count is not the fix either (a fresh isolate starts
  /// empty and would cancel anyway) — full argument in CLAUDE.md. Android is
  /// genuinely per-alarm and still cancels.
  @override
  Future<void> cancelChecks(int alarmId) async {}
}
