/// Every **composed** Arunoday string, built here as pure functions rather
/// than inline in a widget (MESSAGES.md A1–A16).
///
/// Why this file exists: a string built inside a `build()` is a string no test
/// can name, so its rarer branches ship unread. Nivaat learned this three
/// times — `nivaatHistoryLine`, `nivaatHistorySub`, and `nivaatDeleteCourtWarning`,
/// the last of which had been rendering "**1 alarm use** Society Court" because
/// MESSAGES.md wrote the singular as `{n} alarm(s)` and nobody ever saw it
/// (2026-07-26). Arunoday's lines are the branchiest in either app — the
/// bedtime line alone has five optional clauses — so they get the same
/// treatment.
///
/// Static one-off labels (`ARUNODAY`, `SETTINGS`, the empty state) stay in
/// their widgets: they have no branches to hide, and `message_test` asserts
/// them by rendering the real screen instead.
library;

import 'package:core/core.dart';

// ── A1–A3 · notification titles and bodies ──────────────────────────────────

/// **The app's own name is deliberately absent** (2026-08-13, Samyak — the
/// rule Nivaat's titles have followed since 2026-07-22). Android prints
/// "Arunoday" in the notification header directly above the title, so the
/// prefix spent the scannable head of the line saying it twice; on iOS the
/// title is AlarmKit's `label`, shown inside the app's own alert. Either way
/// the app is already identified before this string is read.
const String kArunodayWakeTitle = 'Dawn';
const String kArunodayBedtimeTitle = 'Bedtime';
const String kArunodayBedtimeBody = 'Wind down — dawn comes early.';

/// A3's body — **which** call this is. The bedtime alarm itself was the first,
/// so the first `+1h` re-ring is the `Second call`.
///
/// It was the fixed string `Second call — dawn does not snooze.` until
/// 2026-08-13, and that was wrong from the third push on: `+1h` can be taken
/// again every time the re-ring sounds, because a re-ring is itself a bedtime
/// alarm. Counting is the honest version and also the pointed one — `Fourth
/// call` says something a generic line cannot.
///
/// **The words run to `Twenty-fourth`, which is the real ceiling** (Samyak,
/// 2026-08-13, worked out from the worst case rather than guessed): a push is
/// refused once it would land at or after the next wake
/// ([ArunodayController.canDelayBedtime]), each one is an hour, and a bedtime
/// is at most 24 hours from the wake it protects. Wake 00:00 with bedtime
/// 00:01 is the longest night there is — 01:01 is the second call, 23:01 the
/// twenty-fourth, and the push it offers would land at 00:01, past the wake.
/// A slower hand only makes the run shorter, since the hour counts from the
/// tap and not from the ring.
///
/// **`Still up` is out of reach while the wake alarm is ON, and reachable the
/// moment it is off** — [ArunodayController.canDelayBedtime] allows every push
/// when there is no wake to protect, so the cap goes with it and the
/// twenty-fifth call has no ordinal left. It is a real line, not the `—`-clock
/// kind of defence it was first written up as.
String arunodayBedtimeAgainBody(int call) {
  // Indexed from the SECOND call, which is the first re-ring — `call` counts
  // rings and the bedtime alarm itself was the first, so there is no ordinal
  // here for 0 or 1 and both fall through to `Still up` with everything past
  // the ceiling.
  const words = [
    'Second', 'Third', 'Fourth', 'Fifth', 'Sixth', 'Seventh', 'Eighth',
    'Ninth', 'Tenth', 'Eleventh', 'Twelfth', 'Thirteenth', 'Fourteenth',
    'Fifteenth', 'Sixteenth', 'Seventeenth', 'Eighteenth', 'Nineteenth',
    'Twentieth', 'Twenty-first', 'Twenty-second', 'Twenty-third',
    'Twenty-fourth',
  ];
  final i = call - 2;
  return (i < 0 || i >= words.length)
      ? 'Still up — dawn does not snooze.'
      : '${words[i]} call — dawn does not snooze.';
}

/// A1's body. "First light" is only honest when the wake IS the dawn, so a
/// non-zero offset names the offset instead.
///
/// No space before the offset — `Dawn+0:20` is ONE value, the way A6's
/// `DAWN+0:20` and A7's `AUTO+0:30` already read (2026-07-22).
String arunodayWakeBody(String locationName, int offsetMinutes) =>
    offsetMinutes == 0
        ? 'First light at $locationName. Good morning.'
        : 'Dawn${fmtOffset(offsetMinutes)} at $locationName. Good morning.';

// ── A4 · bedtime ritual on the ring screen ──────────────────────────────────

/// `WAKE TOMORROW 07:11` — which wake this bedtime is protecting. A bedtime
/// past midnight wakes you the same calendar day, hence `TODAY`.
String arunodayRitualWakeLine(DateTime nextWake, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = nextWake.year == n.year &&
      nextWake.month == n.month &&
      nextWake.day == n.day;
  return 'WAKE ${today ? 'TODAY' : 'TOMORROW'} ${fmtClock(nextWake)}';
}

// ── A6–A8 · home screen ─────────────────────────────────────────────────────

