import 'dart:ui';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

import 'check_scheduler.dart';
import 'skip_notifier.dart';
import 'ui_resync.dart';

/// User-selected alarm tone; null = default Court Call. Loaded by
/// [NivaatEngine.standard], so every entrypoint — app start, the Android
/// AlarmManager isolate, the iOS Workmanager isolate — sees it before any
/// ring is scheduled.
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

/// The note for a heads-up snapshot row (`watchedUntil` set): "watching until
/// …" while the retry window still runs — the same promise the heads-up
/// card makes — then "watched until …" forever, marking it as the
/// at-T moment whose final outcome is its own later row. Null for final rows.
///
/// The deadline uses [fmtCheckTime] against the alarm (`at`) — same rule as
/// the check time — so a late-night alarm whose +30m cap crosses midnight
/// reads `watched until 23 Jul 00:19`, never a bare `00:19` (2026-07-23).
String? nivaatStillWatchingNote(HistoryRecord record, {DateTime? now}) {
  final until = record.watchedUntil;
  if (until == null) return null;
  final t = now ?? DateTime.now();
  final when = fmtCheckTime(until, record.at);
  return t.isBefore(until)
      ? 'watching until $when'
      : 'watched until $when';
}

/// Snapshot still inside its +30m window whose occurrence is **still being
/// checked** — used by the home cue and its dismiss timer (MESSAGES.md N21).
///
/// Cleared when: the cap passes; a **final** row exists for the same
/// `alarmId + at` (late ring / cap skip); that alarm is gone / disabled; or
/// live [CheckState] no longer targets that occurrence (toggle-off discards
/// it; toggle-on re-arms *tomorrow* — without this, the cue would lie until
/// the cap). With several open windows, returns the **soonest** cap.
HistoryRecord? nivaatSoonestOpenWatch(
  Iterable<HistoryRecord> history, {
  required Iterable<NivaatAlarm> alarms,
  required Iterable<CheckState> checkStates,
  DateTime? now,
}) {
  final t = now ?? DateTime.now();
  final liveIds = {for (final a in alarms) if (a.enabled) a.id};
  final finalized = {
    for (final h in history)
      if (h.watchedUntil == null) _watchKey(h.alarmId, h.at)
  };
  final inFlight = {
    for (final s in checkStates) _watchKey(s.alarmId, s.alarmAt)
  };
  HistoryRecord? soonest;
  for (final h in history) {
    final until = h.watchedUntil;
    if (until == null || !t.isBefore(until)) continue;
    if (!liveIds.contains(h.alarmId)) continue;
    if (finalized.contains(_watchKey(h.alarmId, h.at))) continue;
    if (!inFlight.contains(_watchKey(h.alarmId, h.at))) continue;
    final best = soonest?.watchedUntil;
    if (best == null || until.isBefore(best)) soonest = h;
  }
  return soonest;
}

String _watchKey(int alarmId, DateTime at) =>
    '$alarmId@${at.millisecondsSinceEpoch}';

/// Home cue text for [nivaatSoonestOpenWatch], or null when home stays clean.
/// The UI prefixes this with a wind-accent live ● (not a word).
String? nivaatHomeWatchingLine(
  Iterable<HistoryRecord> history, {
  required Iterable<NivaatAlarm> alarms,
  required Iterable<CheckState> checkStates,
  DateTime? now,
}) {
  final open = nivaatSoonestOpenWatch(
    history,
    alarms: alarms,
    checkStates: checkStates,
    now: now,
  );
  if (open == null) return null;
  return 'Still checking wind · until '
      '${fmtCheckTime(open.watchedUntil!, open.at)}';
}

