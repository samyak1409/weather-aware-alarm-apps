import 'dart:ui';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

import 'check_scheduler.dart';
import 'skip_notifier.dart';

/// User-selected alarm tone; null = default Court Call. Loaded from the
/// store at startup and in background entrypoints.
String? nivaatSelectedSound;

const String nivaatDefaultSound = 'assets/sounds/nivaat_ring.wav';

/// Maps the wind-ramp volume to a pre-rendered loudness variant (AlarmKit
/// has no volume knob). Variants exist only for the default Court Call;
/// other tones play as-is (the `alarm` package path applies real volume,
/// so this only flattens the ramp on iOS with a non-default tone).
String nivaatSoundForVolume(double volume) {
  final selected = nivaatSelectedSound;
  if (selected != null && selected != nivaatDefaultSound) return selected;
  final pct = ((volume * 10).round() * 10).clamp(50, 100);
  return 'assets/sounds/nivaat_ring_$pct.wav';
}

/// Background entrypoint for Android AlarmManager wakeups. Runs in a fresh
/// isolate: rebuild the whole graph, evaluate every alarm, reschedule.
@pragma('vm:entry-point')
Future<void> nivaatBackgroundCheck() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final engine = await NivaatEngine.standard();
  nivaatSelectedSound = await engine.store.loadSoundPath();
  await engine.evaluateAll();
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
    this.notifier,
  });

  static Future<NivaatEngine> standard() async => NivaatEngine(
        store: NivaatStore(),
        scheduler: await createAlarmScheduler(
          soundAssetForVolume: nivaatSoundForVolume,
          tintColor: '#6FB7EC',
        ),
        api: OpenMeteo(),
        checks: CheckScheduler.forPlatform(
            androidEntrypoint: nivaatBackgroundCheck),
        notifier: SkipNotifier(),
      );

  final NivaatStore store;
  final AlarmScheduler scheduler;
  final OpenMeteo api;
  final CheckScheduler checks;
  final SkipNotifier? notifier;

  Future<void> _notifySkip(HistoryRecord record, String courtName) async {
    try {
      await notifier?.showSkip(record, courtName);
    } on Exception {
      // A notification failure must never break the cascade.
    }
  }

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

    final stored = await store.loadCheckState(alarm.id);
    final next = _resolveOccurrence(alarm, stored, t);
    if (next == null || court == null) {
      await scheduler.cancel(alarm.id);
      await checks.cancelCheck(alarm.id);
      await store.clearCheckState(alarm.id);
      return;
    }

    // Rule 1: a ring physically sounding IS the decision, made real — never
    // cancel it or relabel it on a resync/check. (Disabled alarms fall through
    // above so an explicit delete/toggle-off can still stop a ring.) The pre-T
    // ladder — not a split-second T-0 cancel — is what keeps a windy morning
    // from ringing; once it's audible, it stays. This is what makes "open the
    // app during a ring" safe on both platforms.
    if (alarm.enabled && await scheduler.isRinging(alarm.id)) return;

    // A committed ring from an occurrence we're no longer tracking as current
    // (the app opened past the 30-min retry window, so `next` has already moved
    // on) still fired — record its "rang" so a late open never loses it. This
    // is mutually exclusive with Rule 2 below, which handles the in-window case
    // (next == stored.alarmAt); the clear lets the fresh state for `next` take
    // over. Without it, iOS (no exact T-0 check) drops the ring from history
    // whenever the app is first opened >30 min after it rang.
    if (stored != null &&
        stored.ringScheduled &&
        stored.alarmAt != next &&
        t.isAfter(stored.alarmAt)) {
      await store.addHistory(HistoryRecord(
        alarmId: alarm.id,
        at: stored.alarmAt,
        outcome: CheckOutcome.rang,
        courtSpeedKmh: stored.ringCourtSpeedKmh,
        rawGustKmh: stored.ringRawGustKmh,
        courtSpeedLimitKmh: alarm.courtSpeedLimitKmh,
        rawGustLimitKmh: alarm.thresholds.rawGustLimit,
        volume: stored.ringVolume,
      ));
      await store.clearCheckState(alarm.id);
    }

    // Cascade state is per-occurrence.
    var state = (stored != null && stored.alarmAt == next)
        ? stored
        : CheckState(alarmId: alarm.id, alarmAt: next, hadSuccessfulCheck: false);

    // Rule 2: a committed ring whose time has passed (and isn't sounding — see
    // Rule 1) already fired. Record it as "rang" instead of re-deciding with
    // newer wind. Without this, an app-open after the ring — the normal iOS
    // path, where no exact T-0 check runs — could log a ring as "skipped".
    if (state.ringScheduled && t.isAfter(next)) {
      await store.addHistory(HistoryRecord(
        alarmId: alarm.id,
        at: next,
        outcome: CheckOutcome.rang,
        courtSpeedKmh: state.ringCourtSpeedKmh,
        rawGustKmh: state.ringRawGustKmh,
        courtSpeedLimitKmh: alarm.courtSpeedLimitKmh,
        rawGustLimitKmh: alarm.thresholds.rawGustLimit,
        volume: state.ringVolume,
      ));
      await store.clearCheckState(alarm.id);
      return;
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
      if (decision.shouldRing) {
        // Not sounding here (Rule 1 returned above), so re-scheduling is safe.
        // A retry that succeeds just after T rings late (never in the past).
        final ringAt =
            next.isAfter(t) ? next : t.add(const Duration(seconds: 10));
        await scheduler.scheduleRing(
          id: alarm.id,
          at: ringAt,
          title: 'Nivaat · ${court.name}',
          body: '${fmtWindGust(
            decision.sample.courtSpeedKmh,
            decision.thresholds.courtSpeedLimitKmh,
            decision.sample.rawGustKmh,
            decision.thresholds.rawGustLimit,
          )} — play! 🏸',
          volume: decision.volume,
        );
        state = state.copyWith(
          ringScheduled: true,
          ringCourtSpeedKmh: decision.sample.courtSpeedKmh,
          ringRawGustKmh: decision.sample.rawGustKmh,
          ringVolume: decision.volume,
        );
      } else {
        // Not sounding here either, so cancelling the provisional ring is safe.
        await scheduler.cancel(alarm.id);
        state = state.copyWith(ringScheduled: false);
      }
    }

    final hadSuccess = state.hadSuccessfulCheck || decision != null;
    state = state.copyWith(hadSuccessfulCheck: hadSuccess);
    await store.saveCheckState(state);

    final nextCheck =
        CheckCascade.nextCheckTime(t, next, hadSuccessfulCheck: hadSuccess);

    // Final decision moment: at/after T with a result, or cascade exhausted.
    // The grace covers scheduler jitter only; it must stay smaller than the
    // gap between creating an alarm and its T, or the skip card fires early.
    final atOrPastAlarm =
        !t.isBefore(next.subtract(const Duration(seconds: 5)));
    if (atOrPastAlarm && decision != null) {
      final record = HistoryRecord(
        alarmId: alarm.id,
        at: next,
        outcome: switch (decision.verdict) {
          WindVerdict.ring => CheckOutcome.rang,
          WindVerdict.tooWindy => CheckOutcome.skippedWindy,
          WindVerdict.tooGusty => CheckOutcome.skippedGusty,
        },
        courtSpeedKmh: decision.sample.courtSpeedKmh,
        rawGustKmh: decision.sample.rawGustKmh,
        courtSpeedLimitKmh: decision.thresholds.courtSpeedLimitKmh,
        rawGustLimitKmh: decision.thresholds.rawGustLimit,
        volume: decision.shouldRing ? decision.volume : null,
      );
      await store.addHistory(record);
      await store.clearCheckState(alarm.id);
      if (!decision.shouldRing) await _notifySkip(record, court.name);
    } else if (atOrPastAlarm && nextCheck == null) {
      // Every check of this occurrence failed and the retry cap has passed.
      final record = HistoryRecord(
        alarmId: alarm.id,
        at: next,
        outcome: CheckOutcome.skippedNoData,
        courtSpeedLimitKmh: alarm.courtSpeedLimitKmh,
        rawGustLimitKmh: alarm.thresholds.rawGustLimit,
      );
      await store.addHistory(record);
      await store.clearCheckState(alarm.id);
      await _notifySkip(record, court.name);
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
