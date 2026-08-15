import 'dart:ui';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

import 'check_scheduler.dart';
import 'ids.dart';
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
  // Snap to the nearest of core's [windVolumeSteps] (loudest first) rather
  // than switching on the exact values: any volume in 0-1 then resolves to a
  // file that ships, and changing the ramp is a one-line edit in core plus a
  // render — no midpoints to keep in sync here. Ties go to the louder step,
  // matching volumeForWind's own boundaries.
  var step = windVolumeSteps.last;
  for (var i = 0; i < windVolumeSteps.length - 1; i++) {
    if (volume >= (windVolumeSteps[i] + windVolumeSteps[i + 1]) / 2) {
      step = windVolumeSteps[i];
      break;
    }
  }
  // 100% IS the master — no byte-identical `_100` copy ships (SPEC.md).
  final pct = (step * 100).round();
  return pct == 100 ? nivaatDefaultSound : 'assets/sounds/nivaat_ring_$pct.wav';
}

/// A history row's headline: the outcome, plus the numbers that caused it.
///
/// Every other reader on a [HistoryRecord] degrades rather than assuming an
/// optional field is there — [HistoryRecord.whenChecked] falls back to `at`,
/// [HistoryRecord.windGustSummary] drops to a reduced string and then to ''.
/// This one now does too: `volume` is written on every "rang" row the engine
/// produces, but the field is optional, and force-unwrapping it meant one row
/// without it would take the whole sheet down — permanently, since history is
/// persisted. That is the worst screen to lose: it is the one that explains a
/// morning the alarm didn't ring (2026-07-26).
///
/// A cancelled row is the exception to all of it: it carries no reason of its
/// own — you ended the morning, the wind didn't — so it reads bare, and its
/// numbers live on the still-checking row directly beside it.
String nivaatHistoryLine(HistoryRecord record) {
  if (record.kind == HistoryKind.cancelled) return kNivaatCancelled;
  final volume = record.volume;
  // Ring disposition is a SEPARATE axis from the wind outcome, and when it is
  // set it is the more specific answer: `outcome` says what the app decided
  // about the wind, `ringDisposition` says what became of the ring it decided
  // on. A dropped ring still carries `CheckOutcome.rang` — the wind really did
  // say ring — so reading the wind axis first would print `Rang` for a morning
  // that never made a sound.
  final disposition = record.ringDisposition;
  if (disposition != null) {
    final head = switch (disposition) {
      RingDisposition.missed => kNivaatMissed,
      RingDisposition.unknown => kNivaatUnknownRing,
      RingDisposition.rang => volume == null
          ? 'Rang'
          : 'Rang (vol. ${(volume * 100).round()}%)',
    };
    final summary = record.windGustSummary;
    return summary.isEmpty ? head : '$head · $summary';
  }
  // The status word mirrors the card's title, so a row and the card it was
  // written for read the same. The reason rides in the parenthetical, exactly
  // as it already did for `Skipped (gusty)`.
  final status = record.kind == HistoryKind.stillChecking
      ? kNivaatStillChecking
      : 'Skipped';
  final head = switch (record.outcome) {
    // "vol." so the number can't read as a score — the rest of the line is
    // label-value too (2026-07-22). Only an outcome row can be a ring.
    CheckOutcome.rang => volume == null
        ? 'Rang'
        : 'Rang (vol. ${(volume * 100).round()}%)',
    // N5's bare "Skipped" means windy — locked 2026-07-22, don't add "(windy)".
    CheckOutcome.skippedWindy => status,
    CheckOutcome.skippedGusty => '$status (gusty)',
    CheckOutcome.skippedNoData => '$status (no data)',
  };
  // N7 quotes no numbers at all: a no-data row means nothing was measured, so
  // any readings on one would contradict its own label. A row that simply lost
  // its readings degrades to the same empty summary — and either way the " · "
  // that joins it has to go too, or the line ends in a dangling separator.
  final summary = record.outcome == CheckOutcome.skippedNoData
      ? ''
      : record.windGustSummary;
  return summary.isEmpty ? head : '$head · $summary';
}

/// The trailing note on a history row's sub, or null when it has none
/// (MESSAGES.md N10).
///
/// Rows are immutable, so this is pure formatting of what was already
/// recorded — nothing here depends on "now", and nothing ages:
///
/// * **still-checking** → ` · watching until 06:30`. Present tense forever,
///   because that is what the card said at that moment. How far the morning
///   actually got is the next row's business.
/// * **outcome** → ` · watched until 06:30`, but only when checking reached
///   past the last reading. Almost always they are the same instant and this
///   is empty; when they differ, the final attempt failed to reach the
///   network, and this is the one thing separating "we gave up at 06:29" from
///   "we tried at 06:30 and got nothing".
/// * **cancelled** → ` · stopped 06:05`.
///
/// Times use [fmtCheckTime] against the alarm, so a window whose cap crosses
/// midnight reads `watching until 23 Jul 00:19`, never a bare `00:19`.
String? nivaatHistoryNote(HistoryRecord record) => switch (record.kind) {
      HistoryKind.stillChecking => record.watchedUntil == null
          ? null
          : nivaatWatchingUntilPhrase(record.watchedUntil!, record.at),
      HistoryKind.cancelled => record.checkingEndedAt == null
          ? null
          : nivaatStoppedPhrase(record.checkingEndedAt!, record.at),
      HistoryKind.outcome => nivaatOutlastedLastReading(record)
          ? nivaatWatchedUntilPhrase(record.checkingEndedAt!, record.at)
          : null,
    };

/// A history row's second line: where and when, how fresh the reading was,
/// and whatever [nivaatHistoryNote] has to add (MESSAGES.md N4–N7, N10).
///
/// Lives here rather than inside the sheet because a string built inside a
/// widget is an untested string — the same reason [nivaatHistoryLine] moved
/// out. It bit immediately: the sheet was still writing `checked` after the
/// whole app moved to `last checked`, and only a test that rebuilt this line
/// by hand was passing (2026-07-26).
///
/// A cancelled row reads bare — `Society Court · 18 Jul · 06:00 · stopped
/// 06:05`, with no freshness clause (Samyak, 2026-07-26). Its line already
/// drops the reason and the numbers, and the still-checking row it always sits
/// beside carries both: a cancelled row can only exist where one was written.
/// The CARD keeps the full evidence because it has no neighbour to lean on —
/// that asymmetry is the decision, not an oversight.
///
/// [courtName] is the caller's lookup, and it is **non-null** (Samyak,
/// 2026-08-15): every load prunes rows whose court has gone
/// (`NivaatController._loadHistory`), so the sheet can only render rows whose
/// court is still there. It used to degrade to the word `court removed`, which
/// nothing could reach — and neither app has shipped, so a throw here is a bug
/// report where the fallback was a wrong word nobody would ever query.
String nivaatHistorySub(HistoryRecord record, String courtName) {
  final note = nivaatHistoryNote(record);
  final checked = record.kind == HistoryKind.cancelled
      ? ''
      : nivaatCheckedNote(
          record.whenChecked,
          record.at,
          tried: record.outcome == CheckOutcome.skippedNoData,
        );
  return '$courtName · '
      '${fmtShortDate(record.at)} · ${fmtClock(record.at)}$checked'
      '${note == null ? '' : ' · $note'}';
}

/// Does saving [next] over [previous] kill an in-flight occurrence?
///
/// **Continue** (false): wind limit, Keep checking widen/shrink, weekdays that
/// still include the in-flight day (add-only or drop-other-days).
/// **Abandon** (true): time, court, drop the in-flight weekday, disable.
bool nivaatEditAbandonsInFlight(
  NivaatAlarm previous,
  NivaatAlarm next, {
  CheckState? state,
  DateTime? now,
}) {
  if (!next.enabled && previous.enabled) return true;
  if (previous.hour != next.hour || previous.minute != next.minute) {
    return true;
  }
  if (previous.courtId != next.courtId) return true;
  final t = now ?? DateTime.now();
  if (state != null && nivaatOccurrenceInFlight(previous, state, t)) {
    return !next.weekdays.contains(state.alarmAt.weekday);
  }
  return false;
}

/// The newest row of each occurrence, keyed `alarmId@at`.
///
/// Rows are immutable and a morning writes several, so "what is this morning
/// doing now?" is always a question about its LAST row — the highest
/// [HistoryRecord.pushSeq] (2026-07-26).
///
/// A tie keeps the row seen FIRST, and callers pass history newest-first (the
/// order [NivaatStore.loadHistory] returns), so the newer row wins. **Nothing
/// the store can hand over actually ties** — `upsertHistory` keys on
/// `alarmId + at + pushSeq` and converges same-numbered writes onto one row —
/// so this is a determinism rule for a function that takes any iterable, not a
/// case with a story behind it. (It used to have one: rows predating push
/// numbers all carried 0. Those can no longer be read at all — `fromJson`
/// requires `pushSeq` — so the rule outlived its reason and is kept for the
/// obvious one.) Resolving a tie the other way reads a finished morning as an
/// open window, and home promises checking that already stopped.
Map<String, HistoryRecord> nivaatLatestRowPerOccurrence(
  Iterable<HistoryRecord> history,
) {
  final latest = <String, HistoryRecord>{};
  for (final h in history) {
    final key = _watchKey(h.alarmId, h.at);
    final seen = latest[key];
    if (seen == null || h.pushSeq > seen.pushSeq) latest[key] = h;
  }
  return latest;
}

/// The open retry window whose cap comes soonest — the home cue and its
/// dismiss timer (MESSAGES.md N11). Null when nothing is being checked.
///
/// A window is open when the occurrence's **newest** row is still-checking
/// (an outcome or cancelled row means the morning is done), its cap is still
/// ahead, the alarm is present and enabled, and live [CheckState] still
/// targets that occurrence. That last clause is what stops a toggle-off then
/// toggle-on from reviving today's dead retries — toggling on re-arms
/// *tomorrow*, so the cue would otherwise lie until the cap.
HistoryRecord? nivaatSoonestOpenWatch(
  Iterable<HistoryRecord> history, {
  required Iterable<NivaatAlarm> alarms,
  required Iterable<CheckState> checkStates,
  DateTime? now,
}) {
  final t = now ?? DateTime.now();
  final liveIds = {for (final a in alarms) if (a.enabled) a.id};
  final inFlight = {
    for (final s in checkStates) _watchKey(s.alarmId, s.alarmAt)
  };
  HistoryRecord? soonest;
  for (final entry in nivaatLatestRowPerOccurrence(history).entries) {
    final h = entry.value;
    if (h.kind != HistoryKind.stillChecking) continue;
    final until = h.watchedUntil;
    if (until == null || !t.isBefore(until)) continue;
    if (!liveIds.contains(h.alarmId)) continue;
    if (!inFlight.contains(entry.key)) continue;
    final best = soonest?.watchedUntil;
    if (best == null || until.isBefore(best)) soonest = h;
  }
  return soonest;
}

String _watchKey(int alarmId, DateTime at) =>
    '$alarmId@${at.millisecondsSinceEpoch}';

/// Home alarm-list sub (MESSAGES.md N15). Non-default retry windows surface
/// as `· +1m` / `· +60m` so a short test window is visible without opening
/// the editor; the default 30 stays silent (the common case).
///
/// [court] is **non-null** (Samyak, 2026-08-15): deleting a court deletes its
/// alarms in the same synchronous step (N20), and only the UI isolate ever
/// writes the alarm list, so no background check can leave an alarm behind its
/// court. The old `court removed` fallback was a word no state could produce.
String nivaatAlarmListSub(NivaatAlarm alarm, SavedLocation court) {
  final base =
      '${fmtWeekdays(alarm.weekdays)} · ${court.name} '
      '· ≤${alarm.courtSpeedLimitKmh} km/h';
  if (alarm.retryMinutesAfter == CheckCascade.retryCapMinutesAfter) {
    return base;
  }
  return '$base · +${alarm.retryMinutesAfter}m';
}

/// "in 1h 00m" until [t], minute-truncated (MESSAGES.md N15). Past a day it
/// switches to "in 5d 04h" — [fmtDuration] alone would say "in 120h 00m", and
/// a multi-day gap is routine here: a weekend-only alarm is five days out on
/// a Monday. (Arunoday's `IN 7H 22M` never needed this — its wake is daily.)
///
/// Day form truncates to the hour, so 24h30m reads "in 1d 00h" — each form
/// drops what's below its smallest unit, and at a day's range half an hour is
/// noise. The seam is exact: 23h59m still reads "in 23h 59m".
///
/// Sentence case — Nivaat's home/editor meta is quiet body text, not Arunoday's
/// ALL-CAPS label strip. Empty when [t] is null or already past.
String nivaatInLabel(DateTime? t, {DateTime? now}) {
  if (t == null) return '';
  final n = now ?? DateTime.now();
  final mins = DateTime(t.year, t.month, t.day, t.hour, t.minute)
      .difference(DateTime(n.year, n.month, n.day, n.hour, n.minute))
      .inMinutes;
  if (mins < 0) return '';
  const day = 24 * 60;
  if (mins < day) return 'in ${fmtDuration(mins.toDouble())}';
  return 'in ${mins ~/ day}d '
      '${((mins % day) ~/ 60).toString().padLeft(2, '0')}h';
}

