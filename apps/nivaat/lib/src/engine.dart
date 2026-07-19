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
  // The ramp spans 75-100% (SPEC.md), so the variants are 5%-stepped over
  // that band: nivaat_ring_{75,80,85,90,95,100}.wav.
  final pct = ((volume * 20).round() * 5).clamp(75, 100);
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

    // An occurrence we're no longer tracking as current (the app first ran past
    // its 30-min retry window, so `next` has already rolled on) still needs
    // finalising — the app may never have run during [T, T+30]. A committed
    // ring fired → log "rang"; anything else (windy / gusty / no-data) is a
    // skip → log it AND post its one card, so a late first-open never silently
    // drops the occurrence. (Mutually exclusive with Rule 2, the in-window case
    // where next == stored.alarmAt.) Without this, iOS — no exact wakeups —
    // loses the whole occurrence when first opened >30 min after T.
    if (stored != null &&
        stored.alarmAt != next &&
        t.isAfter(stored.alarmAt)) {
      if (stored.ringScheduled) {
        await store.addHistory(HistoryRecord(
          alarmId: alarm.id,
          courtId: alarm.courtId,
          at: stored.alarmAt,
          checkedAt: stored.lastCheckAt,
          outcome: CheckOutcome.rang,
          courtSpeedKmh: stored.ringCourtSpeedKmh,
          rawGustKmh: stored.ringRawGustKmh,
          courtSpeedLimitKmh: alarm.courtSpeedLimitKmh,
          rawGustLimitKmh: alarm.thresholds.rawGustLimit,
          volume: stored.ringVolume,
        ));
      } else {
        final record = _skipRecord(alarm, stored.alarmAt, stored);
        await store.addHistory(record);
        await _notifySkip(record, court.name);
      }
      await store.clearCheckState(alarm.id);
    }

    // Cascade state is per-occurrence.
    var state = (stored != null && stored.alarmAt == next)
        ? stored
        : CheckState(alarmId: alarm.id, alarmAt: next);

    // Rule 2: a committed ring whose time has passed (and isn't sounding — see
    // Rule 1) already fired. Record it as "rang" instead of re-deciding with
    // newer wind. Without this, an app-open after the ring — the normal iOS
    // path, where no exact T-0 check runs — could log a ring as "skipped".
    if (state.ringScheduled && t.isAfter(next)) {
      await store.addHistory(HistoryRecord(
        alarmId: alarm.id,
        courtId: alarm.courtId,
        at: next,
        checkedAt: state.lastCheckAt,
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

    // Every check counts as an attempt (this timestamps a no-data skip's
    // "last tried"); a successful one also updates lastCheckAt below.
    state = state.copyWith(lastAttemptAt: t);

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
          title: 'Nivaat ${fmtClock(next)} · ${court.name}',
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
          lastCheckAt: t,
        );
      } else {
        // Not sounding here either, so cancelling the provisional ring is safe.
        // Remember the reading behind this skip (kept across later no-data
        // retries) so the final card can report the real reason.
        await scheduler.cancel(alarm.id);
        state = state.copyWith(
          ringScheduled: false,
          skipCourtSpeedKmh: decision.sample.courtSpeedKmh,
          skipRawGustKmh: decision.sample.rawGustKmh,
          skipGusty: decision.verdict == WindVerdict.tooGusty,
          lastCheckAt: t,
        );
      }
    }

    final nextCheck = CheckCascade.nextCheckTime(t, next);
    // The grace covers scheduler jitter only; it must stay smaller than the gap
    // between creating an alarm and its T, or a skip would finalise early.
    final atOrPastAlarm =
        !t.isBefore(next.subtract(const Duration(seconds: 5)));

    // At/after T and ringing → final; we never retry a ring. A leftover "still
    // checking" heads-up is left in place — the ring itself is the update.
    if (atOrPastAlarm && decision != null && decision.shouldRing) {
      await store.addHistory(HistoryRecord(
        alarmId: alarm.id,
        courtId: alarm.courtId,
        at: next,
        // The check behind this ring is the one that just ran now (`t`) — on
        // time at T, or a later retry-until-calm check. Recorded so history
        // can show "checked 06:07" when that differs from the 06:00 alarm.
        checkedAt: t,
        outcome: CheckOutcome.rang,
        courtSpeedKmh: decision.sample.courtSpeedKmh,
        rawGustKmh: decision.sample.rawGustKmh,
        courtSpeedLimitKmh: decision.thresholds.courtSpeedLimitKmh,
        rawGustLimitKmh: decision.thresholds.rawGustLimit,
        volume: decision.volume,
      ));
      await store.clearCheckState(alarm.id);
      return;
    }

    // At/after T but NOT ringing (windy/gusty/no-data): the skip is provisional.
    // Keep re-checking every minute until the +30m cap, ringing late if the wind
    // drops. Only at the cap do we finalise the skip and fire its card — using
    // the last KNOWN reason (state), so a network blip exactly at the cap still
    // reports "windy" rather than "couldn't check".
    if (atOrPastAlarm && nextCheck == null) {
      final record = _skipRecord(alarm, next, state);
      await store.addHistory(record);
      await store.clearCheckState(alarm.id);
      await _notifySkip(record, court.name);
      return;
    }

    // Before T (ladder), or a provisional post-T skip → keep the cascade going.
    // On the first at/after-T skip, post the "still checking" heads-up (once).
    if (atOrPastAlarm && !state.extendedCheckShown) {
      final until =
          next.add(const Duration(minutes: CheckCascade.retryCapMinutesAfter));
      await _notifyExtendedCheck(
          _skipRecord(alarm, next, state), court.name, until);
      state = state.copyWith(extendedCheckShown: true);
    }
    await store.saveCheckState(state);
    if (nextCheck != null) await checks.scheduleCheck(alarm.id, nextCheck);
  }

  /// The skip record for [alarm]'s occurrence [at], from the last known skip
  /// reading in [state] (windy/gusty with numbers), or "no data" if no check
  /// ever read a skip-worthy wind. `checkedAt` is [state.lastCheckAt] for a
  /// windy/gusty skip (the reading behind it) but [state.lastAttemptAt] for a
  /// no-data skip (its last try — there was no successful reading).
  HistoryRecord _skipRecord(NivaatAlarm alarm, DateTime at, CheckState state) {
    if (state.skipCourtSpeedKmh == null) {
      return HistoryRecord(
        alarmId: alarm.id,
        courtId: alarm.courtId,
        at: at,
        checkedAt: state.lastAttemptAt,
        outcome: CheckOutcome.skippedNoData,
        courtSpeedLimitKmh: alarm.courtSpeedLimitKmh,
        rawGustLimitKmh: alarm.thresholds.rawGustLimit,
      );
    }
    return HistoryRecord(
      alarmId: alarm.id,
      courtId: alarm.courtId,
      at: at,
      checkedAt: state.lastCheckAt,
      outcome: state.skipGusty
          ? CheckOutcome.skippedGusty
          : CheckOutcome.skippedWindy,
      courtSpeedKmh: state.skipCourtSpeedKmh,
      rawGustKmh: state.skipRawGustKmh,
      courtSpeedLimitKmh: alarm.courtSpeedLimitKmh,
      rawGustLimitKmh: alarm.thresholds.rawGustLimit,
    );
  }

  Future<void> _notifyExtendedCheck(
      HistoryRecord record, String courtName, DateTime until) async {
    try {
      await notifier?.showExtendedCheck(record, courtName, until);
    } on Exception {
      // A notification failure must never break the cascade.
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