/// Whole minutes from [now] until [t], both truncated to the minute first so
/// the number agrees with the clocks it is printed under. Null — nothing to
/// count down to — for a null [t] and for one already past.
int? _minutesUntil(DateTime? t, DateTime? now) {
  if (t == null) return null;
  final n = now ?? DateTime.now();
  final mins = DateTime(t.year, t.month, t.day, t.hour, t.minute)
      .difference(DateTime(n.year, n.month, n.day, n.hour, n.minute))
      .inMinutes;
  return mins < 0 ? null : mins;
}

/// ` · IN 7H 22M` until [t]. Empty when [t] is null or already past.
///
/// ALL-CAPS here and sentence-case in Nivaat: this is Arunoday's label strip,
/// which is entirely `labelSmall` caps, while Nivaat's countdown is body text
/// beside a clock (see `nivaatInLabel`).
String arunodayInLabel(DateTime? t, {DateTime? now}) {
  final mins = _minutesUntil(t, now);
  if (mins == null) return '';
  return ' · IN ${fmtDuration(mins.toDouble()).toUpperCase()}';
}

/// A6's label line under the wake clock: `WAKE · DAWN+0:20 · IN 7H 22M`.
///
/// `IN …` and `OFF` are opposites sharing the final slot — a switched-off
/// alarm must never advertise a ring.
String arunodayWakeLine({
  required int offsetMinutes,
  required bool enabled,
  DateTime? nextWake,
  DateTime? now,
}) =>
    'WAKE · DAWN${fmtOffset(offsetMinutes)}'
    '${enabled ? arunodayInLabel(nextWake, now: now) : ' · OFF'}';

/// A7's label line under the bedtime clock, five clauses long:
/// `BEDTIME · AUTO+0:30 · AGAIN 22:56 · 8H 45M TONIGHT · IN 3H 05M`.
///
/// [mode] is [ArunodayController.bedtimeModeDescription] (`Auto` / `Auto+0:30`),
/// upper-cased here so the caller never has to remember to. [again] is a
/// pending "sleep late" re-ring, [sleepMinutes] tonight's sleep if it can be
/// computed, and the tail is the same IN/OFF pair as A6.
String arunodayBedtimeLine({
  required String mode,
  required bool enabled,
  DateTime? again,
  double? sleepMinutes,
  DateTime? nextRing,
  DateTime? now,
}) =>
    'BEDTIME · ${mode.toUpperCase()}'
    '${again == null ? '' : ' · AGAIN ${fmtClock(again)}'}'
    '${sleepMinutes == null ? '' : ' · ${fmtDuration(sleepMinutes).toUpperCase()} TONIGHT'}'
    '${enabled ? arunodayInLabel(nextRing, now: now) : ' · OFF'}';

/// A8's footer: `Dawn today 06:51 · Sunrise 07:18`. [rolled] is true once
/// today's dawn has passed and the line is quoting tomorrow's.
String arunodayFooterLine(DateTime dawn, DateTime? sunrise,
        {required bool rolled}) =>
    'Dawn ${rolled ? 'tomorrow' : 'today'} ${fmtClock(dawn)}'
    '${sunrise == null ? '' : ' · Sunrise ${fmtClock(sunrise)}'}';

// ── A13–A15 · settings ──────────────────────────────────────────────────────

/// A13: what the year does to your sleep at this latitude.
String arunodaySleepReadout(SleepPlanResult plan) =>
    'Year here: sleep ${fmtDuration(plan.minSleepMinutes)} (summer) to '
    '${fmtDuration(plan.maxSleepMinutes)} (winter) — the natural swing of '
    'dawn at this latitude.';

/// `in 7h 22m` until [t] — the settings pickers' live feedback (A14/A15),
/// answering "what would this actually do?" while you nudge the time.
///
/// Sentence-case and unprefixed, unlike [arunodayInLabel]: it stands alone
/// under the dialog's own clock, among lower-case hints, which is Nivaat's
/// editor exactly (`nivaatInLabel`) rather than home's caps strip. Same
/// minute-truncated number underneath.
///
/// **[t] is non-null and there is no empty branch** (Samyak, 2026-08-15). It
/// used to take a nullable and render `''`, described as defence — but a
/// bedtime is a clock time and always has a next occurrence, and a drafted
/// wake offset walks the whole window (`ArunodayController.draftWakeRing`), so
/// even −12h lands on the following morning rather than behind you. Nothing
/// reached the branch, so it was a line nobody could read and one more thing
/// to keep true.
String arunodayPickerInLabel(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  // Both truncated to the minute first, so the number agrees with the clock it
  // is printed under.
  final mins = DateTime(t.year, t.month, t.day, t.hour, t.minute)
      .difference(DateTime(n.year, n.month, n.day, n.hour, n.minute))
      .inMinutes;
  return 'in ${fmtDuration(mins.toDouble())}';
}