/// Background entrypoint for Android AlarmManager wakeups. Runs in a fresh
/// isolate: rebuild the whole graph, evaluate every alarm, reschedule.
@pragma('vm:entry-point')
Future<void> nivaatBackgroundCheck() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final engine = await NivaatEngine.standard();
  await engine.evaluateAll();
  pingNivaatUiResync();
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

  static Future<NivaatEngine> standard() async {
    final store = NivaatStore();
    // Here, not per-entrypoint: a background isolate that forgets this line
    // would schedule rings with the default tone instead of the user's pick
    // (exactly the bug the iOS Workmanager entrypoint had).
    nivaatSelectedSound = await store.loadSoundPath();
    final AlarmScheduler scheduler = kScreenshotHarness
        ? const NoOpAlarmScheduler()
        : await createAlarmScheduler(
            soundAssetForVolume: nivaatSoundForVolume,
            tintColor: '#6FB7EC',
          );
    return NivaatEngine(
      store: store,
      scheduler: scheduler,
      api: OpenMeteo(),
      checks:
          CheckScheduler.forPlatform(androidEntrypoint: nivaatBackgroundCheck),
      notifier: SkipNotifier(),
    );
  }

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

  /// One state-touching job per alarm at a time. Two overlapping runs of the
  /// same alarm — the app-open resync racing a toggle/edit made moments later,
  /// with the first run parked on its wind fetch — would both read the
  /// persisted cascade state before either writes it: duplicate history
  /// rows/cards, or an edit's freshly cleared state re-saved by the older run.
  /// Queuing per alarm id makes the later job see the earlier one's writes.
  /// (Same-isolate only; an overlap with a background isolate remains possible
  /// and worst-cases at a re-written row — upsertHistory converges both writes
  /// onto the same occurrence row, and the next check self-corrects.)
  final Map<int, Future<void>> _evalQueue = {};

  Future<void> _enqueue(int alarmId, Future<void> Function() job) {
    final tail = _evalQueue[alarmId] ?? Future<void>.value();
    final run = tail.then((_) => job());
    // Park an error-swallowing copy so one failed run can't jam the lane;
    // the caller still sees the failure through `run`.
    _evalQueue[alarmId] = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> evaluateAlarm(
    NivaatAlarm alarm,
    List<SavedLocation> courts, {
    DateTime? now,
  }) =>
      _enqueue(alarm.id, () => _evaluate(alarm, courts, now: now));

  /// The controller's edit path: an edit invalidates the in-flight occurrence,
  /// but its state may hold the only evidence of a ring that already FIRED —
  /// blind-clearing here was how an edited alarm's ring vanished from history
  /// for good (2026-07-19 device testing). Finalise that ring into history,
  /// then drop the state. Pass the PRE-edit alarm: the fired ring belongs to
  /// its old court/thresholds.
  Future<void> discardOccurrence(NivaatAlarm alarm, {DateTime? now}) =>
      _enqueue(alarm.id, () async {
        final t = now ?? DateTime.now();
        final stored = await store.loadCheckState(alarm.id);
        if (stored != null &&
            stored.ringScheduled &&
            t.isAfter(stored.alarmAt)) {
          await store.upsertHistory(_rangRecord(alarm, stored));
        }
        await store.clearCheckState(alarm.id);
      });

  Future<void> _evaluate(
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
      // A committed ring that already fired must reach history even while its
      // alarm is being disabled/deleted — clearing first silently dropped it
      // ("rang but never showed up in history", 2026-07-19 device testing).
      //
      // Only when the COURT survives, though: that bug was about the alarm
      // going away (`next == null`), and a row whose court is gone is an
      // orphan no screen can render (2026-07-22).
      if (court != null &&
          stored != null &&
          stored.ringScheduled &&
          t.isAfter(stored.alarmAt)) {
        await store.upsertHistory(_rangRecord(alarm, stored));
      }
      await store.clearCheckState(alarm.id);
      return;
    }

    // Rule 1: a ring physically sounding IS the decision, made real — never
    // cancel it or relabel it on a resync/check. (Disabled alarms fall through
    // above so an explicit delete/toggle-off can still stop a ring.) The pre-T
    // ladder — not a split-second T-0 cancel — is what keeps a windy morning
    // from ringing; once it's audible, it stays. This is what makes "open the
    // app during a ring" safe on both platforms.
    if (alarm.enabled && await scheduler.isRinging(alarm.id)) {
      // Audible = final, so the "rang" row is written HERE — the first moment
      // the app can see the ring — not whenever the user gets around to
      // stopping it (history must show the ring while it still sounds).
      // Idempotent: the cleared state stops a second mid-ring pass relogging.
      if (stored != null && stored.ringScheduled) {
        await store.upsertHistory(_rangRecord(alarm, stored));
        await store.clearCheckState(alarm.id);
      }
      // Keep the cascade alive without touching the scheduler (cancelling or
      // re-setting the ring's id would silence it): checks live in their own
      // id space, so book the NEXT occurrence's first rung. Without this, the
      // T-0 check ending here left Android with no future wakeup at all —
      // checks only ever reschedule themselves.
      final upcoming = alarm.nextOccurrence(t);
      if (upcoming != null) {
        final firstRung = CheckCascade.nextCheckTime(t, upcoming);
        if (firstRung != null) await checks.scheduleCheck(alarm.id, firstRung);
      }
      return;
    }

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
        await store.upsertHistory(_rangRecord(alarm, stored));
      } else {
        final record = _skipRecord(alarm, stored.alarmAt, stored);
        await store.upsertHistory(record);
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
      await store.upsertHistory(_rangRecord(alarm, state));
      await store.clearCheckState(alarm.id);
      return _rollOn(alarm, courts, t, next);
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
          title: nivaatNotificationTitle(court.name, next, kNivaatRing),
          // The numbers that won, and when they were read — `t` is the same
          // instant stored as `lastCheckAt` below, so the ring card and its
          // history row quote one check time (MESSAGES.md N1).
          body: '${fmtWindGust(
            decision.sample.courtSpeedKmh,
            decision.thresholds.courtSpeedLimitKmh,
            decision.sample.rawGustKmh,
            decision.thresholds.rawGustLimit,
          )}${nivaatCheckedNote(t, next)}',
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
      await store.upsertHistory(HistoryRecord(
        alarmId: alarm.id,
        courtId: alarm.courtId,
        at: next,
        // The check behind this ring is the one that just ran now (`t`) — on
        // time at T, or a later retry-until-calm check. Recorded so history
        // can show "checked 06:07" when that differs from the 06:00 alarm.
        // A late ring APPENDS this row; the heads-up snapshot row stays too
        // (append-only log — both moments really happened).
        checkedAt: t,
        outcome: CheckOutcome.rang,
        courtSpeedKmh: decision.sample.courtSpeedKmh,
        rawGustKmh: decision.sample.rawGustKmh,
        courtSpeedLimitKmh: decision.thresholds.courtSpeedLimitKmh,
        rawGustLimitKmh: decision.thresholds.rawGustLimit,
        volume: decision.volume,
      ));
      await store.clearCheckState(alarm.id);
      return _rollOn(alarm, courts, t, next);
    }

    // At/after T but NOT ringing (windy/gusty/no-data): the skip is provisional.
    // Keep re-checking every minute until the +30m cap, ringing late if the wind
    // drops. Only at the cap do we finalise the skip and fire its card — using
    // the last KNOWN reason (state), so a network blip exactly at the cap still
    // reports "windy" rather than "couldn't check".
    if (atOrPastAlarm && nextCheck == null) {
      final record = _skipRecord(alarm, next, state);
      await store.upsertHistory(record);
      await store.clearCheckState(alarm.id);
      await _notifySkip(record, court.name);
      return _rollOn(alarm, courts, t, next);
    }

    // Before T (ladder), or a provisional post-T skip → keep the cascade going.
    // On the first at/after-T skip, post the "still checking" heads-up (once)
    // AND its permanent history row: the at-T moment is in the app from the
    // moment it happens (user decision 2026-07-19), as its own entry — the
    // final outcome (cap skip / late ring) will be a separate later row, so
    // dismissing the heads-up notification never hides what happened
    // (append-only log, 2026-07-20). Retries touch neither: this row is the
    // snapshot of what the heads-up said.
    if (atOrPastAlarm && !state.extendedCheckShown) {
      final until =
          next.add(const Duration(minutes: CheckCascade.retryCapMinutesAfter));
      final snapshot = _skipRecord(alarm, next, state, watchedUntil: until);
      await _notifyExtendedCheck(snapshot, court.name, until);
      await store.upsertHistory(snapshot);
      state = state.copyWith(extendedCheckShown: true);
    }
    await store.saveCheckState(state);
    if (nextCheck != null) await checks.scheduleCheck(alarm.id, nextCheck);
  }

  /// The "rang" row for a committed ring, built from its persisted [state] —
  /// used everywhere a ring is finalised after the fact (audible ring, past
  /// ring on app open, stale occurrence, alarm being edited/disabled).
  HistoryRecord _rangRecord(NivaatAlarm alarm, CheckState state) =>
      HistoryRecord(
        alarmId: alarm.id,
        courtId: alarm.courtId,
        at: state.alarmAt,
        checkedAt: state.lastCheckAt,
        outcome: CheckOutcome.rang,
        courtSpeedKmh: state.ringCourtSpeedKmh,
        rawGustKmh: state.ringRawGustKmh,
        courtSpeedLimitKmh: alarm.courtSpeedLimitKmh,
        rawGustLimitKmh: alarm.thresholds.rawGustLimit,
        volume: state.ringVolume,
      );

  /// After finalising [closed], immediately evaluate the alarm's NEXT
  /// occurrence in the same pass: this very open/wakeup pre-arms it (iOS may
  /// never get a background slot before T) and books its first check (on
  /// Android nothing else would — checks only reschedule themselves, so
  /// returning here left the cascade dead until the next manual app open).
  /// Skipped when the "next" occurrence is still [closed] itself (a T-0 check
  /// running inside the pre-T grace), which also guarantees the recursion
  /// terminates: a genuinely future occurrence can't finalise again.
  Future<void> _rollOn(
    NivaatAlarm alarm,
    List<SavedLocation> courts,
    DateTime t,
    DateTime closed,
  ) {
    if (alarm.nextOccurrence(t) == closed) return Future.value();
    return _evaluate(alarm, courts, now: t);
  }

  /// The skip record for [alarm]'s occurrence [at], from the last known skip
  /// reading in [state] (windy/gusty with numbers), or "no data" if no check
  /// ever read a skip-worthy wind. `checkedAt` is [state.lastCheckAt] for a
  /// windy/gusty skip (the reading behind it) but [state.lastAttemptAt] for a
  /// no-data skip (its last try — there was no successful reading).
  /// [watchedUntil] marks the heads-up snapshot row (see HistoryRecord).
  HistoryRecord _skipRecord(
    NivaatAlarm alarm,
    DateTime at,
    CheckState state, {
    DateTime? watchedUntil,
  }) {
    if (state.skipCourtSpeedKmh == null) {
      return HistoryRecord(
        alarmId: alarm.id,
        courtId: alarm.courtId,
        at: at,
        checkedAt: state.lastAttemptAt,
        watchedUntil: watchedUntil,
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
      watchedUntil: watchedUntil,
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