/// How early a wake may arrive and still count as "the alarm time has come".
///
/// **Zero, on purpose** (Samyak, 2026-07-26). Android AlarmManager and iOS
/// BGTasks both fire at or after the requested instant, never before, so there
/// is nothing to forgive — and a number with no reason behind it is worse than
/// none. If a backwards clock correction ever does land a check a hair early,
/// it simply books another for T and decides there: one extra wake, never a
/// missed alarm. It cannot be widened to absorb LATE wakes either, because the
/// same value decides when a skip may finalise — at 45s a check meant for
/// 05:59 would count as 06:00 and post "still checking" before the alarm was
/// even due.
const Duration kNivaatWakeGrace = Duration.zero;

/// The last moment a late wake still belongs to the occurrence whose cap it
/// was booked for, rather than rolling on to tomorrow.
///
/// **The whole of the cap's minute** (Samyak, 2026-07-26) — not a chosen number
/// of seconds. History prints HH:MM, so any reading taken before 06:31 shows as
/// `06:30` and is honest; one at 06:31:00 would print `06:31`, later than the
/// deadline the card promised. The display draws the line, which is why there
/// is no constant here to justify.
///
/// This matters because the cap check is the window's LAST check. Before this,
/// five seconds of slack meant a wake landing 10s late was treated as a new
/// morning: the engine closed the books using the previous reading and never
/// checked again, so a 06:00 alarm with a 30-minute window recorded
/// `last checked 06:29`, and a 1-minute window recorded `06:00` (device, 2026-07-26).
DateTime nivaatOccurrenceEndsAfter(NivaatAlarm alarm, DateTime alarmAt) {
  final cap = alarm.retryCapAt(alarmAt);
  return DateTime(cap.year, cap.month, cap.day, cap.hour, cap.minute)
      .add(const Duration(minutes: 1));
}

/// Is [state] still the occurrence the engine is working on at [t]?
///
/// One rule, two readers — the engine picks the occurrence to evaluate with it,
/// and the UI decides what to count down to ([nivaatNextRingAt]) — so a screen
/// can never disagree with the engine about which morning is live. The weekday
/// test drops a state whose day is no longer selected.
bool nivaatOccurrenceInFlight(
  NivaatAlarm alarm,
  CheckState state,
  DateTime t,
) =>
    t.isBefore(nivaatOccurrenceEndsAfter(alarm, state.alarmAt)) &&
    alarm.weekdays.contains(state.alarmAt.weekday);

