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
/// [courtName] is the caller's lookup, so a row whose court is gone can
/// degrade to one word instead of blanking the sheet. Orphan rows are pruned
/// on load, so that fallback is defence, not an expected path.
String nivaatHistorySub(HistoryRecord record, String? courtName) {
  final note = nivaatHistoryNote(record);
  final checked = record.kind == HistoryKind.cancelled
      ? ''
      : nivaatCheckedNote(
          record.whenChecked,
          record.at,
          tried: record.outcome == CheckOutcome.skippedNoData,
        );
  return '${courtName ?? 'court removed'} · '
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
/// order [NivaatStore.loadHistory] returns), so the newer row wins. Two live
/// rows can't tie — `upsertHistory` converges same-numbered writes onto one —
/// but every row written before push numbers existed carries 0, so a finished
/// morning from an older build would otherwise resolve to its still-checking
/// row and read as an open window.
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
String nivaatAlarmListSub(NivaatAlarm alarm, SavedLocation? court) {
  final base =
      '${fmtWeekdays(alarm.weekdays)} · ${court?.name ?? 'court removed'} '
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

/// Delay until the next wall-clock minute (:00). Countdown tickers align here
/// so "6:30 → in …" flips the moment 6:31 starts, not one minute after open.
Duration nivaatUntilNextMinute([DateTime? now]) {
  final n = now ?? DateTime.now();
  final next = DateTime(n.year, n.month, n.day, n.hour, n.minute)
      .add(const Duration(minutes: 1));
  return next.difference(n);
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

  /// Clear EVERY armed ring for this alarm — both the pre-arm and late-ring
  /// lockers, since the role we aren't looking at right now may still hold one.
  Future<void> _cancelAllRings(int alarmId) async {
    for (final id in NivaatIds.allRings(alarmId)) {
      await scheduler.cancel(id);
    }
  }

  /// Is any of this alarm's occurrences sounding? Rule 1 has to ask about both
  /// lockers: a late ring from the occurrence that just closed can still be
  /// audible after `next` has rolled on to tomorrow, and missing it would let
  /// the cascade cancel a ring that is physically going off.
  Future<bool> _isRingingAny(int alarmId) async {
    for (final id in NivaatIds.allRings(alarmId)) {
      if (await scheduler.isRinging(id)) return true;
    }
    return false;
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
      _enqueue(alarm.id, () async {
        final t = now ?? DateTime.now();
        final state = await store.loadCheckState(alarm.id);
        // The advanced counter _pushCard hands back is dropped on purpose here:
        // this occurrence is ending, and its state is cleared below, so there
        // is nothing left to number.
        if (state != null && state.ringScheduled && t.isAfter(state.alarmAt)) {
          await _pushCard(
            state,
            (seq) => _rangRecord(alarm, state, pushSeq: seq),
            null,
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
      _enqueue(next.id, () async {
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
      await _pushCard(
        state,
        (seq) => _rangRecord(alarm, state, pushSeq: seq),
        null,
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
        await _pushCard(
          stored,
          (seq) => _rangRecord(alarm, stored, pushSeq: seq),
          null,
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
      // Audible = final, so the "rang" row is written HERE — the first moment
      // the app can see the ring — not whenever the user gets around to
      // stopping it (history must show the ring while it still sounds).
      // Idempotent: the cleared state stops a second mid-ring pass relogging.
      //
      // `!t.isBefore(stored.alarmAt)` ties the row to the ring that is ACTUALLY
      // sounding. Since late rings got their own locker, the audible ring can
      // belong to the occurrence that just closed while `stored` already tracks
      // the NEXT one (pre-armed by the same `_rollOn`); without this the resync
      // during that ring would log tomorrow as "rang" — a future-dated row —
      // and wipe its cascade state. The ring itself is still protected either
      // way: this branch returns without touching the scheduler.
      if (stored != null &&
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
        if (firstRung != null) await checks.scheduleCheck(alarm.id, firstRung);
      }
      return;
    }

    // An occurrence we're no longer tracking as current (the app first ran past
    // its retry window, so `next` has already rolled on) still needs
    // finalising — the app may never have run during [T, T+cap]. A committed
    // ring fired → log "rang"; anything else (windy / gusty / no-data) is a
    // skip → log it AND post its one card, so a late first-open never silently
    // drops the occurrence. (Mutually exclusive with Rule 2, the in-window case
    // where next == stored.alarmAt.) Without this, iOS — no exact wakeups —
    // loses the whole occurrence when first opened past the cap.
    if (stored != null &&
        stored.alarmAt != next &&
        t.isAfter(stored.alarmAt)) {
      if (stored.ringScheduled) {
        await _pushCard(
          stored,
          (seq) => _rangRecord(alarm, stored, pushSeq: seq),
          null,
        );
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
    // Rule 1) already fired. Record it as "rang" instead of re-deciding with
    // newer wind. Without this, an app-open after the ring — the normal iOS
    // path, where no exact T-0 check runs — could log a ring as "skipped".
    if (state.ringScheduled && t.isAfter(next)) {
      final fired = state;
      await _pushCard(
        fired,
        (seq) => _rangRecord(alarm, fired, pushSeq: seq),
        null,
      );
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
        // At/past T this is a LATE ring (a retry found calm air), and it goes
        // in its own locker: this same pass closes the occurrence and pre-arms
        // the NEXT one, and that pre-arm would otherwise evict this ring
        // seconds before it sounds. `!next.isAfter(t)` is precisely the
        // condition under which `_rollOn` can reach a further occurrence.
        final isLate = !next.isAfter(t);
        final ringAt =
            next.isAfter(t) ? next : t.add(const Duration(seconds: 10));
        if (isLate) {
          // The occurrence's own pre-armed ring (if the ladder committed one)
          // is superseded by this later, better-informed one — drop it, or the
          // alarm sounds twice a few seconds apart.
          await scheduler.cancel(NivaatIds.ring(alarm.id));
        }
        await scheduler.scheduleRing(
          id: isLate
              ? NivaatIds.lateRing(alarm.id)
              : NivaatIds.ring(alarm.id),
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
        state = state.copyWith(
          ringScheduled: true,
          ringCourtSpeedKmh: decision.sample.courtSpeedKmh,
          ringRawGustKmh: decision.sample.rawGustKmh,
          ringVolume: decision.volume,
          lastCheckAt: t,
        );
      } else {
        // Not sounding here either, so cancelling the provisional ring is safe.
        // ONLY the pre-arm locker: the late-ring locker can hold a ring for
        // the occurrence that just closed — `_rollOn` lands here moments after
        // arming it — and clearing that would re-create the very bug the split
        // exists to fix. (This occurrence can't own a late ring itself: one
        // would have finalised it as "rang" and cleared the state.)
        // Remember the reading behind this skip (kept across later no-data
        // retries) so the final card can report the real reason.
        await scheduler.cancel(NivaatIds.ring(alarm.id));
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
    // [kNivaatWakeGrace] is zero — a wake cannot arrive early, so there is
    // nothing to forgive at this end. It stays a named constant because the
    // temptation to widen it for LATE wakes is exactly the mistake: that job
    // belongs to [nivaatOccurrenceEndsAfter], which is a different question.
    final atOrPastAlarm = !t.isBefore(next.subtract(kNivaatWakeGrace));

    // At/after T and ringing → final; we never retry a ring. The morning's
    // card comes DOWN: the ring is that morning's notification now, and a
    // "still checking" card beside a sounding alarm is just noise.
    if (atOrPastAlarm && decision != null && decision.shouldRing) {
      final ringing = state;
      final ringDecision = decision;
      await _pushCard(
        ringing,
        (seq) => HistoryRecord(
          alarmId: alarm.id,
          courtId: alarm.courtId,
          at: next,
          pushSeq: seq,
          // The check behind this ring is the one that just ran now (`t`) — on
          // time at T, or a later retry-until-calm check. Recorded so history
          // can show "checked 06:07" when that differs from the 06:00 alarm.
          // A late ring APPENDS this row; the still-checking row stays too
          // (append-only log — both moments really happened).
          checkedAt: t,
          checkingEndedAt: t,
          outcome: CheckOutcome.rang,
          courtSpeedKmh: ringDecision.sample.courtSpeedKmh,
          rawGustKmh: ringDecision.sample.rawGustKmh,
          courtSpeedLimitKmh: ringDecision.thresholds.courtSpeedLimitKmh,
          rawGustLimitKmh: ringDecision.thresholds.rawGustLimit,
          volume: ringDecision.volume,
        ),
        null,
      );
      if (ringing.cardShown) await _cancelCard(alarm.id);
      await store.clearCheckState(alarm.id);
      return _rollOn(alarm, courts, t, next);
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
      return _rollOn(alarm, courts, t, next);
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
    await store.saveCheckState(state);
    if (nextCheck != null) await checks.scheduleCheck(alarm.id, nextCheck);
  }

  /// The "rang" row for a committed ring, built from its persisted [state] —
  /// used everywhere a ring is finalised after the fact (audible ring, past
  /// ring on app open, stale occurrence, alarm being edited/disabled).
  HistoryRecord _rangRecord(
    NivaatAlarm alarm,
    CheckState state, {
    required int pushSeq,
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