/// A14's hint. [autoMinutes] is the SLEEP PLAN's bedtime — what the row would
/// read at offset 0 — so the hint quotes it whether or not you have nudged
/// bedtime off it. That is the whole point: it is the anchor your offset is
/// measured from.
///
/// Takes a plain `int` since 2026-07-31. It used to be nullable, with the null
/// branch rendering `manual`, and that was wrong twice: the word named the
/// wrong thing (a manually-set bedtime is `bedtimeOffsetMinutes`, which leaves
/// the auto value perfectly quotable), and the state it stood for — no sleep
/// plan, i.e. no location — cannot reach this dialog.
///
/// **That unreachability now rests on a different fact** (2026-08-15): settings
/// used to open only from the armed home screen, and opens from the empty one
/// too since the tune icon moved onto both. What keeps this dialog out of the
/// no-location state is that the row which opens it is not built until there is
/// a location — see `_SettingsPageState.build`. Same for
/// [arunodayWakeOffsetHint].
String arunodayBedtimePickerHint(int autoMinutes) =>
    'auto is ${fmtMinutesOfDay(autoMinutes.toDouble())}'
    ' · tap the time to pick exactly';

/// A15's hint — anchor first, then the result: `dawn 06:51 · wake 07:11`.
///
/// [dawn] is non-null for the same reason [arunodayBedtimePickerHint]'s
/// argument is: with no location the row that opens this dialog is not built at
/// all, and a location that has no daily dawn is refused when you add it. The
/// old `relative to civil dawn` fallback was unreachable, and it took the
/// dialog's wake↔bedtime collision check down with it — that check short-
/// circuits on a null dawn, so the one state that produced the fallback string
/// was also the one state where Save stopped being validated.
String arunodayWakeOffsetHint(DateTime dawn, int offsetMinutes) =>
    'dawn ${fmtClock(dawn)} · wake '
    '${fmtClock(dawn.add(Duration(minutes: offsetMinutes)))}';

// ── A11 · the LOCATIONS section ─────────────────────────────────────────────

/// What the LOCATIONS section says when it is empty (2026-08-15).
///
/// **A state that could not be reached until this build.** Settings opened only
/// from the armed home screen, so the section always had at least one row and
/// never needed an empty state; now that the tune icon sits on the empty home
/// too, an empty LOCATIONS is the first thing a new user meets there — and a
/// bare header with a `+` beside it says nothing about what a location is for.
/// Nivaat's courts have had this line (N19) since the sheet existed.
///
/// Names both alarms, because the wake is the obvious one and the bedtime is
/// the one you would not guess also hangs off the dawn here.
const String kArunodayNoLocationsYet =
    'Add a location — the wake and bedtime alarms follow its dawn.';

/// The delete-location confirmation (2026-08-15, Samyak — modelled on N20, and
/// asked for **every** delete rather than only the destructive one).
///
/// Three shapes, and the split is the whole reason this is a builder: one tap
/// on the bin can mean three different things, and only the last of them is
/// obvious from the row.
///
/// [isActive] is measured against the *effective* active location — the stored
/// id, or the first location when that is null — because that fallback is what
/// the alarms really follow. [nextActiveName] is the place that inherits it,
/// null only when nothing is left.
String arunodayDeleteLocationWarning(
  String name, {
  required bool isActive,
  String? nextActiveName,
}) {
  if (isActive && nextActiveName == null) {
    // The tap that silently switched everything off. It is the one delete that
    // costs the user their alarms, so it is the one that has to say so.
    return 'Deleting $name leaves no location, so the wake and bedtime '
        'alarms stop until you add one. Continue?';
  }
  if (isActive) {
    // "will start following", not "will follow" (Samyak, 2026-08-15): the
    // alarms are following something already, so the plain future reads as a
    // description of the status quo rather than as the change you are about
    // to make.
    return '$name is the active location — the alarms will start following '
        '$nextActiveName instead. Continue?';
  }
  return '$name will be removed. The alarms are unaffected. Continue?';
}

// ── A16 · place-picker refusals ─────────────────────────────────────────────

/// Refused at add time, so the no-dawn state can never be reached at all — it
/// replaced a whole screen you could strand yourself on.
const String kArunodayNoDawnHere =
    'No daily dawn here (polar) — Arunoday needs a real dawn.';

/// Arunoday dedupes by **dawn time**: two towns that share a dawn are one
/// alarm. (Nivaat dedupes by distance instead — N21.)
String arunodaySameDawn(String name) => 'Same dawn as $name — already added.';

// ── X3 · notifications-off banner (Arunoday's variant) ──────────────────────

/// Android-only: under AlarmKit-only iOS, Arunoday posts zero iOS
/// notifications, so there is nothing to grant and no banner to show
/// (2026-07-20). A constant so `message_test` can assert it without mounting a
/// banner whose visibility depends on a real permission answer.
///
/// It used to add "and bedtime reminders can't appear", which was false
/// (2026-07-31): the bedtime is an **alarm** (A2/A3), not a separate reminder
/// — it still rings with notifications off, it just rings with nothing on
/// screen, which is exactly what the first clause already says. Arunoday posts
/// no other notification of any kind, so there is nothing left to lose here.
const String kArunodayNotificationsOff =
    'Notifications are off — a ringing alarm shows nothing on screen '
    '(sound only, no Stop).';