/// Next moment this alarm may ring — the in-flight **pre-T** occurrence if any,
/// else [NivaatAlarm.nextOccurrence]. Null when the alarm is off (unless
/// [ignoreEnabled]), when no weekday is selected, or while a **post-T retry**
/// is still open (a late ring is anytime — don't flash tomorrow beside
/// "Still checking … until …").
///
/// [ignoreEnabled] exists for the **alarm editor**, and the split is deliberate
/// (Samyak, 2026-07-26): the editor is where you are choosing a time, so "in 7h
/// 20m" is the feedback that makes the choice — switched on or not. A home row
/// is the opposite: its switch is off, so it must not advertise a ring. Same
/// alarm, two different questions.
DateTime? nivaatNextRingAt(
  NivaatAlarm alarm,
  CheckState? state, {
  DateTime? now,
  bool ignoreEnabled = false,
}) {
  if (!ignoreEnabled && !alarm.enabled) return null;
  final t = now ?? DateTime.now();
  if (state != null && nivaatOccurrenceInFlight(alarm, state, t)) {
    return state.alarmAt.isAfter(t) ? state.alarmAt : null;
  }
  return alarm.nextOccurrence(t);
}

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
    OutboxStore? outbox,
  }) : outbox = outbox ?? OutboxStore() {
    scheduler.setHostAlarmEventHandler(_onHostAlarmEvent);
  }

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

  /// Where "this occurrence closed and the next one still needs arming" lives
  /// between the transaction that decides it and the platform call that does
  /// it. See [_rollOn].
  final OutboxStore outbox;

  /// Kind string for a roll-on intent. Stored in rows, so renaming it strands
  /// whatever is in flight — the dispatcher parks a row it has no handler for.
  static const String rollOnKind = 'nivaat.rollOn';

  /// The intent to open the occurrence after [closed] for [alarmId].
  ///
  /// **Keyed by occurrence, never by clock time.** That is what makes a repeat
  /// settle of one morning — which host events make routine, since they arrive
  /// at least once and two isolates can both be told — find the roll already
  /// recorded instead of booking a second one.
  static OutboxIntent _rollOnIntent(int alarmId, DateTime closed) => OutboxIntent(
        kind: rollOnKind,
        dedupKey: '$rollOnKind:$alarmId:${closed.microsecondsSinceEpoch}',
        payload: {
          'alarmId': alarmId,
          'closedMicros': closed.microsecondsSinceEpoch,
        },
      );

  /// Handlers bound to the clock of the pass dispatching them.
  ///
  /// [t] is threaded rather than re-derived because **a settle uses the clock
  /// of the pass it runs inside**, and reaching for the wall clock instead once
  /// rolled the cascade past a whole occurrence. Null only at a barrier, where
  /// the row is being recovered on its own and there is no pass clock to
  /// inherit — [_nowFor] then answers, exactly as it does for a host event that
  /// arrives outside a lane.
  Map<String, OutboxHandler> _outboxHandlersAt(DateTime? t) =>
      {rollOnKind: (job) => _runRollOnJob(job, t)};

  /// Take this alarm's card down. Only for a card that can never be corrected
  /// into truth: the alarm (or its court) is gone, or a late ring has taken
  /// over as the morning's card.
  Future<void> _cancelCard(int alarmId) async {
    try {
      await notifier?.cancelForAlarm(alarmId);
    } on Exception {
      // A notification failure must never break the cascade.
    }
  }

  /// Append one state's history row **and then** push the morning's card,
  /// both stamped with the same push number. **That order is the safety
  /// rule** — see below; don't reverse it to read more naturally.
  ///
  /// These two are deliberately one call. Every card the user sees has a row
  /// behind it and vice versa, so neither can be added without the other, and
  /// the row cannot drift from what the card said — it is built from the same
  /// [HistoryRecord].
  ///
  /// The row is appended, never edited: a morning that changes its mind
  /// (Keep checking widened, then narrowed) leaves one row per push and the
  /// reader follows the sequence. [CheckState.pushSeq] is what keeps that
  /// safe against a foreground/background double-write — see [HistoryRecord].
  ///
  /// [show] receives the notifier only when there is one, so no call site has
  /// to null-check it — and a `!` here would throw a TypeError, which is an
  /// Error and would sail straight past the Exception guard below.
  ///
  /// Returns [state] with the counter advanced; the caller must save it.
  Future<CheckState> _pushCard(
    CheckState state,
    HistoryRecord Function(int pushSeq) build,
    Future<void> Function(SkipNotifier n, HistoryRecord record)? show,
  ) async {
    final next = state.copyWith(pushSeq: state.pushSeq + 1);
    final record = build(next.pushSeq);
    // Row first. If the write throws, the whole evaluate unwinds and nothing
    // was shown — better than a card in the shade with no record behind it,
    // which is the one direction the user can't recover from. The notify then
    // fails soft: history stays complete even when the shade doesn't.
    await store.upsertHistory(record);
    final n = notifier;
    if (show != null && n != null) {
      try {
        await show(n, record);
      } on Exception {
        // A notification failure must never break the cascade.
      }
    }
    return next;
  }

  /// Clear EVERY armed ring for this alarm — the pre-arm, the late-ring and
  /// the next-occurrence lockers, since the role we aren't looking at right
  /// now may still hold one.
  Future<void> _cancelAllRings(int alarmId) async {
    for (final id in NivaatIds.allRings(alarmId)) {
      await scheduler.cancel(id);
    }
  }

  /// Is any of this alarm's occurrences sounding? Rule 1 has to ask about
  /// every locker: a late ring from the occurrence that just closed can still
  /// be audible after `next` has rolled on to tomorrow, and a next-occurrence
  /// pre-arm can sound in its own right when no ladder rung ever ran to hand
  /// it over. Missing either would let the cascade cancel a ring that is
  /// physically going off.
  Future<bool> _isRingingAny(int alarmId) async {
    for (final id in NivaatIds.allRings(alarmId)) {
      if (await scheduler.isRinging(id)) return true;
    }
    return false;
  }

  /// Within this window of the alarm we trust live wind over forecast.
  static const Duration liveWindWindow = Duration(minutes: 15);

  Future<void> evaluateAll({DateTime? now}) async {
    final t = now ?? DateTime.now();
    // Host events before any Rang / cancel / re-arm decision.
    await scheduler.applyHostAlarmEvents();
    // **The barrier where an abandoned intent is picked up.** A process that
    // died between closing an occurrence and arming the next one left its
    // roll-on row leased; the lease has expired by now, so this is where the
    // next morning finally gets booked. Unscoped on purpose — this is the one
    // place with no alarm's lane to break, and each job takes its own.
    //
    // Never throws (the dispatcher logs and retries), so a stuck intent cannot
    // stop the pass that would otherwise still evaluate every alarm. The pass
    // clock is threaded in like every other call here — a recovered roll must
    // not silently reach for `DateTime.now()`.
    await outbox.dispatch(_outboxHandlersAt(t), now: t);
    // Housekeeping, not correctness — the same shape (and the same guard) as
    // the host-event claim sweep. Without a caller the `done` rows the outbox
    // keeps as its "already rolled" record would accumulate for the life of
    // the install.
    try {
      await outbox.prune(now: t);
    } on Exception catch (e) {
      debugPrint('nivaat outbox prune failed (non-fatal): $e');
    }
    await _recoverAmbiguousPending(now: t);
    final alarms = await store.loadAlarms();
    final courts = await store.loadCourts();
    // Sweep BEFORE the loop, not after: `evaluateAlarm` can throw (a wind
    // fetch, a plugin hiccup) and a sweep behind it would be skipped by
    // exactly the passes that most need one. Nothing this pass goes on to arm
    // can be swept anyway — every alarm it touches is in `alarms`.
    await _sweepOrphanRings(alarms);
    for (final alarm in alarms) {
      await evaluateAlarm(alarm, courts, now: t);
    }
  }

  /// Cancel every armed ring whose alarm has left the store.
  ///
  /// The recovery half of the delete race. [_stillLive] stops this isolate
  /// from creating an orphan, but it cannot undo one that already exists —
  /// armed by a build without that guard, or by a background isolate whose
  /// snapshot went stale inside the gap any check-then-act leaves open.
  ///
  /// **The gap is not the store's any more, and this is still needed.** It used
  /// to be blamed on SharedPreferences having no cross-isolate lock; SQLite has
  /// one, and the store reads are atomic now. The gap that remains is the one
  /// no database can close: the read and the ARMING are separate acts, and no
  /// transaction reaches AlarmManager or AlarmKit. And an orphan is
  /// **permanent** without this: [evaluateAll] only ever visits alarms that are
  /// in the store, so a deleted id is never looked at again and its ring keeps
  /// firing on schedule for good.
  ///
  /// `scheduledIds()` over-reporting — on Android it is the plugin's own
  /// bookkeeping, not the OS's — is harmless *here and only here*: a sweep
  /// decides what to CANCEL, and cancelling something already gone is a no-op.
  /// Never read that call as proof a ring IS armed.
  Future<void> _sweepOrphanRings(List<NivaatAlarm> alarms) async {
    final live = {for (final a in alarms) a.id};
    final Set<int> armed;
    try {
      armed = await scheduler.scheduledIds();
    } on Exception catch (e) {
      // The safety net must never be the thing that stops the cascade.
      debugPrint('nivaat orphan ring sweep skipped (non-fatal): $e');
      return;
    }
    for (final id in armed) {
      final alarmId = NivaatIds.alarmIdOfRing(id);
      if (alarmId == null || live.contains(alarmId)) continue;
      try {
        await scheduler.cancel(id);
      } on Exception catch (e) {
        // Per id, not per sweep: one throwing cancel escaping here would abort
        // the whole pass before any alarm was evaluated — the safety net
        // taking down what it protects. The orphan waits for the next sweep.
        debugPrint('nivaat orphan ring $id could not be cancelled: $e');
      }
    }
  }

  /// Is [alarm] — and the court it rings for — still in the store?
  ///
  /// [evaluateAll] snapshots the alarm and court lists once, then spends
  /// seconds per alarm on a wind fetch, all while the home screen is already
  /// up (`init` renders before it awaits `resync`). A delete landing in that
  /// window leaves the loop holding a stale, still-`enabled` copy, and arming
  /// its ring is unrecoverable from inside the cascade — see
  /// [_sweepOrphanRings] for why, and for the net that catches what this
  /// misses.
  ///
  /// The court is checked too, because `removeCourt` is the same hole by the
  /// other door: it drops those alarms from the store as well, and the stale
  /// snapshot still lists the court, so `_evaluate`'s court-gone branch does
  /// not fire. Read from the STORE's copy of the alarm, never the snapshot's —
  /// an edit may have moved it to a different court in the meantime.
  Future<bool> _stillLive(NivaatAlarm alarm) async {
    // No reload needed any more: this reads the database, so a delete the UI
    // isolate committed while this pass was fetching wind is simply there. It
    // used to require `store.refresh()` because SharedPreferences caches per
    // isolate and a background check would otherwise never see that delete —
    // the exact split REVIEW #23 is about.
    //
    // **What this still is not is a lock.** The read and the arming below are
    // separate acts, and nothing here makes the platform call part of the
    // transaction, so a delete landing between them still leaves an orphan.
    // That is what [_sweepOrphanRings] is for, and moving to a database did not
    // retire it.
    for (final a in await store.loadAlarms()) {
      if (a.id != alarm.id) continue;
      // **`enabled` is re-read too, not just existence.** A toggle-off is the
      // same race as a delete by a quieter door: the snapshot this pass is
      // holding still says `enabled: true`, and `_resolveOccurrence` — the only
      // other thing that reads the flag — read it off that same stale copy. On
      // one isolate the lane covers it, because the toggle's own
      // `abandonOccurrence` queues behind this pass and cancels what it armed;
      // across isolates nothing did, and the orphan sweep cannot help, since a
      // disabled alarm has not left the store.
      // **Every field that decides WHAT gets armed is compared, not just
      // existence.** An edit is the delete race with the alarm still present:
      // the snapshot this pass holds says 06:00, the store now says 07:00, and
      // `next` was computed from the snapshot — so the pass arms a ring for a
      // time the user has already moved away from, on a locker the new
      // occurrence will not look at. Bail and let the edit's own evaluation,
      // which is already queued behind this one, do the work.
      if (a.enabled != alarm.enabled ||
          a.hour != alarm.hour ||
          a.minute != alarm.minute ||
          a.courtId != alarm.courtId ||
          a.courtSpeedLimitKmh != alarm.courtSpeedLimitKmh ||
          a.retryMinutesAfter != alarm.retryMinutesAfter ||
          a.weekdays.length != alarm.weekdays.length ||
          !a.weekdays.containsAll(alarm.weekdays)) {
        return false;
      }
      if (!a.enabled) return false;
      return (await store.loadCourts()).any((c) => c.id == a.courtId);
    }
    return false;
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
  ///
  /// Host-event handlers also enter this lane (C1, 2026-08-08): a drop that
  /// lands while post-T hold/`_rollOn` is mid-flight must not settle
  /// concurrently and roll on a second time. When the lane is already running
  /// for that alarm ([_activeAlarmIds]), the handler runs inline so
  /// `applyHostAlarmEvents` inside the job cannot deadlock waiting on itself.
  final Map<int, Future<void>> _evalQueue = {};

  /// **Every** alarm id whose `_enqueue` job is executing on this isolate.
  ///
  /// A SET, not one slot, and that is load-bearing rather than tidiness. Lanes
  /// are per alarm, so two jobs genuinely overlap — alarm A parked on its wind
  /// fetch inside `applyHostAlarmEvents` while alarm B's handler runs to
  /// completion. With a single slot, B finishing cleared the mark for A, so
  /// the next event for A missed the inline path and queued behind A's own
  /// still-running job: the handler waited for the job, the job waited for the
  /// handler, and `evaluateAll` never returned. Two events in one batch was
  /// all it took.
  final Set<int> _activeAlarmIds = {};

  /// The clock each active job is evaluating against, so a host event handled
  /// inside that job settles at the SAME instant the pass is using rather than
  /// reaching for the wall clock. Every other entry point in this repo takes
  /// `now` as a parameter for exactly this reason (CLAUDE.md) — and a settle
  /// that read `DateTime.now()` while the pass evaluated 06:00 rolled the
  /// cascade on to the wrong day.
  final Map<int, DateTime> _activeNow = {};

  /// True while [_handleHostAlarmEvent] runs. Evaluate must not re-enter
  /// `applyHostAlarmEvents` in that stack — the outer drain is awaiting the
  /// handler, and a nested apply that waits on that drain deadlocks (or lets
  /// emit return before roll-on evaluate finishes).
  bool _inHostHandler = false;

  /// Occurrences closed by an inline host settle during an active evaluate
  /// (`alarmId:occurrenceMs`). The outer pass must abort before re-arming or
  /// overwriting rolled-on CheckState — enqueue alone is not enough when the
  /// handler runs inline on `_activeAlarmId` (continue-after-settle).
  final Set<String> _hostClosedOccurrences = {};

  /// Occurrences an inline host settle both closed **and rolled on from**.
  ///
  /// Closing and rolling are separate acts, and only tracking the first lost
  /// the second. A settle skips the roll when the pass that armed the ring had
  /// already claimed it (`rollOnDone`) — so "closed" alone told the outer pass
  /// nothing about whether tomorrow had been opened, and returning on it left
  /// the cascade with no next occurrence at all. Exactly one side must roll;
  /// this is how they agree which.
  final Set<String> _hostRolledOccurrences = {};

  String _occurrenceKey(int alarmId, DateTime occurrence) =>
      '$alarmId:${occurrence.millisecondsSinceEpoch}';

  void _markHostClosedOccurrence(int alarmId, DateTime occurrence) {
    _hostClosedOccurrences.add(_occurrenceKey(alarmId, occurrence));
  }

  bool _hostClosedOccurrence(int alarmId, DateTime occurrence) =>
      _hostClosedOccurrences.contains(_occurrenceKey(alarmId, occurrence));

  /// The stored alarm with [alarmId], or null if it has been deleted.
  Future<NivaatAlarm?> _alarmById(int alarmId) async {
    for (final a in await store.loadAlarms()) {
      if (a.id == alarmId) return a;
    }
    return null;
  }

  /// The instant a host settle for [alarmId] should use: the clock of the job
  /// it is running inside, or the wall clock when it arrives on its own.
  DateTime _nowFor(int alarmId) => _activeNow[alarmId] ?? DateTime.now();

  Future<void> _enqueue(
    int alarmId,
    Future<void> Function() job, {
    DateTime? now,
  }) {
    final tail = _evalQueue[alarmId] ?? Future<void>.value();
    final run = tail.then((_) async {
      _activeAlarmIds.add(alarmId);
      if (now != null) _activeNow[alarmId] = now;
      // Clear prior-job flags only here — not at `_evaluate` entry. Nested
      // `_rollOn` → `_evaluate` must keep the mark so the outer pass still
      // aborts after an inline host settle.
      _hostClosedOccurrences
          .removeWhere((k) => k.startsWith('$alarmId:'));
      _hostRolledOccurrences
          .removeWhere((k) => k.startsWith('$alarmId:'));
      try {
        await job();
      } finally {
        _activeAlarmIds.remove(alarmId);
        _activeNow.remove(alarmId);
      }
    });
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
      _enqueue(alarm.id, () async {
        await scheduler.applyHostAlarmEvents();
        await _evaluate(alarm, courts, now: now);
      }, now: now);

  /// You ended the in-flight occurrence — toggled the alarm off, or edited its
  /// time / court / weekday so today's window no longer applies.
  ///
  /// Finalises a fired-but-unlogged ring first (that ring really woke you, and
  /// clearing state without recording it was how an edited alarm's ring
  /// vanished from history for good — 2026-07-19 device testing), then rewrites
  /// the morning's card to `Cancelled` and appends the matching row. Pass the
  /// PRE-edit alarm when an edit abandoned: the fired ring, and the reason
  /// behind the card, belong to its old court and thresholds.
  ///
  /// Nothing is written when the morning never posted a card — cancelling
  /// before T ends a window that never started, and leaves no trace to explain.
  Future<void> abandonOccurrence(
    NivaatAlarm alarm, {
    DateTime? now,
    bool keepCard = false,
  }) =>
      _enqueue(alarm.id, now: now, () async {
        final t = now ?? DateTime.now();
        await scheduler.applyHostAlarmEvents();
        // A pending ring for this alarm: if it's audible, settle as Rang.
        // Otherwise clear it without Policy B — toggle-off / delete is an
        // intentional abandon, not ambiguous loss-after-ack (H2).
        final pending = await store.loadPendingRing(alarm.id);
        if (pending != null) {
          if (await scheduler.isRinging(pending.pluginId)) {
            await _settlePending(
              pending,
              disposition: RingDisposition.rang,
              now: t,
              rollOn: false,
            );
          } else {
            await store.clearPendingRing(alarm.id);
          }
        }
        final state = await store.loadCheckState(alarm.id);
        // The advanced counter _pushCard hands back is dropped on purpose here:
        // this occurrence is ending, and its state is cleared below, so there
        // is nothing left to number.
        if (state != null && state.ringScheduled && t.isAfter(state.alarmAt)) {
          await _settleRingScheduled(
            alarm,
            state,
            now: t,
            courts: await store.loadCourts(),
            rollOn: false,
          );
        } else if (state != null && state.cardShown) {
          final court = keepCard ? await _courtFor(alarm) : null;
          await _pushCard(
            state,
            (seq) => _skipRecord(
              alarm,
              state.alarmAt,
              state,
              kind: HistoryKind.cancelled,
              checkingEndedAt: t,
              pushSeq: seq,
            ),
            // Deleting the alarm takes the card down instead — a card for
            // something that no longer exists is an orphan no rewrite fixes.
            court == null ? null : (n, r) => n.showCancelled(r, court.name),
          );
        }
        // Unconditional, and not just for the branch above: a delete must also
        // clear a card left over from an EARLIER morning, which has no state
        // here to notice it by.
        if (!keepCard) await _cancelCard(alarm.id);
        await _cancelAllRings(alarm.id);
        await checks.cancelCheck(alarm.id);
        await store.clearCheckState(alarm.id);
        await store.clearPendingRing(alarm.id);
      });

  /// Keep-checking / add-only weekdays / limit: keep the same occurrence
  /// flying under the new settings.
  ///
  /// Limit-only returns early — state stays put and the follow-up
  /// [evaluateAlarm] re-decides under the new thresholds, which is what makes
  /// "raise the limit at 06:05 and it still rings this morning" work. A new
  /// retry cap re-posts the card with the new deadline and appends a row for
  /// it; the wind numbers come from the STORED reading, never rebuilt from the
  /// edited alarm — that mixed two moments into "Too windy · wind 5 (≤20)".
  ///
  /// **Either window being over ends the morning HERE**, on Save, with a
  /// `Skipped` card and no further promise — see the guard below for both
  /// cases and why the boundary is the cap's minute. The follow-up
  /// [evaluateAlarm] then has nothing left to close and only rolls tomorrow
  /// on. Neither case is a cancellation: nobody stopped this, it ran out.
  Future<void> retainInFlightEdits(
    NivaatAlarm previous,
    NivaatAlarm next, {
    DateTime? now,
  }) =>
      _enqueue(next.id, now: now, () async {
        final t = now ?? DateTime.now();
        var state = await store.loadCheckState(next.id);
        if (state == null) return;
        if (previous.retryMinutesAfter == next.retryMinutesAfter) return;
        final court = await _courtFor(next);
        // Two ways the morning is already over, and both end it here rather
        // than pushing another promise:
        //
        // * the OLD window had already run out — widening after death must
        //   not resurrect it;
        // * the NEW window is already behind us — shrinking 30→1 at T+2 used
        //   to post an alerting card reading `watching until 06:01` at 06:02,
        //   and append the matching row, which is immutable and therefore
        //   stayed in the log for good. A promise the morning has already
        //   broken is the exact failure the one-card model exists to prevent
        //   (device review, 2026-07-31).
        //
        // Judged by [nivaatOccurrenceInFlight], not a raw compare against the
        // new cap, so the boundary matches what the card prints: still inside
        // the cap's own minute is still honest.
        if (!nivaatOccurrenceInFlight(previous, state, t) ||
            !nivaatOccurrenceInFlight(next, state, t)) {
          await _finaliseDeadWindow(previous, state, court, t);
          return;
        }
        if (!state.cardShown) return;
        final newCap = next.retryCapAt(state.alarmAt);
        final open = state;
        state = await _pushCard(
          open,
          (seq) => _skipRecord(
            previous,
            open.alarmAt,
            open,
            kind: HistoryKind.stillChecking,
            watchedUntil: newCap,
            pushSeq: seq,
          ),
          court == null
              ? null
              : (n, r) => n.showStillChecking(r, court.name, newCap),
        );
        await store.saveCheckState(state);
      });

  /// The cap already passed (or Keep checking widened after the window died):
  /// close [state] out and clear it. Not a cancellation — nobody stopped this,
  /// it simply ran out.
  Future<void> _finaliseDeadWindow(
    NivaatAlarm alarm,
    CheckState state,
    SavedLocation? court,
    DateTime t,
  ) async {
    if (state.ringScheduled) {
      await _settleRingScheduled(
        alarm,
        state,
        now: t,
        courts: court == null ? <SavedLocation>[] : [court],
        rollOn: false,
      );
    } else {
      await _pushCard(
        state,
        (seq) => _skipRecord(alarm, state.alarmAt, state, pushSeq: seq),
        court == null ? null : (n, r) => n.showSkipped(r, court.name),
      );
    }
    await checks.cancelCheck(alarm.id);
    await store.clearCheckState(alarm.id);
  }

  Future<SavedLocation?> _courtFor(NivaatAlarm alarm) async {
    for (final c in await store.loadCourts()) {
      if (c.id == alarm.courtId) return c;
    }
    return null;
  }

  /// [rolledOn] marks the nested pass [_rollOn] makes to open the NEXT
  /// occurrence, and it changes exactly one thing: where a pre-arm is written.
  /// That pass runs at the instant the occurrence it just closed was due to
  /// ring, so `NivaatIds.ring(alarm.id)` may still be holding a live alarm
  /// that is milliseconds from sounding. A roll-on therefore never writes to
  /// (and so never evicts) that locker — it uses `NivaatIds.nextRing`, which
  /// the occurrence's own first ladder rung takes over from.
  Future<void> _evaluate(
    NivaatAlarm alarm,
    List<SavedLocation> courts, {
    DateTime? now,
    bool rolledOn = false,
  }) async {
    final t = now ?? DateTime.now();
    // Live host events can land between evaluateAll's barrier and here —
    // drain again before any cancel / schedule / Rang decision.
    if (!rolledOn && !_inHostHandler) {
      await scheduler.applyHostAlarmEvents();
    }

    SavedLocation? court;
    for (final c in courts) {
      if (c.id == alarm.courtId) court = c;
    }

    final stored = await store.loadCheckState(alarm.id);
    final pending = await store.loadPendingRing(alarm.id);
    final next = _resolveOccurrence(alarm, stored, t);
    if (next == null || court == null) {
      await _cancelAllRings(alarm.id);
      await checks.cancelCheck(alarm.id);
      // This alarm has gone quiet — switched off, deleted, or its court
      // removed. Only the last two take the card down: those leave a card for
      // something that no longer exists, which no rewrite can make true. A
      // switched-off alarm is different — [abandonOccurrence] has just
      // rewritten its card to `Cancelled`, and cancelling here would erase the
      // explanation a moment after writing it. Court-gone is tested first
      // because it needs no store read to decide.
      //
      // Nothing is written here either, for the same reason: the toggle or the
      // abandoning edit already appended its row and cleared the state, so
      // this pass normally finds an empty locker. The exception below is a
      // committed ring that already fired and must reach history even as its
      // alarm is disabled or deleted — clearing state first silently dropped
      // it ("rang but never showed up in history", 2026-07-19 device testing).
      // Only when the COURT survives, though: a row whose court is gone is an
      // orphan no screen can render, and `removeCourt` sweeps that court's
      // whole log straight afterwards (2026-07-22).
      if (court == null ||
          !(await store.loadAlarms()).any((a) => a.id == alarm.id)) {
        await _cancelCard(alarm.id);
      }
      if (court != null &&
          stored != null &&
          stored.ringScheduled &&
          t.isAfter(stored.alarmAt)) {
        await _settleRingScheduled(
          alarm,
          stored,
          now: t,
          courts: courts,
          rollOn: false,
        );
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
    if (alarm.enabled && await _isRingingAny(alarm.id)) {
      // Audible = final. Prefer a held [PendingRing] (post-T schedule success
      // no longer writes Rang immediately); fall back to CheckState that still
      // carries ringScheduled for a pre-T arm that sounded before promotion.
      if (pending != null &&
          !t.isBefore(pending.occurrenceAt) &&
          await scheduler.isRinging(pending.pluginId)) {
        await _settlePending(
          pending,
          disposition: RingDisposition.rang,
          now: t,
          courts: courts,
        );
      } else if (stored != null &&
          stored.ringScheduled &&
          !t.isBefore(stored.alarmAt)) {
        await _pushCard(
          stored,
          (seq) => _rangRecord(alarm, stored, pushSeq: seq),
          null,
        );
        await store.clearCheckState(alarm.id);
      }
      // Keep the cascade alive without touching the scheduler (cancelling or
      // re-setting the ring's id would silence it): checks live in their own
      // id space, so book the NEXT occurrence's first rung. Without this, the
      // T-0 check ending here left Android with no future wakeup at all —
      // checks only ever reschedule themselves.
      final upcoming = alarm.nextOccurrence(t);
      if (upcoming != null) {
        final firstRung = CheckCascade.nextCheckTime(
          t,
          upcoming,
          retryCapMinutes: alarm.retryMinutesAfter,
        );
        if (firstRung != null &&
            !await checks.scheduleCheck(alarm.id, firstRung)) {
          // Same rule as the bottom of this method (REVIEW #22): on Android
          // nothing else re-books the cascade, so a refusal here means the
          // NEXT occurrence has no wakeup — and this is the one path that
          // reaches it while a ring is audible, i.e. during a mid-ring resync.
          debugPrint('nivaat could not book the first rung for alarm '
              '${alarm.id} at $firstRung — its next occurrence waits for an '
              'app open');
        }
      }
      return;
    }

    // An occurrence we're no longer tracking as current (the app first ran past
    // its retry window, so `next` has already rolled on) still needs
    // finalising — the app may never have run during [T, T+cap]. A committed
    // ring is settled (audible / pending / ambiguous B); anything else
    // (windy / gusty / no-data) is a skip → log it AND post its one card, so a
    // late first-open never silently drops the occurrence. (Mutually exclusive
    // with Rule 2, the in-window case where next == stored.alarmAt.) Without
    // this, iOS — no exact wakeups — loses the whole occurrence when first
    // opened past the cap.
    if (stored != null &&
        stored.alarmAt != next &&
        t.isAfter(stored.alarmAt)) {
      if (stored.ringScheduled) {
        final settled = await _settleRingScheduled(
          alarm,
          stored,
          now: t,
          courts: courts,
          rollOn: false,
        );
        if (!settled) {
          // Still owed on the plugin — promote to pending so this pass can
          // open the next occurrence without cancelling today's pre-arm.
          //
          // **`rollOnDone: true` here is not a claim about a roll that ran**,
          // unlike every other write of it — `rollOn: false` above means none
          // was even attempted. It says the roll is UNNECESSARY: this pass is
          // already evaluating `next`, which is the occurrence a roll from
          // `stored` would have opened, and it goes on to do exactly that
          // below. So there is no failure to ask about.
          final held = await _holdPendingFromState(alarm, stored);
          await store.savePendingRing(held.copyWith(rollOnDone: true));
        }
      } else {
        final closed = stored;
        final courtName = court.name;
        await _pushCard(
          closed,
          (seq) => _skipRecord(alarm, closed.alarmAt, closed, pushSeq: seq),
          (n, r) => n.showSkipped(r, courtName),
        );
      }
      await store.clearCheckState(alarm.id);
    }

    // Cascade state is per-occurrence.
    var state = (stored != null && stored.alarmAt == next)
        ? stored
        : CheckState(alarmId: alarm.id, alarmAt: next);

    // Rule 2: a committed ring whose time has passed (and isn't sounding — see
    // Rule 1) is Owed, not proven Rang. Hold pending while the plugin still
    // has it; settle audible / drop / ambiguous B otherwise. Never treat
    // the platform's stored time as Rang proof.
    if (state.ringScheduled && t.isAfter(next)) {
      final settled = await _settleRingScheduled(
        alarm,
        state,
        now: t,
        courts: courts,
        rollOn: true,
      );
      if (settled) return;
      // Still armed on the plugin — promote to pending and roll on without
      // writing Rang (and without falling through to a re-decide that would
      // cancel the pre-arm about to sound — REVIEW #1(a)).
      final held = await _holdPendingFromState(alarm, state);
      await store.clearCheckState(alarm.id);
      // **Only claim the roll once it is a fact** — the same rule as the post-T
      // hold below, and the third site of this shape. `rollOnDone: true` makes
      // `_settlePending.owesRoll` false for this occurrence for good, so
      // stamping it after a roll that failed retires the pending slot's own
      // recovery path and leaves the outbox row as the only thing still owed.
      // The dispatcher swallows the failure, so it has to be asked about.
      if (!await _rollOn(alarm, t, next)) return;
      final still = await store.loadPendingRing(alarm.id);
      if (still != null &&
          still.occurrenceAt == held.occurrenceAt &&
          still.pluginId == held.pluginId) {
        await store.savePendingRing(still.copyWith(rollOnDone: true));
      }
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

    // The point of no return: everything above only READ, everything below
    // arms rings, posts the card and books wakeups. Here rather than on entry
    // because an evaluation already past an entry check would schedule anyway
    // — see [_stillLive].
    if (!await _stillLive(alarm)) return;

    // Re-drain before destructive cancel / schedule (live events may have
    // landed while we were fetching wind). Never re-enter apply while a host
    // handler is on the stack — the outer drain awaits that handler.
    if (!_inHostHandler) {
      await scheduler.applyHostAlarmEvents();
    }
    // Inline host settle during the fetch (or this drain) may have closed
    // `next` and rolled on. Abort before re-arming today or saveCheckState
    // clobbers tomorrow's CheckState (continue-after-settle).
    if (_hostClosedOccurrence(alarm.id, next)) return;
    if (stored != null && stored.alarmAt == next) {
      final afterHost = await store.loadCheckState(alarm.id);
      if (afterHost == null || afterHost.alarmAt != next) return;
      state = afterHost.copyWith(lastAttemptAt: t);
    }

    // Where a pre-arm from THIS pass goes. A roll-on must leave
    // `NivaatIds.ring` alone entirely — see [_evaluate]'s `rolledOn` and
    // [NivaatIds.nextRing].
    final preArmId =
        rolledOn ? NivaatIds.nextRing(alarm.id) : NivaatIds.ring(alarm.id);

    // [kNivaatWakeGrace] is zero — a wake cannot arrive early, so there is
    // nothing to forgive at this end. It stays a named constant because the
    // temptation to widen it for LATE wakes is exactly the mistake: that job
    // belongs to [nivaatOccurrenceEndsAfter], which is a different question.
    //
    // Read here rather than after the arming block because the arm itself
    // needs it: a ring put on the platform at or past T is owed from that
    // instant, and the durable record of it has to exist before the next
    // await, not eighty lines later.
    final atOrPastAlarm = !t.isBefore(next.subtract(kNivaatWakeGrace));

    // The reading behind a ring this pass REALLY put on the platform, or
    // null. Distinct from `decision.shouldRing`, which is only what the wind
    // said — scheduling can still refuse, and everything downstream that
    // treats the morning as settled has to follow the ring, not the verdict.
    WindDecision? armedWith;
    int? armedPluginId;
    RingLockerRole? armedRole;
    DateTime? armedFor;

    if (decision != null) {
      if (decision.shouldRing) {
        if (_hostClosedOccurrence(alarm.id, next)) return;
        // Not sounding here (Rule 1 returned above), so re-scheduling is safe.
        // A retry that succeeds just after T rings late (never in the past).
        // At/past T this is a LATE ring (a retry found calm air), and it goes
        // in its own locker: this same pass closes the occurrence and pre-arms
        // the NEXT one, and that pre-arm would otherwise evict this ring
        // seconds before it sounds. `!next.isAfter(t)` is precisely the
        // condition under which `_rollOn` can reach a further occurrence.
        //
        // A roll-on is excluded because it is always opening a LATER
        // occurrence, so "late" would be a contradiction — and taking this
        // branch would cancel `NivaatIds.ring`, the one thing it must not
        // touch. (Reachable only if an occurrence lands exactly on `t` while a
        // different one has just closed: the app waking on the dot of the
        // second alarm of the morning. It pre-arms `nextRing` for `t + 10s`
        // instead, which sounds on time and stays visible to Rule 1.)
        final isLate = !rolledOn && !next.isAfter(t);
        final ringAt =
            next.isAfter(t) ? next : t.add(const Duration(seconds: 10));
        final pluginId = isLate ? NivaatIds.lateRing(alarm.id) : preArmId;
        final role = isLate
            ? RingLockerRole.lateRing
            : (rolledOn ? RingLockerRole.nextRing : RingLockerRole.ring);
        if (isLate) {
          // The occurrence's own pre-armed ring (if the ladder committed one)
          // is superseded by this later, better-informed one — drop it, or the
          // alarm sounds twice a few seconds apart.
          await scheduler.cancel(NivaatIds.ring(alarm.id));
        } else if (!rolledOn) {
          // Take over from a roll-on's pre-arm, in case one is holding this
          // occurrence. Cancel BEFORE arming: two live alarms for one instant
          // ring twice, while the gap this leaves is closed on the next line
          // and re-armed by every remaining ladder rung. A cancel on an empty
          // locker is a harmless no-op on both platforms.
          await scheduler.cancel(NivaatIds.nextRing(alarm.id));
        }
        if (!_inHostHandler) {
          await scheduler.applyHostAlarmEvents();
          if (_hostClosedOccurrence(alarm.id, next)) return;
        }
        final armed = await scheduler.scheduleRing(
          id: pluginId,
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
          )}${nivaatCheckedNote(t, next, ring: true)}',
          volume: decision.volume,
        );
        // Only a ring that is REALLY armed may be recorded as one. A silent
        // failure here used to flow straight into `ringScheduled: true`, and
        // the next pass then read "committed, and its time has passed" as
        // proof it had sounded — history said `Rang` for a morning nothing was
        // ever scheduled for (REVIEW #2). Not armed leaves the occurrence
        // undecided instead, so the remaining ladder rungs try again.
        if (armed) {
          armedWith = decision;
          armedPluginId = pluginId;
          armedRole = role;
          armedFor = ringAt;
          state = state.copyWith(
            ringScheduled: true,
            ringCourtSpeedKmh: decision.sample.courtSpeedKmh,
            ringRawGustKmh: decision.sample.rawGustKmh,
            ringVolume: decision.volume,
            lastCheckAt: t,
          );
          // **Record the owed ring HERE, on the same turn it was armed.**
          // A host drop can land on any await, and the drop for this very ring
          // is likeliest in the seconds right after arming it (a foreground
          // service refused inside the boot window is the whole of upstream
          // #424). Writing the pending eighty lines further down left a gap
          // in which the handler found no pending, no saved `ringScheduled`
          // either — `state` is still only in memory — and dropped the event
          // on the floor: a ring that never sounded and no row to say so.
          //
          // `rollOnDone: false` on purpose: nobody has rolled yet, so a drop
          // landing in this window MUST roll on, and the post-T branch below
          // takes ownership by rewriting this with `true` before it does.
          // A pre-T arm gets no pending — the ring is not owed until T — but
          // its CheckState must reach disk NOW rather than at the end of the
          // pass. A drop landing in that gap found no pending and no saved
          // `ringScheduled` either (the copyWith above is still only in
          // memory), so it matched nothing, and the morning that never rang
          // was recorded as merely unconfirmed instead of missed.
          if (!atOrPastAlarm) await store.saveCheckState(state);
          if (atOrPastAlarm && !rolledOn) {
            await _savePendingKeepingHostMove(PendingRing(
              alarmId: alarm.id,
              pluginId: pluginId,
              role: role,
              occurrenceAt: next,
              scheduledFor: ringAt,
              courtId: alarm.courtId,
              volume: decision.volume,
              courtSpeedKmh: decision.sample.courtSpeedKmh,
              rawGustKmh: decision.sample.rawGustKmh,
              courtSpeedLimitKmh: decision.thresholds.courtSpeedLimitKmh,
              rawGustLimitKmh: decision.thresholds.rawGustLimit,
              lastCheckAt: t,
              rollOnDone: false,
            ));
          }
        } else {
          // `ringScheduled: false`, NOT "leave whatever was there". A failure
          // here does not merely fail to arm — it has already destroyed
          // anything this id was holding: `Alarm.set` stops the same id before
          // scheduling, AlarmKit cancels then schedules, and the late branch
          // above cancelled the pre-arm outright. Carrying an earlier rung's
          // `true` forward is REVIEW #2 exactly: the next pass reads
          // "committed, and its time has passed" and writes `Rang` for a
          // morning with nothing armed on the device.
          //
          // Clearing is also the safe direction in the rarer case where the
          // failure came BEFORE anything was destroyed (a settings validation
          // throw): the remaining rungs simply re-decide, and if the old ring
          // does sound after all, Rule 1 sees it audible and records it
          // properly. A false "not armed" costs a retry; a false "armed"
          // costs the truth.
          debugPrint('nivaat could not arm the ring for alarm ${alarm.id} at '
              '$ringAt — leaving the occurrence open for the next rung');
          state = state.copyWith(ringScheduled: false, lastCheckAt: t);
        }
      } else {
        // Not sounding here either, so cancelling the provisional ring is safe.
        // Pre-arm lockers ONLY: the late-ring locker can hold a ring for the
        // occurrence that just closed — `_rollOn` lands here moments after
        // arming it — and clearing that would re-create the very bug the split
        // exists to fix. (This occurrence can't own a late ring itself: one
        // would have finalised it as "rang" and cleared the state.)
        //
        // Both pre-arm lockers, because either can be holding THIS occurrence:
        // its own ladder rungs write `ring`, an earlier roll-on wrote
        // `nextRing`, and a skip has to clear whichever one is live. A roll-on
        // clears only its own — `preArmId` is `nextRing` there, and `ring`
        // still belongs to the occurrence that just closed.
        // Remember the reading behind this skip (kept across later no-data
        // retries) so the final card can report the real reason.
        await scheduler.cancel(preArmId);
        if (!rolledOn) await scheduler.cancel(NivaatIds.nextRing(alarm.id));
        state = state.copyWith(
          ringScheduled: false,
          skipCourtSpeedKmh: decision.sample.courtSpeedKmh,
          skipRawGustKmh: decision.sample.rawGustKmh,
          skipGusty: decision.verdict == WindVerdict.tooGusty,
          lastCheckAt: t,
        );
      }
    }

    final nextCheck = CheckCascade.nextCheckTime(
      t,
      next,
      retryCapMinutes: alarm.retryMinutesAfter,
    );
    // At/after T and a ring really armed → hold pending until audible / drop /
    // ambiguous settle. **Do NOT write Rang on schedule success** — accepting
    // the schedule only means the ring is owed. The morning's card comes DOWN:
    // the ring is that morning's notification now, and a "still checking" card
    // beside a sounding alarm is just noise.
    if (atOrPastAlarm &&
        armedWith != null &&
        armedPluginId != null &&
        armedRole != null &&
        armedFor != null) {
      // A settle closed this occurrence during one of the awaits above — the
      // wind fetch, or `scheduleRing` itself. Reachable at exactly T and
      // nowhere else: `atOrPastAlarm` is `t >= next` (the wake grace is zero)
      // while Rule 2 needs `t > next`, so T is the one instant that arrives
      // here with a ring already committed.
      //
      // The card comes down on this exit too. The line that does it for the
      // straight-through path sits below, placed there so a mid-await settle
      // could not return past it — and this exit, added later, returned past
      // it anyway, leaving `Still checking` up for a morning recorded as
      // missed. No pending is saved on this branch (the settle owns the
      // record), so there is no durable-write-first ordering to respect.
      if (_hostClosedOccurrence(alarm.id, next)) {
        if (state.cardShown) await _cancelCard(alarm.id);
        await _finishHostClosed(alarm, t, next);
        return;
      }
      final ringing = state;
      final ringDecision = armedWith;
      // **The claim is written AFTER the roll, not before it.** Marking
      // `rollOnDone` first prevents a double roll but buys it with the worse
      // failure: die in the gap and recovery reads "already rolled", so the
      // occurrence closes with nothing following it and — on Android, where
      // checks only ever re-book themselves — the alarm waits for a manual app
      // open. Rolling first risks re-arming the same ring for the same instant
      // on the next pass, which is a no-op. Same trade `_settlePending` makes,
      // and the two must agree or one of them is wrong.
      //
      // A drop settling mid-await cannot roll twice either way, because a
      // settle whose roll SUCCEEDED marks `_hostRolledOccurrences` and
      // [_rollOnUnlessHostDid] reads it. One whose roll failed leaves the mark
      // unset on purpose, so this pass tries again rather than inheriting a
      // claim that was never earned.
      final pendingRing = PendingRing(
        alarmId: alarm.id,
        pluginId: armedPluginId,
        role: armedRole,
        occurrenceAt: next,
        scheduledFor: armedFor,
        courtId: alarm.courtId,
        volume: ringDecision.volume,
        courtSpeedKmh: ringDecision.sample.courtSpeedKmh,
        rawGustKmh: ringDecision.sample.rawGustKmh,
        courtSpeedLimitKmh: ringDecision.thresholds.courtSpeedLimitKmh,
        rawGustLimitKmh: ringDecision.thresholds.rawGustLimit,
        lastCheckAt: t,
        rollOnDone: false,
      );
      await _savePendingKeepingHostMove(pendingRing);
      // The morning's card comes down on EVERY exit from this branch, not just
      // the straight-through one: a drop settling mid-await used to return past
      // this line and leave `Still checking` in the shade for a ring that was
      // already recorded as missed. **Both host-closed exits do it** — the
      // early one has its own copy, because it returns before reaching here.
      if (ringing.cardShown) await _cancelCard(alarm.id);
      // The writes above are awaits, so a drop can settle this occurrence
      // during them — and `savePendingRing` would then put a cleared slot back.
      // Take it away again rather than leaving a pending nobody owes, then
      // finish whichever half the settle left to us.
      if (_hostClosedOccurrence(alarm.id, next)) {
        await _finishHostClosed(alarm, t, next);
        return;
      }
      await store.clearCheckState(alarm.id);
      final rolled = await _rollOnUnlessHostDid(alarm, t, next);
      // **Only once the roll is a FACT.** `rollOnDone` is the claim that the
      // next occurrence is open, and the comment above explains why it is
      // written after the roll rather than before: recovery that reads "already
      // rolled" when nothing rolled closes the occurrence with nothing
      // following it, and on Android nothing else books one. Stamping it after
      // a roll that FAILED is the same lie by a quieter route — the dispatcher
      // swallows the failure, so it has to be asked about.
      //
      // And only onto a slot that is still this occurrence's: a settle during
      // the roll may have finalised and cleared it, and resurrecting it would
      // leave a pending ring nothing is waiting for.
      if (!rolled) return;
      final held = await store.loadPendingRing(alarm.id);
      if (held != null && held.occurrenceAt == next && !held.rollOnDone) {
        await store.savePendingRing(held.copyWith(rollOnDone: true));
      }
      return;
    }

    // At/after T but NOT ringing (windy/gusty/no-data): the skip is provisional.
    // Keep re-checking every minute until the alarm's retry cap, ringing late
    // if the wind drops. Only at the cap do we finalise the skip and rewrite
    // the card — using the last KNOWN reason (state), so a network blip exactly
    // at the cap still reports "windy" rather than "couldn't check".
    if (atOrPastAlarm && nextCheck == null) {
      final closing = state;
      final courtName = court.name;
      await _pushCard(
        closing,
        (seq) => _skipRecord(alarm, next, closing, pushSeq: seq),
        (n, r) => n.showSkipped(r, courtName),
      );
      await store.clearCheckState(alarm.id);
      // Whether the roll landed is only `_settlePending`'s business — it is the
      // one caller holding a pending slot that must not be dropped on a roll
      // that never happened. Here there is no slot, and a failed roll is
      // already owed in the outbox for the next barrier.
      await _rollOn(alarm, t, next);
      return;
    }

    // Before T (ladder), or a provisional post-T skip → keep the cascade going.
    // On the first at/after-T skip, post the morning's card AND its permanent
    // history row: the at-T moment is in the app from the moment it happens
    // (user decision 2026-07-19), as its own entry — the outcome will be a
    // separate later row, so dismissing the card never hides what happened.
    if (atOrPastAlarm && !state.cardShown) {
      final until = alarm.retryCapAt(next);
      final opening = state;
      final courtName = court.name;
      state = await _pushCard(
        opening,
        (seq) => _skipRecord(
          alarm,
          next,
          opening,
          kind: HistoryKind.stillChecking,
          watchedUntil: until,
          pushSeq: seq,
        ),
        (n, r) => n.showStillChecking(r, courtName, until),
      );
      state = state.copyWith(cardShown: true);
    }
    if (_hostClosedOccurrence(alarm.id, next)) return;
    await store.saveCheckState(state);
    if (nextCheck != null) {
      // On Android nothing else re-books this alarm — checks only reschedule
      // themselves — so a booking that failed means the cascade stops here
      // (REVIEW #22). `scheduleCheck` has already tried its coarse fallback
      // and logged; this is the layer that knows what was lost, so it says so.
      if (!await checks.scheduleCheck(alarm.id, nextCheck)) {
        final lost = nivaatOccurrenceInFlight(alarm, state, t)
            ? 'this morning stays open until the app is next opened'
            : 'the next occurrence waits for an app open';
        debugPrint('nivaat cascade for alarm ${alarm.id} has no wakeup booked '
            'after $t — $lost');
      }
    }
  }

  /// The "rang" row for a committed ring, built from its persisted [state] —
  /// used everywhere a ring is finalised after the fact (audible ring, past
  /// ring on app open, stale occurrence, alarm being edited/disabled).
  HistoryRecord _rangRecord(
    NivaatAlarm alarm,
    CheckState state, {
    required int pushSeq,
    RingDisposition disposition = RingDisposition.rang,
    String? hostEventKey,
  }) =>
      HistoryRecord(
        alarmId: alarm.id,
        courtId: alarm.courtId,
        at: state.alarmAt,
        pushSeq: pushSeq,
        checkedAt: state.lastCheckAt,
        // A ring ends the morning's checking, and it ended on the reading that
        // approved it — so these agree and the row prints no reach note.
        checkingEndedAt: state.lastCheckAt,
        outcome: CheckOutcome.rang,
        courtSpeedKmh: state.ringCourtSpeedKmh,
        rawGustKmh: state.ringRawGustKmh,
        courtSpeedLimitKmh: alarm.courtSpeedLimitKmh,
        rawGustLimitKmh: alarm.thresholds.rawGustLimit,
        volume: state.ringVolume,
        ringDisposition: disposition,
        hostEventKey: hostEventKey,
      );

  /// Next pushSeq for [alarmId]@[at] from existing history (CheckState may
  /// already be cleared when settling a pending ring).
  Future<int> _nextHistoryPushSeq(int alarmId, DateTime at) async {
    final rows = await store.loadHistory();
    var max = 0;
    for (final r in rows) {
      if (r.alarmId == alarmId && r.at == at && r.pushSeq > max) {
        max = r.pushSeq;
      }
    }
    return max + 1;
  }

  HistoryRecord _dispositionRecordFromPending(
    PendingRing pending, {
    required int pushSeq,
    required RingDisposition disposition,
    String? hostEventKey,
  }) =>
      HistoryRecord(
        alarmId: pending.alarmId,
        courtId: pending.courtId,
        at: pending.occurrenceAt,
        pushSeq: pushSeq,
        checkedAt: pending.lastCheckAt,
        checkingEndedAt: pending.lastCheckAt,
        outcome: CheckOutcome.rang,
        courtSpeedKmh: pending.courtSpeedKmh,
        rawGustKmh: pending.rawGustKmh,
        courtSpeedLimitKmh: pending.courtSpeedLimitKmh,
        rawGustLimitKmh: pending.rawGustLimitKmh,
        volume: pending.volume,
        ringDisposition: disposition,
        hostEventKey: hostEventKey,
      );

  /// Promote a still-armed `ringScheduled` CheckState into durable pending so
  /// roll-on can open the next occurrence without writing Rang or cancelling
  /// the pre-arm about to sound.
  Future<PendingRing> _holdPendingFromState(
    NivaatAlarm alarm,
    CheckState state,
  ) async {
    // Prefer whichever locker the plugin still holds for this alarm. One
    // snapshot for all three, so the answer cannot shift between lookups.
    final armed = await scheduler.scheduledAlarms();
    int pluginId = NivaatIds.ring(alarm.id);
    var role = RingLockerRole.ring;
    var scheduledFor = state.alarmAt;
    for (final entry in [
      (RingLockerRole.lateRing, NivaatIds.lateRing(alarm.id)),
      (RingLockerRole.ring, NivaatIds.ring(alarm.id)),
      (RingLockerRole.nextRing, NivaatIds.nextRing(alarm.id)),
    ]) {
      final info = armed[entry.$2];
      if (info != null) {
        role = entry.$1;
        pluginId = entry.$2;
        scheduledFor = info.dateTime;
        break;
      }
    }
    final pending = PendingRing(
      alarmId: alarm.id,
      pluginId: pluginId,
      role: role,
      occurrenceAt: state.alarmAt,
      scheduledFor: scheduledFor,
      courtId: alarm.courtId,
      volume: state.ringVolume,
      courtSpeedKmh: state.ringCourtSpeedKmh,
      rawGustKmh: state.ringRawGustKmh,
      courtSpeedLimitKmh: alarm.courtSpeedLimitKmh,
      rawGustLimitKmh: alarm.thresholds.rawGustLimit,
      lastCheckAt: state.lastCheckAt,
      rollOnDone: false,
    );
    await store.savePendingRing(pending);
    return pending;
  }

  /// Save [candidate] without writing our own `scheduledFor` over a LATER one
  /// the host has already reported for the same ring.
  ///
  /// **Both saves in the arming path go through here, and that is the point.**
  /// A deferral can land inside the microtask between `scheduleRing` accepting
  /// the ring and the pass recording it — the handler matches it (through
  /// CheckState, if the pending is not written yet) and stores the new time —
  /// and then the pass's own save put its now-stale request straight back on
  /// top. Fixing only the later of the two writes left the earlier one still
  /// clobbering it, which is exactly how this was missed the first time.
  ///
  /// Everything downstream keys on `scheduledFor`: `_recoverAmbiguousPending`
  /// compares it against what the platform holds and would read a live ring as
  /// a different one, and a second move would fall outside `_hostEventSlack`
  /// and be rejected as the wrong occurrence.
  Future<void> _savePendingKeepingHostMove(PendingRing candidate) async {
    final held = await store.loadPendingRing(candidate.alarmId);
    final hostMoved = held != null &&
        held.occurrenceAt == candidate.occurrenceAt &&
        held.pluginId == candidate.pluginId &&
        held.scheduledFor.isAfter(candidate.scheduledFor);
    await store.savePendingRing(hostMoved
        ? candidate.copyWith(scheduledFor: held.scheduledFor)
        : candidate);
  }

  /// True when the plugin still lists any ring locker for [alarmId].
  /// Bookkeeping only — never Rang proof.
  Future<bool> _pluginStillHasRing(int alarmId) async {
    final armed = await scheduler.scheduledAlarms();
    return NivaatIds.allRings(alarmId).any(armed.containsKey);
  }

  /// What a vanished ring means on THIS platform.
  ///
  /// The owed ring is gone from the plugin and is not sounding. Android can
  /// say why — a drop arrives on `Alarm.events` and the morning is recorded
  /// as `Missed` — so silence there is a genuine anomaly and the honest answer
  /// is [RingDisposition.unknown], `Couldn't confirm`.
  ///
  /// **iOS cannot, and that changes the answer entirely.** AlarmKit reports
  /// nothing it does on its own, and an alarm leaves it the moment it fires
  /// and is dismissed — which is what a perfectly ordinary morning looks like.
  /// It also never opens the app, so Nivaat is essentially never running while
  /// the alert sounds and almost never gets to see the ring as audible. Read
  /// there, "gone with nothing said" would relabel EVERY iOS ring as
  /// unconfirmed. Where the platform has no drop channel, an owed ring whose
  /// time has passed and whose handle is gone rang.
  RingDisposition get _vanishedRingDisposition => scheduler.reportsHostEvents
      ? RingDisposition.unknown
      : RingDisposition.rang;

  /// Settle a CheckState that claimed `ringScheduled` past T.
  ///
  /// Returns true when the occurrence was finalized (history written / pending
  /// cleared). False when the plugin still owes the ring — caller must hold
  /// pending rather than re-decide (which would cancel the pre-arm).
  Future<bool> _settleRingScheduled(
    NivaatAlarm alarm,
    CheckState state, {
    required DateTime now,
    required List<SavedLocation> courts,
    required bool rollOn,
    String? hostEventKey,
  }) async {
    final existing = await store.loadPendingRing(alarm.id);
    if (existing != null && existing.occurrenceAt == state.alarmAt) {
      // Pending owns settle for this occurrence — don't write Rang from
      // ringScheduled alone.
      if (await scheduler.isRinging(existing.pluginId)) {
        await _settlePending(
          existing,
          disposition: RingDisposition.rang,
          now: now,
          courts: courts,
          rollOn: rollOn,
          hostEventKey: hostEventKey,
        );
        return true;
      }
      // Still armed — including a late ring due seconds from now. Hold, do not
      // close: this is the read that used to be unconditionally null on iOS,
      // so a ring about to sound was settled out from under itself.
      if ((await scheduler.scheduledAlarms())[existing.pluginId] != null) {
        return false;
      }
      await _settlePending(
        existing,
        disposition: _vanishedRingDisposition,
        now: now,
        courts: courts,
        rollOn: rollOn,
        hostEventKey: hostEventKey,
      );
      return true;
    }

    if (await _isRingingAny(alarm.id)) {
      await _pushCard(
        state,
        (seq) => _rangRecord(alarm, state,
            pushSeq: seq, hostEventKey: hostEventKey),
        null,
      );
      await store.clearCheckState(alarm.id);
      // The morning is closed either way — the ring was audible. A roll that
      // failed is owed in the outbox and retried at the next barrier; nothing
      // here holds a pending slot whose loss would be the debt's only record,
      // which is what makes this site different from Rule 2's and the post-T
      // hold's. Same at the vanished-ring exit below.
      if (rollOn) await _rollOn(alarm, now, state.alarmAt);
      return true;
    }

    if (await _pluginStillHasRing(alarm.id)) {
      return false;
    }

    await _pushCard(
      state,
      (seq) => _rangRecord(
        alarm,
        state,
        pushSeq: seq,
        disposition: _vanishedRingDisposition,
        hostEventKey: hostEventKey,
      ),
      null,
    );
    await store.clearCheckState(alarm.id);
    if (rollOn) await _rollOn(alarm, now, state.alarmAt);
    return true;
  }

  /// **`unknown` is the only verdict a later one may replace, and only by
  /// `missed`.**
  ///
  /// `Couldn't confirm` does not mean "we decided nothing happened" — it means
  /// *we never found out*. So a known `AlarmDropped` arriving afterwards is not
  /// a competing opinion, it is the answer, and refusing it leaves the log
  /// permanently vaguer than the evidence. Every other pair is a downgrade or a
  /// duplicate and is refused: nothing replaces `missed`, and nothing replaces
  /// `rang` — a late drop after the user already stopped an audible alarm must
  /// not rewrite the morning they actually woke up to.
  ///
  /// A premature `Rang` from the pre-hold era carries no disposition at all,
  /// so [_supersedeRangWithDisposition] can still find and overwrite it.
  static bool _canReplaceVerdict(
    RingDisposition existing,
    RingDisposition incoming,
  ) =>
      existing == RingDisposition.unknown && incoming == RingDisposition.missed;

  /// Has this occurrence's ring already been settled in a way [disposition]
  /// may not improve on?
  ///
  /// Two ways to recognise a settle that has already happened: the host
  /// event's own claim key (the precise one — a redelivery of the very same
  /// drop), and any row for this occurrence already carrying a
  /// `ringDisposition` (the broad one). Only the settle path writes that field,
  /// so its presence means some run reached a verdict — and a crash between
  /// writing the row and clearing the pending slot used to make the next pass
  /// write a SECOND verdict beside the first.
  Future<bool> _dispositionAlreadyRecorded(
    PendingRing pending,
    RingDisposition disposition,
    String? hostEventKey,
  ) async {
    final rows = await store.loadHistory();
    for (final r in rows) {
      // The very same event again — nothing to add, whatever it says.
      if (hostEventKey != null && r.hostEventKey == hostEventKey) return true;
    }
    for (final r in rows) {
      if (r.alarmId != pending.alarmId || r.at != pending.occurrenceAt) continue;
      final existing = r.ringDisposition;
      if (existing == null) continue;
      if (_canReplaceVerdict(existing, disposition)) continue;
      return true;
    }
    return false;
  }

  /// Finalize [pending] with [disposition] and open the next occurrence.
  ///
  /// **The order is history, then roll-on, then clear the pending slot — and
  /// the last of those is the point.** The pending record is the only durable
  /// evidence that this occurrence is unfinished, so it is dropped after
  /// everything it guards. Clearing it first read as tidier and lost the
  /// cascade outright: a process death in the gap left `Missed` in the log
  /// with nothing anywhere saying the next occurrence still needed booking,
  /// and on Android nothing else books one — checks only ever re-book
  /// themselves, so the alarm waits for a manual app open.
  ///
  /// **Re-entry is expected, not exceptional.** Host events are delivered at
  /// least once by design and two isolates can both be told. So the write is
  /// idempotent by `hostEventKey` and by occurrence — and a repeat still
  /// finishes whatever the first attempt did not, rather than returning early,
  /// because the run it repeats may be exactly the one that died before
  /// rolling on. The accepted cost is the mirror image: a crash between the
  /// roll-on and the clear makes the next pass roll on again, which re-arms the
  /// same ring for the same instant and re-saves the same state. A duplicate
  /// roll is a no-op; a missing one is a morning that never comes.
  Future<void> _settlePending(
    PendingRing pending, {
    required RingDisposition disposition,
    required DateTime now,
    List<SavedLocation>? courts,
    bool rollOn = true,
    String? hostEventKey,
  }) async {
    // Whether the roll is still owed is read from DISK where the slot still
    // describes this occurrence. **The claim it reads is written AFTER a roll
    // that succeeded, never before one** — the sentence here used to say the
    // opposite, and it was describing a design this file had already moved
    // away from. Marking first prevents a double roll and buys it with the
    // worse failure: a drop landing mid-flight reads "already rolled", leaves
    // the roll alone, and the occurrence closes with nothing following it.
    // A double roll is a no-op, because the intent is keyed on the occurrence.
    final stored = await store.loadPendingRing(pending.alarmId);
    final rolledAlready = stored != null &&
            stored.occurrenceAt == pending.occurrenceAt
        ? stored.rollOnDone
        : pending.rollOnDone;
    final owesRoll = rollOn && !rolledAlready;

    // **One transaction: the row that records the verdict, the CheckState that
    // said the occurrence was open, and the intent to open the next one.**
    //
    // Those three are one fact — this morning is finished and tomorrow is
    // owed — and splitting them is what left the state that has to be recovered
    // from. It stops short of the roll itself, which is a platform call and
    // cannot be inside a transaction (an alarm armed in one stays armed through
    // a `ROLLBACK`). That is exactly the seam the outbox row covers: recorded
    // here, carried out below.
    //
    // The pending slot is deliberately NOT cleared here. It is the durable
    // record that this occurrence is unfinished, and it must outlive the roll —
    // see the clear at the bottom.
    await store.transaction(() async {
      // **The three log reads below stay separate calls, and the reason they
      // do has changed.** They used to be kept apart so each had a last chance
      // to notice a row another isolate had written mid-settle: with a shared
      // snapshot, `_nextHistoryPushSeq` re-derives a number already taken, and
      // `upsertHistory` keys on it, so a `Couldn't confirm` REPLACES a `Missed`
      // the other isolate had just written — exactly the downgrade
      // `_canReplaceVerdict` forbids. Inside a transaction no other isolate can
      // write here at all, so that hazard is gone and what is left is a
      // consistent snapshot by construction. They are still separate because
      // each answers a different question, not because the narrowness is doing
      // any work.
      final alreadyRecorded = await _dispositionAlreadyRecorded(
          pending, disposition, hostEventKey);
      if (!alreadyRecorded) {
        final superseded = await _supersedeRangWithDisposition(
          pending: pending,
          disposition: disposition,
          hostEventKey: hostEventKey,
        );
        if (!superseded) {
          final seq =
              await _nextHistoryPushSeq(pending.alarmId, pending.occurrenceAt);
          await store.upsertHistory(_dispositionRecordFromPending(
            pending,
            pushSeq: seq,
            disposition: disposition,
            hostEventKey: hostEventKey,
          ));
        }
      }

      // Synthesized pending (from CheckState) never lived in the pending store
      // — still clear the matching CheckState so Rule 2 cannot re-settle it.
      // Matched on the occurrence inside the DELETE rather than loaded, checked
      // and deleted: the gap in that older shape is where a roll-on writes the
      // NEXT occurrence's state, which the delete would then throw away.
      await store.clearCheckStateForOccurrence(
          pending.alarmId, pending.occurrenceAt);

      if (owesRoll) {
        await outbox.enqueue(
          _rollOnIntent(pending.alarmId, pending.occurrenceAt),
          now: now,
        );
      }
    });

    // Signal the outer evaluate (if any) to abort before re-arming.
    _markHostClosedOccurrence(pending.alarmId, pending.occurrenceAt);

    // **Whether the roll HAPPENED, not whether it was attempted.** The
    // dispatcher swallows a failed handler by design, so without asking, a roll
    // whose arming threw would look exactly like one that worked — and the
    // clear below would then drop the pending slot, which is the durable record
    // that this occurrence is unfinished.
    var rolled = true;
    if (owesRoll) {
      final alarm = await _alarmById(pending.alarmId);
      if (alarm != null) {
        // A nextRing drop closes THAT occurrence, then rolls to the one after.
        rolled = await _rollOn(alarm, now, pending.occurrenceAt);
        // **Claimed only once it is a fact.** Marking before the roll stops a
        // double roll and buys it with the worse failure, which is the same
        // trade `rollOnDone` refuses to make: the outer pass reads the mark,
        // skips its own roll, and the occurrence closes with nothing following
        // it. `_rollOn` is keyed on the occurrence, so a second attempt is a
        // no-op rather than a second morning — the mark is an optimisation, and
        // it must not outrank the truth.
        if (rolled) {
          _hostRolledOccurrences
              .add(_occurrenceKey(pending.alarmId, pending.occurrenceAt));
        }
      }
      // A deleted alarm has nothing to roll on to — but its slot must still go,
      // or every later pass re-settles a morning nobody is waiting for. That is
      // `rolled` staying true: nothing is owed, so nothing is being abandoned.
    }

    // **Only this occurrence's own slot may be cleared, matched on the
    // occurrence and never on the plugin id** — ring ids repeat daily, so last
    // Tuesday's lateRing wears tomorrow's number.
    //
    // Still last, and still the point: the roll is a whole evaluation, and it
    // is exactly where the NEXT occurrence's pending gets written. The older
    // shape re-read the slot and compared before deleting, which was a
    // check-then-act around that very write; the occurrence is in the `WHERE`
    // clause now, so there is no gap for the new ring to land in.
    //
    // **And it does not happen at all when the roll is still owed.** Before the
    // outbox this was enforced by accident — the roll threw and execution never
    // reached here — and routing it through a dispatcher that swallows turned
    // that into a silent clear. Keeping the slot means the next pass re-settles
    // (idempotently) and tries again, so there are two records of the debt
    // rather than none.
    if (rolled) {
      await store.clearPendingRingForOccurrence(
          pending.alarmId, pending.occurrenceAt);
    }
  }

  /// Overwrite a premature Rang for [pending.occurrenceAt] with [disposition]
  /// (same pushSeq). Returns true when a row was rewritten.
  ///
  /// Hold-pending (decision 3) makes a premature Rang unreachable on the
  /// normal post-T path; this remains for residual / hand-seeded state that
  /// still wrote Rang before settle. There is no `rangHistoryPushSeq` pointer
  /// — match by occurrence + outcome.
  Future<bool> _supersedeRangWithDisposition({
    required PendingRing pending,
    required RingDisposition disposition,
    String? hostEventKey,
  }) async {
    if (disposition == RingDisposition.rang) return false;
    final rows = await store.loadHistory();
    HistoryRecord? target;
    for (final r in rows) {
      if (r.alarmId != pending.alarmId || r.at != pending.occurrenceAt) {
        continue;
      }
      if (r.kind != HistoryKind.outcome) continue;
      if (r.outcome != CheckOutcome.rang) continue;
      final existing = r.ringDisposition;
      // A settled verdict is replaced only by a better-informed one — see
      // [_canReplaceVerdict]. In particular a `rang` row is a morning the user
      // woke up to, and a late drop must never rewrite it.
      if (existing != null && !_canReplaceVerdict(existing, disposition)) {
        continue;
      }
      if (target == null || r.pushSeq > target.pushSeq) target = r;
    }
    if (target == null) return false;

    await store.upsertHistory(HistoryRecord(
      alarmId: target.alarmId,
      courtId: target.courtId,
      at: target.at,
      outcome: target.outcome,
      kind: target.kind,
      pushSeq: target.pushSeq,
      checkedAt: target.checkedAt,
      watchedUntil: target.watchedUntil,
      checkingEndedAt: target.checkingEndedAt,
      courtSpeedKmh: target.courtSpeedKmh,
      rawGustKmh: target.rawGustKmh,
      courtSpeedLimitKmh: target.courtSpeedLimitKmh,
      rawGustLimitKmh: target.rawGustLimitKmh,
      volume: target.volume,
      ringDisposition: disposition,
      hostEventKey: hostEventKey ?? target.hostEventKey,
    ));
    return true;
  }

  /// Settle any pending ring the plugin no longer holds and is not sounding.
  ///
  /// **This runs on every platform** — it is the only thing that closes a
  /// morning whose ring was held pending and then simply happened while the app
  /// was not watching, which on iOS is the ordinary case rather than the
  /// exception. Skipping it there left iOS pendings on disk forever and the
  /// morning recorded nowhere at all, which is worse than mislabelling it.
  ///
  /// What differs by platform is the WORD, not whether to write one: see
  /// [_vanishedRingDisposition].
  Future<void> _recoverAmbiguousPending({required DateTime now}) async {
    final pendingList = await store.loadAllPendingRings();
    if (pendingList.isEmpty) return;
    final courts = await store.loadCourts();
    for (final pending in pendingList) {
      // Serialize with evaluate / host settle for this alarm (C1 / C2).
      await _enqueue(pending.alarmId, now: now, () async {
        // Drain again inside the lane: a drop queued after `evaluateAll`'s
        // barrier explains this exact pending, and settling first would spend
        // the occurrence on `Couldn't confirm` when `Missed` was moments away.
        await scheduler.applyHostAlarmEvents();
        final fresh = await store.loadPendingRing(pending.alarmId);
        if (fresh == null) return;
        if (await scheduler.isRinging(fresh.pluginId)) return;
        // **Read the platform INSIDE the lane, not once for the whole sweep.**
        // Everything between the outer read and here — the drain, the other
        // alarms' settles, their roll-ons — can arm or move this very id, and
        // an older snapshot would then call a ring that exists "vanished" and
        // close the morning on it.
        final armed = await scheduler.scheduledAlarms();
        // The id alone is not enough: ring ids repeat every day, so tomorrow's
        // pre-arm under the same number would make today's stale pending look
        // armed and it would never be finalised. It is only still OUR ring if
        // the platform also still has it for the time we asked for.
        final live = armed[fresh.pluginId];
        if (live != null &&
            live.dateTime.difference(fresh.scheduledFor).abs() <=
                _hostEventSlack) {
          return;
        }
        await _settlePending(
          fresh,
          disposition: _vanishedRingDisposition,
          now: now,
          courts: courts,
        );
      });
    }
  }

  Future<void> _onHostAlarmEvent(HostAlarmEvent event) async {
    final role = NivaatIds.ringRoleOf(event.id);
    final alarmId = NivaatIds.alarmIdOfRing(event.id);
    if (role == null || alarmId == null) return;

    // Same per-alarm lane as evaluate / abandon (C1). Inline when that lane is
    // already running so applyHostAlarmEvents inside a job cannot deadlock.
    if (_activeAlarmIds.contains(alarmId)) {
      await _handleHostAlarmEvent(event, role: role, alarmId: alarmId);
      return;
    }
    await _enqueue(
      alarmId,
      () => _handleHostAlarmEvent(event, role: role, alarmId: alarmId),
    );
  }

  Future<void> _handleHostAlarmEvent(
    HostAlarmEvent event, {
    required RingLockerRole role,
    required int alarmId,
  }) async {
    _inHostHandler = true;
    try {
      await _handleHostAlarmEventBody(event, role: role, alarmId: alarmId);
    } finally {
      _inHostHandler = false;
    }
  }

  Future<void> _handleHostAlarmEventBody(
    HostAlarmEvent event, {
    required RingLockerRole role,
    required int alarmId,
  }) async {
    // Idempotent: a prior settle already claimed this (id, recordedAt).
    // Still fall through to _settlePending so C2 clears leftover pending.
    final pending = await _matchPendingForHostEvent(
      event: event,
      alarmId: alarmId,
      role: role,
    );

    if (event.kind == HostAlarmEventKind.moved) {
      // Same window as a drop, and it was wrong to scope the retry to drops
      // alone: a deferral claimed with nothing to write it onto leaves
      // `scheduledFor` at the time the host has already moved away from, and
      // every later comparison keys on that. `_recoverAmbiguousPending` then
      // reads a ring the platform still holds as a DIFFERENT ring and settles
      // the morning as vanished, and a second, larger move falls outside the
      // slack and is rejected as the wrong occurrence.
      if (pending == null) {
        throw const HostAlarmEventNotReady('no pending ring to move yet');
      }
      // Ignore stale replays after fire: plugin must still show a future time.
      // These are genuine "not ours" answers, not "not yet", so they do NOT
      // ask for the event back — retrying them would only burn the attempts.
      final info = (await scheduler.scheduledAlarms())[pending.pluginId];
      if (info == null) return;
      final t = _nowFor(alarmId);
      if (!info.dateTime.isAfter(t) && !event.at.isAfter(t)) return;
      // **A deferral only ever moves a ring FORWARD**, so an event naming an
      // earlier time than the one we already hold is a replay of a move that
      // has since been superseded. Applying it rolled `06:01:00` back to
      // `06:00:30` and every later comparison keyed on the older time.
      if (event.at.isBefore(pending.scheduledFor)) return;
      // Only update when the pending still tracks a live occurrence for this
      // alarm (wrong occurrence / id reuse → ignore).
      final state = await store.loadCheckState(alarmId);
      final occurrenceOk = state == null ||
          state.alarmAt == pending.occurrenceAt ||
          pending.role == RingLockerRole.nextRing ||
          pending.role == RingLockerRole.lateRing;
      if (!occurrenceOk) return;
      // **The slot belongs to ONE occurrence, so a move for another may not
      // take it.** `savePendingRing` keys on `alarmId` alone, and
      // `_matchPendingForHostEvent` will happily synthesize a pending for a
      // different morning — so a deferral of tomorrow's `nextRing` wrote
      // straight over today's held ring and erased the only record that it was
      // still owed. Same rule the settle path's clear already follows; it was
      // applied there and not here.
      //
      // The cost of declining is a deferral we cannot store for an occurrence
      // that does not hold the slot yet. That is recoverable — the roll-on
      // arms that occurrence fresh and reads its own time back — whereas
      // losing the held pending is not.
      final held = await store.loadPendingRing(alarmId);
      if (held != null && held.occurrenceAt != pending.occurrenceAt) return;
      await store.savePendingRing(pending.copyWith(scheduledFor: event.at));
      return;
    }

    // Dropped → missed (any cause: platformRefusal, staleAtBoot, …). Known drop
    // always supersedes a premature Rang.
    // [_matchPendingForHostEvent] also synthesizes from CheckState when the
    // ring was never promoted to durable pending.
    if (pending == null) {
      // **Nothing to attach it to YET is not the same as handled.** The one
      // window left between arming a ring and recording it is a single
      // microtask as `scheduleRing`'s future completes — and a refused
      // foreground service lands in exactly those seconds (upstream #424), so
      // it is the likeliest moment for this drop to arrive. Returning here
      // marked it done and the morning was later recorded as merely
      // unconfirmed rather than missed.
      //
      // Asking for it back works here, unlike in Arunoday, because Nivaat's
      // barriers are spread through the pass rather than all inside one
      // rebuild: the very next `applyHostAlarmEvents` finds the pending
      // saved. An event that genuinely never matches — a deleted alarm, a
      // stale replay — costs three bounded attempts and a log line.
      throw const HostAlarmEventNotReady(
          'no pending ring or check state to record the drop against yet');
    }
    await _settlePending(
      pending,
      disposition: RingDisposition.missed,
      // The clock of the evaluate this handler is running inside, when there
      // is one — a settle that reached for the wall clock while the pass was
      // evaluating 06:00 rolled the cascade past a whole occurrence.
      now: _nowFor(alarmId),
      hostEventKey: event.claimKey,
    );
  }

  /// How far an event's time may sit from the ring we think it belongs to.
  ///
  /// A pre-arm is set for the occurrence's exact minute and a deferral moves it
  /// by seconds, so two minutes is generous for "the same ring" while still
  /// refusing an event for a different morning — the ids repeat daily, so
  /// yesterday's drop and today's ring wear the same number.
  static const Duration _hostEventSlack = Duration(minutes: 2);

  /// Does a `lateRing` event at [eventAt] belong to the occurrence at
  /// [occurrenceAt]?
  ///
  /// A late ring has no fixed time — it is armed "ten seconds from now" by
  /// whichever retry found calm air — so it cannot be matched by proximity to
  /// the alarm's minute like the other two lockers. **It is bounded by the
  /// occurrence's own retry window instead**, because "any lateRing event at or
  /// after `alarmAt`" is satisfied by every future morning as well: a replayed
  /// drop from last Tuesday would then close today's occurrence and roll the
  /// cascade on, one day early, on evidence a week old.
  bool _lateRingBelongsTo(
    NivaatAlarm alarm,
    DateTime occurrenceAt,
    DateTime eventAt,
  ) =>
      !eventAt.isBefore(occurrenceAt) &&
      eventAt.isBefore(
        nivaatOccurrenceEndsAfter(alarm, occurrenceAt).add(_hostEventSlack),
      );

  Future<PendingRing?> _matchPendingForHostEvent({
    required HostAlarmEvent event,
    required int alarmId,
    required RingLockerRole role,
  }) async {
    final alarm = await _alarmById(alarmId);
    final pending = await store.loadPendingRing(alarmId);
    if (pending != null) {
      final delta = pending.scheduledFor.difference(event.at).abs();
      final timeMatches = switch (role) {
        RingLockerRole.ring => delta <= _hostEventSlack,
        RingLockerRole.lateRing => alarm != null &&
            _lateRingBelongsTo(alarm, pending.occurrenceAt, event.at) &&
            delta <= _hostEventSlack,
        RingLockerRole.nextRing => delta <= _hostEventSlack,
      };
      if (timeMatches &&
          (pending.pluginId == event.id || pending.role == role)) {
        return pending;
      }
      // Fall through: another locker may still be live in CheckState (e.g.
      // nextRing while today's lateRing is held pending).
    }
    // CheckState can stand in when pending was never promoted (pre-T arm), or
    // when a different occurrence's pending occupies the one slot.
    final state = await store.loadCheckState(alarmId);
    if (state == null || !state.ringScheduled) return null;
    if (alarm == null) return null;
    final matches = switch (role) {
      RingLockerRole.ring =>
        event.at.difference(state.alarmAt).abs() <= _hostEventSlack,
      RingLockerRole.lateRing =>
        _lateRingBelongsTo(alarm, state.alarmAt, event.at),
      RingLockerRole.nextRing =>
        event.at.difference(state.alarmAt).abs() <= _hostEventSlack,
    };
    if (!matches) return null;
    return PendingRing(
      alarmId: alarmId,
      pluginId: event.id,
      role: role,
      occurrenceAt: state.alarmAt,
      scheduledFor: event.at,
      courtId: alarm.courtId,
      volume: state.ringVolume,
      courtSpeedKmh: state.ringCourtSpeedKmh,
      rawGustKmh: state.ringRawGustKmh,
      courtSpeedLimitKmh: alarm.courtSpeedLimitKmh,
      rawGustLimitKmh: alarm.thresholds.rawGustLimit,
      lastCheckAt: state.lastCheckAt,
      rollOnDone: false,
    );
  }

  /// Open the occurrence after [closed], unless an inline host settle already
  /// did.
  ///
  /// Both halves of that are needed. A settle that owned the roll has already
  /// booked tomorrow, and rolling again would pre-arm the day AFTER it. A
  /// settle that did not — because this pass had claimed `rollOnDone` before
  /// the drop landed — leaves a closed occurrence and nothing following it,
  /// and on Android nothing else ever books one.
  /// Finishes an occurrence a settle closed underneath this pass: complete the
  /// roll it may have left owed, then drop its slot — **and only once the roll
  /// is a fact**.
  ///
  /// One body for both host-closed exits, because keeping two is exactly how
  /// the earlier one drifted out of step with the later for three review rounds
  /// running. Every clause here was a separate defect:
  ///
  /// - Roll BEFORE clearing, the same order `_settlePending` uses. Clearing
  ///   first dropped the debt record a settle deliberately preserves when its
  ///   own roll failed, leaving the outbox row as the only thing still owed.
  /// - Only if the roll LANDED. The dispatcher swallows a failed handler by
  ///   design, so a roll that never happened is otherwise indistinguishable
  ///   from one that did.
  /// - Matched on the OCCURRENCE. The roll is where the next occurrence's
  ///   pending gets written, and an unqualified clear takes that away instead.
  Future<void> _finishHostClosed(
    NivaatAlarm alarm,
    DateTime t,
    DateTime next,
  ) async {
    if (await _rollOnUnlessHostDid(alarm, t, next)) {
      await store.clearPendingRingForOccurrence(alarm.id, next);
    }
  }

  /// Returns whether the next occurrence is now open — either because an inline
  /// settle already rolled it, or because this call did.
  ///
  /// **False means the roll is still owed**, and every caller that is about to
  /// drop a durable record of that debt has to check. The dispatcher swallows a
  /// failed handler by design, so a roll that never happened is otherwise
  /// indistinguishable from one that did.
  Future<bool> _rollOnUnlessHostDid(
    NivaatAlarm alarm,
    DateTime t,
    DateTime closed,
  ) async {
    // The mark is only ever set by a settle whose roll SUCCEEDED, so finding it
    // here really does mean the occurrence after `closed` is open.
    if (_hostRolledOccurrences.contains(_occurrenceKey(alarm.id, closed))) {
      return true;
    }
    return _rollOn(alarm, t, closed);
  }

  /// After finalising [closed], immediately evaluate the alarm's NEXT
  /// occurrence in the same pass: this very open/wakeup pre-arms it (iOS may
  /// never get a background slot before T) and books its first check (on
  /// Android nothing else would — checks only reschedule themselves, so
  /// returning here left the cascade dead until the next manual app open).
  /// Skipped when the "next" occurrence is still [closed] itself (a T-0 check
  /// running inside the pre-T grace), which also guarantees the recursion
  /// terminates: a genuinely future occurrence can't finalise again.
  ///
  /// `rolledOn: true` is what keeps the next occurrence's pre-arm off
  /// [closed]'s own ring locker, which may still be holding a live alarm —
  /// see [_evaluate] for why that mattered.
  /// **Records the intent before carrying it out**, so a crash cannot lose the
  /// next morning.
  ///
  /// This is the one place a database transaction genuinely could not reach.
  /// Rolling on arms a real alarm, and no `ROLLBACK` un-arms one — so the
  /// closing work commits with an outbox row beside it, and the platform call
  /// happens after. Die in between and the row is still there: the next barrier
  /// finds its lease expired and rolls on then. Before this, a process death
  /// after the settle wrote its history row and before `_evaluate` returned
  /// left the occurrence closed with nothing booked after it — and on Android
  /// nothing else ever books one, so the alarm waited for a manual app open.
  ///
  /// Dispatched **scoped to this intent** (`only:`), because this runs inside
  /// the alarm's lane: an unscoped dispatch would carry out other alarms'
  /// intents here too, and their evaluates would run outside their own lanes.
  /// Returns whether the roll actually happened.
  ///
  /// **The dispatcher never throws** — a failed handler is logged, left owed and
  /// retried on a later barrier — so a caller that needs to know cannot find out
  /// by catching. It has to ask, and `_settlePending` does: it may not drop the
  /// pending slot on the strength of a roll that did not occur.
  Future<bool> _rollOn(NivaatAlarm alarm, DateTime t, DateTime closed) async {
    final intent = _rollOnIntent(alarm.id, closed);
    await outbox.enqueue(intent, now: t);
    await outbox.dispatch(_outboxHandlersAt(t), now: t, only: intent.dedupKey);
    return await outbox.stateOf(intent.dedupKey) == OutboxState.done;
  }

  /// Carries out a roll-on intent, in the alarm's own lane.
  ///
  /// Same shape as [_onHostAlarmEvent]: inline when that lane is already
  /// running — which is the case for every [_rollOn], since it is reached from
  /// inside a pass — and queued when it is not, which is how a row recovered at
  /// a barrier gets in.
  Future<void> _runRollOnJob(OutboxJob job, DateTime? t) async {
    final alarmId = job.payload['alarmId'] as int;
    if (_activeAlarmIds.contains(alarmId)) return _rollOnFromJob(job, t);
    return _enqueue(alarmId, () => _rollOnFromJob(job, t), now: t);
  }

  Future<void> _rollOnFromJob(OutboxJob job, DateTime? t) async {
    final alarmId = job.payload['alarmId'] as int;
    final closed = DateTime.fromMicrosecondsSinceEpoch(
        job.payload['closedMicros'] as int);
    final alarm = await _alarmById(alarmId);
    // A deleted alarm has nothing to roll on to. That is DONE, not failed:
    // returning normally retires the row, where throwing would spend the retry
    // budget rediscovering that the alarm is still gone.
    if (alarm == null) return;
    // Read rather than carried: this can run at a barrier with no snapshot in
    // hand, and a court deleted since the intent was recorded should be seen.
    final courts = await store.loadCourts();
    // Always open the occurrence *after* [closed]. A nextRing drop can close a
    // morning that is still in the future relative to wall clock; using only
    // the pass clock then hits `nextOccurrence(t) == closed` and would skip the
    // cascade (H5). Prefer the later of wall clock and just-past-closed so a
    // roll that already runs after T keeps its own evaluate clock for wind
    // bookkeeping.
    final afterClosed = closed.add(const Duration(milliseconds: 1));
    final at = t ?? _nowFor(alarmId);
    await _evaluate(
      alarm,
      courts,
      now: at.isAfter(afterClosed) ? at : afterClosed,
      rolledOn: true,
    );
  }

  /// A row for [alarm]'s occurrence [at], built from the last known skip
  /// reading in [state] (windy/gusty with numbers), or "no data" if no check
  /// ever read a skip-worthy wind. `checkedAt` is [state.lastCheckAt] for a
  /// windy/gusty skip (the reading behind it) but [state.lastAttemptAt] for a
  /// no-data skip (its last try — there was no successful reading).
  ///
  /// Serves all three kinds. [watchedUntil] is the promise on a still-checking
  /// row; [checkingEndedAt] defaults to the last attempt, which is what makes
  /// an outcome row able to say "we tried at 06:30" when the last reading it
  /// can quote is 06:29 — a cancelled row passes the moment you stopped it.
  HistoryRecord _skipRecord(
    NivaatAlarm alarm,
    DateTime at,
    CheckState state, {
    HistoryKind kind = HistoryKind.outcome,
    DateTime? watchedUntil,
    DateTime? checkingEndedAt,
    required int pushSeq,
  }) {
    // A still-checking row promises a deadline; it hasn't ended yet.
    final endedAt = kind == HistoryKind.stillChecking
        ? null
        : checkingEndedAt ?? state.lastAttemptAt;
    if (state.skipCourtSpeedKmh == null) {
      return HistoryRecord(
        alarmId: alarm.id,
        courtId: alarm.courtId,
        at: at,
        kind: kind,
        pushSeq: pushSeq,
        checkedAt: state.lastAttemptAt,
        watchedUntil: watchedUntil,
        checkingEndedAt: endedAt,
        outcome: CheckOutcome.skippedNoData,
        courtSpeedLimitKmh: alarm.courtSpeedLimitKmh,
        rawGustLimitKmh: alarm.thresholds.rawGustLimit,
      );
    }
    return HistoryRecord(
      alarmId: alarm.id,
      courtId: alarm.courtId,
      at: at,
      kind: kind,
      pushSeq: pushSeq,
      checkedAt: state.lastCheckAt,
      watchedUntil: watchedUntil,
      checkingEndedAt: endedAt,
      outcome: state.skipGusty
          ? CheckOutcome.skippedGusty
          : CheckOutcome.skippedWindy,
      courtSpeedKmh: state.skipCourtSpeedKmh,
      rawGustKmh: state.skipRawGustKmh,
      courtSpeedLimitKmh: alarm.courtSpeedLimitKmh,
      rawGustLimitKmh: alarm.thresholds.rawGustLimit,
    );
  }

  /// The occurrence this evaluation is about. An in-flight occurrence
  /// (persisted state, still within the alarm's post-T retry window) wins over
  /// [NivaatAlarm.nextOccurrence], which would otherwise jump to next
  /// week/day the moment T passes.
  ///
  /// "Still in flight" is [nivaatOccurrenceInFlight] — the same rule the home
  /// countdown reads, so it runs to the end of the cap's MINUTE
  /// ([nivaatOccurrenceEndsAfter]), not to the cap instant.
  DateTime? _resolveOccurrence(
    NivaatAlarm alarm,
    CheckState? state,
    DateTime t,
  ) {
    if (!alarm.enabled) return null;
    if (state != null && nivaatOccurrenceInFlight(alarm, state, t)) {
      return state.alarmAt;
    }
    return alarm.nextOccurrence(t);
  }
}
