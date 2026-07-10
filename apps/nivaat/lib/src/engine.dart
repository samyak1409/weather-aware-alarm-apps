import 'dart:ui';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

import 'check_scheduler.dart';

/// Background entrypoint for Android AlarmManager wakeups. Runs in a fresh
/// isolate: rebuild the whole graph, evaluate every alarm, reschedule.
@pragma('vm:entry-point')
Future<void> nivaatBackgroundCheck() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await NivaatEngine.standard().evaluateAll();
}

/// Orchestrates the wind-check cascade for every alarm (SPEC.md):
/// fetch forecast/current wind for the alarm's court, decide, schedule or
/// cancel the ring with wind-proportional volume, persist cascade state,
/// record history at the final decision, and book the next check.
class NivaatEngine {
  NivaatEngine({
    required this.store,
    required this.scheduler,
    required this.api,
    required this.checks,
  });

  factory NivaatEngine.standard() => NivaatEngine(
        store: NivaatStore(),
        scheduler:
            AlarmPkgScheduler(soundAsset: 'assets/sounds/nivaat_ring.wav'),
        api: OpenMeteo(),
        checks: CheckScheduler.forPlatform(
            androidEntrypoint: nivaatBackgroundCheck),
      );

  final NivaatStore store;
  final AlarmScheduler scheduler;
  final OpenMeteo api;
  final CheckScheduler checks;

  /// Within this window of the alarm we trust live wind over forecast.
  static const Duration liveWindWindow = Duration(minutes: 15);

  Future<void> evaluateAll({DateTime? now}) async {
    final alarms = await store.loadAlarms();
    final courts = await store.loadCourts();
    for (final alarm in alarms) {
      await evaluateAlarm(alarm, courts, now: now);
    }
  }

  Future<void> evaluateAlarm(
    NivaatAlarm alarm,
    List<SavedLocation> courts, {
    DateTime? now,
  }) async {
    final t = now ?? DateTime.now();

    SavedLocation? court;
    for (final c in courts) {
      if (c.id == alarm.courtId) court = c;
    }

    final next = _resolveOccurrence(alarm, await store.loadCheckState(alarm.id), t);
    if (next == null || court == null) {
      await scheduler.cancel(alarm.id);
      await checks.cancelCheck(alarm.id);
      await store.clearCheckState(alarm.id);
      return;
    }

    // Cascade state is per-occurrence.
    var state = await store.loadCheckState(alarm.id);
    if (state == null || state.alarmAt != next) {
      state = CheckState(
        alarmId: alarm.id,
        alarmAt: next,
        hadSuccessfulCheck: false,
      );
    }

    WindDecision? decision;
    try {
      final untilAlarm = next.difference(t);
      final sample = untilAlarm <= liveWindWindow
          ? await api.currentWind(court.lat, court.lon)
          : await api.forecastWindAt(court.lat, court.lon, next);
      decision = decide(sample, alarm.thresholds);
    } on Exception {
      decision = null; // fail-silent per locked spec; cascade keeps retrying
    }

    if (decision != null) {
      final ringing = await scheduler.isRinging(alarm.id);
      if (decision.shouldRing) {
        if (!ringing) {
          // A retry that succeeds just after T rings late (never in the past).
          final ringAt =
              next.isAfter(t) ? next : t.add(const Duration(seconds: 10));
          await scheduler.scheduleRing(
            id: alarm.id,
            at: ringAt,
            title: 'Nivaat · ${court.name}',
            body:
                'Wind ~${decision.sample.courtSpeedKmh.toStringAsFixed(1)} km/h — play! 🏸',
            volume: decision.volume,
          );
        }
      } else {
        // Skip: cancel the pending ring (also stops a just-started one).
        await scheduler.cancel(alarm.id);
      }
    }

    final hadSuccess = state.hadSuccessfulCheck || decision != null;
    await store.saveCheckState(CheckState(
      alarmId: alarm.id,
      alarmAt: next,
      hadSuccessfulCheck: hadSuccess,
    ));

    final nextCheck =
        CheckCascade.nextCheckTime(t, next, hadSuccessfulCheck: hadSuccess);

    // Final decision moment: at/after T with a result, or cascade exhausted.
    final atOrPastAlarm =
        !t.isBefore(next.subtract(const Duration(seconds: 30)));
    if (atOrPastAlarm && decision != null) {
      await store.addHistory(HistoryRecord(
        alarmId: alarm.id,
        at: next,
        outcome: switch (decision.verdict) {
          WindVerdict.ring => CheckOutcome.rang,
          WindVerdict.tooWindy => CheckOutcome.skippedWindy,
          WindVerdict.tooGusty => CheckOutcome.skippedGusty,
        },
        courtSpeedKmh: decision.sample.courtSpeedKmh,
        rawGustKmh: decision.sample.rawGustKmh,
        volume: decision.shouldRing ? decision.volume : null,
      ));
      await store.clearCheckState(alarm.id);
    } else if (atOrPastAlarm && nextCheck == null) {
      // Every check of this occurrence failed and the retry cap has passed.
      await store.addHistory(HistoryRecord(
        alarmId: alarm.id,
        at: next,
        outcome: CheckOutcome.skippedNoData,
      ));
      await store.clearCheckState(alarm.id);
    }

    if (nextCheck != null && !(atOrPastAlarm && decision != null)) {
      await checks.scheduleCheck(alarm.id, nextCheck);
    }
  }

  /// The occurrence this evaluation is about. An in-flight occurrence
  /// (persisted state, still within the post-alarm retry window) wins over
  /// [NivaatAlarm.nextOccurrence], which would otherwise jump to next
  /// week/day the moment T passes.
  DateTime? _resolveOccurrence(
    NivaatAlarm alarm,
    CheckState? state,
    DateTime t,
  ) {
    if (!alarm.enabled) return null;
    if (state != null) {
      final cap = state.alarmAt
          .add(const Duration(minutes: CheckCascade.retryCapMinutesAfter));
      final inFlight = !t.isAfter(cap);
      if (inFlight && alarm.weekdays.contains(state.alarmAt.weekday)) {
        return state.alarmAt;
      }
    }
    return alarm.nextOccurrence(t);
  }
}
