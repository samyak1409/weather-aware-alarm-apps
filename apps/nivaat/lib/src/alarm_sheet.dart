import 'dart:async';
import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:flutter/cupertino.dart'
    show
        CupertinoDatePicker,
        CupertinoDatePickerMode,
        CupertinoLocalizations,
        CupertinoTheme,
        CupertinoThemeData,
        CupertinoTextThemeData,
        DefaultCupertinoLocalizations;
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';

import 'alarm_time_conflict.dart';
import 'controller.dart';
import 'engine.dart';

/// N17's delete confirmation (2026-08-15, Samyak — the same round that put one
/// on Arunoday's location delete).
///
/// `Delete` sat beside `Save` with nothing between it and a gone alarm, in a
/// sheet you open by tapping the row you were only meaning to read.
///
/// **It names both the time and the court** (Samyak, 2026-08-15). Two alarms
/// differ by exactly those, and the editor's own `Court` row shows the DRAFT —
/// change the dropdown without saving and the row and this sentence disagree,
/// which is the moment naming it here earns its place rather than repeating
/// the screen.
///
/// Both are read off the **saved** alarm for that reason: `Delete` removes what
/// is stored, not what you have half-typed over it.
///
/// [court] is **non-null** (Samyak, 2026-08-15): deleting a court deletes its
/// alarms in the same synchronous step (N20), and only the UI isolate ever
/// writes the alarm list, so an alarm cannot outlive its court. A no-court
/// branch was written and cut — a sentence nothing could render.
///
/// **The history clause is the reassuring half.** Rows outlive their alarm —
/// only deleting the COURT removes them (N20) — and without saying so, "delete"
/// reads as "delete the mornings too", which is the reading that stops someone
/// tidying up an alarm they no longer want. [history] is counted on the alarm's
/// own id, which is never reissued (REVIEW #9), so it survives every edit to
/// the alarm's time and court.
///
/// Top-level and pure for the reason `nivaatDeleteCourtWarning` is: that one
/// shipped "1 alarm **use** Society Court" for a fortnight because it was built
/// inside a widget and no test could name it. This one counts too.
String nivaatDeleteAlarmWarning(String time, String court, int history) {
  final what = 'The $time alarm at $court';
  if (history == 0) return '$what will be deleted. Continue?';
  // The verb agrees with the count, not just the noun — N20's lesson.
  final h =
      history == 1 ? '1 history entry stays' : '$history history entries stay';
  return '$what will be deleted. Its $h in the log. Continue?';
}

/// Alarm minutes come in half hours — `:00` and `:30` only (Samyak,
/// 2026-08-25).
///
/// A product decision, deliberately not an accuracy one: Open-Meteo's
/// 15-minute values are interpolated between hourly anchors (measured), so
/// `06:07` is exactly as well-forecast as `06:00`. What the grid buys is that
/// every alarm in the list reads as chosen rather than as a stray minute.
///
/// Consequence worth knowing: N18 forbids two alarms on the same HH:MM, so the
/// ceiling on coexisting alarms falls from 1440 a day to 48. Nothing near it.
const int kNivaatAlarmMinuteInterval = 30;

/// **What this alarm would actually do, in its own numbers** (Samyak,
/// 2026-08-25) — the block above Save that turns three abstract durations
/// into three times you recognise.
///
/// Three steps and a footnote, and the footnote is where the first draft was
/// simply **wrong**: it read `04:00 – 04:30 keeps checking` on one line and
/// `04:30 you're on court` on the next, which says the alarm might ring at
/// 04:30 AND that you are on court at 04:30 — with a half-hour lead time
/// between them. Caught by Samyak.
///
/// The fix is to anchor everything on the alarm actually going off at its set
/// time, and to say separately that a windy morning shifts the whole thing
/// later. That is exactly what the engine does: `playWindow` is measured from
/// the moment the alarm really rings, so a ring rescued at 04:15 moves the
/// window to 04:45–05:15 — the note's "the times below move with it" is
/// literally true, not a simplification.
///
/// Returns rows rather than a paragraph so the widget can align the times in a
/// column; pure and top-level for the reason every other string here is —
/// a sentence built inside a widget is a sentence no test can name.
({List<(String, String)> steps, String note}) nivaatAlarmTimeline(
  NivaatAlarm alarm,
) {
  // Any date: only the clock face is rendered. Going through `DateTime` is
  // what makes an alarm late in the evening read `00:15` rather than `24:15`.
  final ring = DateTime(2026, 1, 1, alarm.hour, alarm.minute);
  final (from, to) = alarm.playWindow(ring);
  String at(DateTime d) => fmtClock(d);
  return (
    steps: [
      // Just `alarm` (Samyak, 2026-08-25): the other two lines say what
      // HAPPENS at their time, and this one only has to name the thing you
      // set at the top of the sheet.
      (at(ring), 'alarm'),
      (at(from), "you're on court"),
      // `≤`, not "under": the rule is `> limit` skips, so exactly 6 rings.
      // The same symbol the home row and the gust hint already use. "must
      // stay" rather than "stays" — it is a condition, not a prediction.
      (
        '${at(from)} – ${at(to)}',
        'wind must stay ≤${alarm.courtSpeedLimitKmh} km/h',
      ),
    ],
    note:
        "if it's too windy, it keeps checking until "
        '${at(ring.add(Duration(minutes: alarm.retryMinutesAfter)))} — '
        'the times below move with it',
  );
}

/// The time wheel's own furniture, in logical pixels: `CupertinoDatePicker`
/// pads each of its three columns by 12 either side, plus 12 at each end.
const double _kWheelFixedWidth = 120;

/// What one point of type size costs the wheel in width: two two-digit
/// columns and a colon, in Roboto, ≈2.48 — rounded up for headroom.
///
/// **Derived from font metrics, not measured on a device**, and only reachable
/// below about a 320pt screen (see [nivaatWheelFontSize]), so treat it as the
/// slope of a safety ramp rather than as a fact about any phone.
const double _kWheelWidthPerPoint = 2.5;

/// The type size for the time wheel in [available] logical pixels of width.
///
/// [full] — the clock's own 64 — whenever the sheet can hold it, which is
/// every phone still shipping. Narrower than that and it shrinks to fit
/// instead of letting the wheel overlap its own columns, which is what
/// `CupertinoDatePicker` does when its parent is too narrow: it reports a
/// layout error in debug and quietly overlaps in release.
///
/// The relation is affine, not proportional — [_kWheelFixedWidth] is spent
/// whatever the type size — so scaling the font by the width ratio would
/// under-shrink and still overlap. This solves it instead.
///
/// Takes the width it actually gets rather than the screen's (it was the
/// screen's while the wheel lived in a dialog and owned its own insets). The
/// sheet's 24 of padding either side is the caller's business, not this
/// function's.
double nivaatWheelFontSize({required double full, required double available}) {
  final fits = (available - _kWheelFixedWidth) / _kWheelWidthPerPoint;
  return fits >= full ? full : fits;
}

/// Where a NEW alarm's picker opens: **the next half-hour slot, always
/// strictly in the future** (Samyak, 2026-08-25).
///
/// The first cut floored, and floor is wrong in the one way that shows: at
/// 03:45 the sheet opened on 03:30, a time already gone, so the countdown
/// under the clock read "in 23h 45m" and a brand-new alarm's first impression
/// was one a whole day away.
///
/// **Ceiling the minute is not enough** — at 03:30:20 the ceiling of 30 is 30,
/// twenty seconds in the past, and the same 23h-something countdown comes
/// back. Flooring and then adding one whole slot lands strictly ahead of
/// [now] at every second of the hour, which is what "the next alarm I could
/// set" means.
///
/// Goes through [DateTime] rather than modular arithmetic so 23:45 wraps to
/// 00:00 instead of producing an hour of 24 — a value `NivaatAlarm` would
/// store and the picker would assert on.
(int, int) nivaatSeedAlarmTime(DateTime now) {
  final slot = DateTime(
    now.year,
    now.month,
    now.day,
    now.hour,
    now.minute - now.minute % kNivaatAlarmMinuteInterval,
  ).add(const Duration(minutes: kNivaatAlarmMinuteInterval));
  return (slot.hour, slot.minute);
}

Future<void> showAlarmSheet(
  BuildContext context,
  NivaatController c, {
  required NivaatAlarm? alarm,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AlarmSheet(c: c, existing: alarm),
  );
}

class _AlarmSheet extends StatefulWidget {
  const _AlarmSheet({required this.c, required this.existing});

  final NivaatController c;
  final NivaatAlarm? existing;

  @override
  State<_AlarmSheet> createState() => _AlarmSheetState();
}

class _AlarmSheetState extends State<_AlarmSheet> with WidgetsBindingObserver {
  // New alarms open on the next half-hour slot so the picker is already on a
  // useful time; edits keep the saved value (2026-07-22, ceil 2026-08-25).
  late int _hour;
  late int _minute;

  /// What the wheel was built with — see [_wheel]. Set once, so a rebuild
  /// mid-spin cannot re-aim it.
  late final DateTime _pickerOpenedOn;
  late int _timeUntilPlay;
  late int _minPlay;
  // A new alarm opens on the first court; an edit opens on its own.
  late String _courtId = _initialCourtId();
  // A new alarm opens on the defaults; an edit opens on what was saved, which
  // this editor is the only writer of — so both are always values the dropdown
  // and the segments actually offer.
  late int _limit =
      widget.existing?.courtSpeedLimitKmh ?? WindThresholds.defaultLimit;
  // Per-alarm retry window (30 / 60, plus a dev-gated 15), default 30.
  late int _retryMinutes =
      widget.existing?.retryMinutesAfter ?? CheckCascade.retryCapMinutesAfter;
  late final Set<int> _weekdays =
      {...(widget.existing?.weekdays ?? const {1, 2, 3, 4, 5, 6, 7})};
  // Live cue above Save — checked on open and after each time pick so
  // Save isn't the first discovery (2026-07-22).
  late String? _timeConflict;

  /// Ages the "in Xh Ym" under the clock on every wall-clock :00.
  Timer? _minuteTicker;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _hour = existing.hour;
      // **Snapped on the way in, for the same reason a new alarm is.**
      // `CupertinoDatePicker` asserts its initial minute is ON the grid, and
      // the wheel is the sheet's only display of the time now — so a stored
      // `06:17` would either crash the editor open or show `06:00` over a
      // draft that still said `06:17` and saved it back. Neither is a state
      // the app can reach today (nothing has ever written an off-grid minute
      // since the grid landed), but the two paths differing on it is the kind
      // of asymmetry that only shows up the day the grid changes.
      _minute = existing.minute - existing.minute % kNivaatAlarmMinuteInterval;
      _timeUntilPlay = existing.timeUntilPlayMinutes;
      _minPlay = existing.minPlayMinutes;
    } else {
      // Forward on the grid, because backward opens on a time that has
      // already gone ([nivaatSeedAlarmTime]).
      final (hour, minute) = nivaatSeedAlarmTime(DateTime.now());
      _hour = hour;
      _minute = minute;
      _timeUntilPlay = NivaatAlarm.defaultTimeUntilPlayMinutes;
      _minPlay = NivaatAlarm.defaultMinPlayMinutes;
    }
    _pickerOpenedOn = DateTime(2026, 1, 1, _hour, _minute);
    _timeConflict = _conflictFor(_hour, _minute);
    WidgetsBinding.instance.addObserver(this);
    _armMinuteTicker();
  }

  @override
  void dispose() {
    _minuteTicker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Same re-aim home does. Repaint FIRST: re-arming cancels the timer that
    // came due while suspended, which would otherwise have been what redrew
    // the stale minute — without this the countdown waits for the next :00.
    if (state != AppLifecycleState.resumed) return;
    setState(() {});
    _armMinuteTicker();
  }

  /// Re-armed from the clock each hop rather than `Timer.periodic`, which
  /// counts from its own last callback and so drifts off :00 by whatever the
  /// app spent suspended — see the twin in `home_screen.dart`.
  void _armMinuteTicker() {
    _minuteTicker?.cancel();
    _minuteTicker = Timer(untilNextMinute(), () {
      if (!mounted) return;
      setState(() {});
      _armMinuteTicker();
    });
  }

  /// Draft next ring for the live countdown — the time [_save] would arm, built
  /// from the picker's own values.
  ///
  /// The `enabled` / `ignoreEnabled` pair is deliberate (Samyak, 2026-07-26).
  /// The draft carries the real flag so it IS the alarm Save would write, and
  /// then the countdown is asked to disregard it: while you are editing a time,
  /// "in 7h 20m" is exactly the feedback you want, switched on or not. The home
  /// row stays silent for the same alarm — there the switch is the statement.
  /// (This used to fall out of the draft simply omitting `enabled`, which left
  /// `ignoreEnabled` unreachable and the behaviour accidental. It is a decision,
  /// so it now reads like one.)
  ///
  /// No [CheckState] on purpose: the draft is "if I save this clock/weekdays",
  /// not the live cascade. Mid-window continue edits may keep today's flight
  /// alive on save, but the countdown here still answers the draft time
  /// (2026-07-26, Samyak — picker feedback; home stays quiet beside Still
  /// checking). See SPEC / MESSAGES N17.
  DateTime? get _draftNextRing => nivaatNextRingAt(
        NivaatAlarm(
          id: widget.existing?.id ?? 0,
          hour: _hour,
          minute: _minute,
          courtId: _courtId,
          weekdays: _weekdays,
          enabled: widget.existing?.enabled ?? true,
        ),
        null,
        ignoreEnabled: true,
      );

  /// The court the dropdown opens on: a new alarm gets the first court, an
  /// edit gets its own.
  ///
  /// **No "is the saved court still there?" check** (Samyak, 2026-08-15). It
  /// guarded against a value absent from the dropdown's items, which
  /// assert-crashes `DropdownButton` — but deleting a court deletes its alarms
  /// in the same synchronous step (N20), and only the UI isolate writes the
  /// alarm list, so an alarm cannot outlive its court. `courts.first` is the
  /// genuine default for a NEW alarm and nothing else.
  String _initialCourtId() =>
      widget.existing?.courtId ?? widget.c.courts.first.id;

  String? _conflictFor(int hour, int minute) => nivaatAlarmTimeConflict(
        widget.c.alarms,
        NivaatAlarm(
          id: widget.existing?.id ?? widget.c.nextAlarmId(),
          hour: hour,
          minute: minute,
          courtId: _courtId,
        ),
      );

  /// The time picker — **the wheel IS the clock** (Samyak, 2026-08-25).
  ///
  /// It was a `TextButton` showing `04:00` that opened a dialog holding the
  /// wheel; now the wheel sits where that text was. One less tap, one less
  /// surface to dismiss, and the "in 7h 20m" under it moves as you spin
  /// rather than jumping when you press Set — the countdown was always the
  /// point of putting it there, and a modal over the top of it hid the very
  /// thing it was answering.
  ///
  /// Nothing to confirm, so there is nothing to cancel: the draft is the
  /// sheet's own state, and the sheet already has Save. Backing out of the
  /// sheet discards it exactly as it discards a changed court.
  ///
  /// **`CupertinoDatePicker` on both OSes, half-hours only.** Material's
  /// `showTimePicker` has no minute-interval API and never has
  /// (flutter#60573, open since 2020), so restricting the grid means leaving
  /// it — and having left it, an inline wheel is the shape that was available
  /// all along. Arunoday deliberately keeps `showTimePicker`: a bedtime has no
  /// wind grid to align to, so `timePickerTheme` is live code there.
  ///
  /// The restriction is a product choice, not an accuracy one. Open-Meteo's
  /// 15-minute values are interpolated between hourly anchors — measured — so
  /// an alarm at :07 is no less accurate than one at :00. What it buys is that
  /// every alarm reads as deliberate.
  Widget _wheel(BuildContext context, double width) {
    final text = Theme.of(context).textTheme;
    // **Set in the clock's own type** — it IS the clock. The wheel opened at
    // 22px under a 64px hero, so touching the biggest thing on the screen
    // produced the smallest.
    final clock = text.displayLarge!;
    // The clock's PAINTED size, text scale and all, not its declared 64: the
    // wheel pins its own scaling at 1x below, so a phone on larger text would
    // otherwise get a wheel smaller than the type around it.
    final size = nivaatWheelFontSize(
      full: MediaQuery.textScalerOf(context).scale(clock.fontSize!),
      available: width,
    );
    // Roomy enough for the glyphs: Roboto's line box runs about 1.17x the type
    // size, and a child taller than its extent is clipped by the wheel rather
    // than grown around.
    final extent = size * 1.22;
    return SizedBox(
      // **2.2 rows, not 3** (Samyak, 2026-08-25 — "the sheet feels too tall").
      // The wheel replaced an 80px line of text with 235, on a sheet that also
      // carries five settings and a four-line explainer, and it was the only
      // block spending height on something you do not read: the selected value
      // plus a HALF of each neighbour says "this scrolls" exactly as well as
      // two whole ones, on a grid whose neighbours are only ever ±30 minutes.
      // Sixty pixels back for nothing given up.
      height: extent * 2.2,
      child: CupertinoTheme(
        // The wheel draws its own text, so it needs telling about the dark
        // ground — left alone it renders near-black on near-black.
        data: CupertinoThemeData(
          brightness: Brightness.dark,
          textTheme: CupertinoTextThemeData(
            dateTimePickerTextStyle: clock.copyWith(
              fontSize: size,
              color: AppPalette.textPrimary,
            ),
          ),
        ),
        // Text scaling is pinned at 1x HERE and nowhere else in the app. The
        // wheel is already set in the largest type Nivaat has, and its width is
        // sized for exactly that — a scale on top would widen the columns past
        // what `nivaatWheelFontSize` just fitted them into, which is the
        // overlap that function exists to prevent. Nothing is lost: 64px is
        // past what an accessibility scale would be asked to reach.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1,
          child: Localizations.override(
            context: context,
            delegates: const [_PaddedHour.delegate],
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.time,
              minuteInterval: kNivaatAlarmMinuteInterval,
              use24hFormat: true,
              // The colon a clock has. Without it the wheel is two unrelated
              // number columns rather than a time.
              showTimeSeparator: true,
              itemExtent: extent,
              // **Fixed at the value the sheet opened on, never rebuilt from
              // `_hour`/`_minute`.** Every tick of the wheel calls `setState`,
              // so this widget IS rebuilt mid-spin.
              //
              // Honest about what this is: on Flutter 3.44 the picker's
              // `didUpdateWidget` ignores a changed `initialDateTime`
              // entirely, so passing a moving one happens to work today and no
              // test here can fail on it. The parameter is named `initial` and
              // documented as such — depending on it being re-read, or on it
              // being ignored, are both bets on an implementation detail. This
              // takes neither.
              initialDateTime: _pickerOpenedOn,
              onDateTimeChanged: (d) => setState(() {
                _hour = d.hour;
                _minute = d.minute;
                _timeConflict = _conflictFor(_hour, _minute);
              }),
            ),
          ),
        ),
      ),
    );
  }

  bool _saving = false;

  /// Delete, but ask first ([nivaatDeleteAlarmWarning]).
  ///
  /// The warning quotes the **saved** alarm, not the draft on screen: you are
  /// deleting what is stored, and naming a time you have only just picked would
  /// ask you to confirm the destruction of an alarm that never existed.
  Future<void> _confirmDelete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final ok = await confirmDestructive(
      context,
      title: 'DELETE ALARM',
      message: nivaatDeleteAlarmWarning(
        '${existing.hour.toString().padLeft(2, '0')}:'
        '${existing.minute.toString().padLeft(2, '0')}',
        // The SAVED court, not `_courtId`: that one is the DRAFT, and the
        // dropdown may have been changed without saving. `Delete` removes
        // what is stored, so this names what is stored.
        widget.c.courtById(existing.courtId)!.name,
        widget.c.historyForAlarm(existing.id),
      ),
    );
    if (!ok || !mounted) return;
    await widget.c.deleteAlarm(existing.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    // Guard against double-taps: a second tap would mint a second id and
    // create a duplicate alarm.
    if (_saving || _timeConflict != null) return;
    setState(() => _saving = true);
    final alarm = NivaatAlarm(
      id: widget.existing?.id ?? widget.c.nextAlarmId(),
      hour: _hour,
      minute: _minute,
      courtId: _courtId,
      courtSpeedLimitKmh: _limit,
      retryMinutesAfter: _retryMinutes,
      timeUntilPlayMinutes: _timeUntilPlay,
      minPlayMinutes: _minPlay,
      weekdays: _weekdays,
      enabled: widget.existing?.enabled ?? true,
    );
    // Belt-and-suspenders — live check already disables Save; controller
    // also no-ops. Re-check here in case alarms changed while the sheet
    // was open (another path is rare but cheap).
    final conflict = nivaatAlarmTimeConflict(widget.c.alarms, alarm);
    if (conflict != null) {
      if (mounted) {
        setState(() {
          _saving = false;
          _timeConflict = conflict;
        });
      }
      return;
    }
    final saved = await widget.c.upsertAlarm(alarm);
    if (!mounted) return;
    if (!saved) {
      // Race: another alarm took this HH:MM while the sheet was open.
      setState(() {
        _saving = false;
        _timeConflict = nivaatAlarmTimeConflict(widget.c.alarms, alarm);
      });
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final gustLimit =
        WindThresholds(courtSpeedLimitKmh: _limit).rawGustLimit;
    // Bound the sheet so large accessibility text / small phones can't
    // overflow the modal (retry row added 2026-07-26). The cap is OUTSIDE the
    // SafeArea so the status-bar / home-indicator insets come out of the 92%
    // rather than being added to it — inside, a full sheet overshot the screen.
    final maxH = MediaQuery.sizeOf(context).height * 0.92;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: SafeArea(
        // The same opening flash the settings and history sheets have, and
        // this sheet now needs it too (Samyak, 2026-08-25): with the wheel,
        // three minutes rows and the timeline it runs past the fold on every
        // phone, and nothing said so. It flashes only when the content really
        // does overflow, so a short sheet stays clean.
        child: FlashingScrollbar(
          builder: (scroll) => SingleChildScrollView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.existing == null ? 'NEW ALARM' : 'EDIT ALARM',
                  style: text.labelSmall,
                ),
                const SizedBox(height: 16),
                // The wheel where the clock used to be. `LayoutBuilder` because
                // it needs the CONTENT width — the sheet's own 24 of padding
                // either side, not the screen's — to decide whether the type
                // fits ([nivaatWheelFontSize]).
                LayoutBuilder(
                  builder: (context, box) => _wheel(context, box.maxWidth),
                ),
                // Always built, even when blank — an empty Text still lays out a
                // full line box, so this row is exactly as tall with or without a
                // countdown. That kills a 24px jump: the label blinks out the
                // moment you deselect your last weekday, and because a bottom
                // sheet is anchored to the bottom edge, a collapsing slot doesn't
                // pull the rows below it up — it drops the hero wheel and the
                // title DOWN by the slot's whole height (measured). And it
                // does that WITHOUT pinning a height that large accessibility
                // text would be clipped by (at 2x the label wants 40 logical
                // pixels, not 32).
                //
                // **Both gaps are mine now, and both are wider** (Samyak,
                // 2026-08-25). Above used to be whatever the wheel's bottom
                // row happened to leave — that was the time button's own
                // padding until the wheel moved inline, and the wheel gives
                // back much less, which left this line crowded against it.
                //
                // Still asymmetric, 8 over 18: the line belongs to the clock
                // above it, not to the day chips below, and the eye reads that
                // from the gaps before it reads the words. Two numbers, one
                // intent — but they are not a matched pair, so don't tidy them
                // into one constant.
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 18),
                  child: Center(
                    // **The conflict TAKES this slot rather than adding a line
                    // of its own** (Samyak, 2026-08-25).
                    //
                    // It sat above Save first, in the same grey as the
                    // timeline's footnote at the far end of a sheet that now
                    // scrolls — so it read as one more line of that block, and
                    // you met the disabled Save before the reason for it. Then
                    // it moved here as an EXTRA line in brighter type, which
                    // shifted the whole sheet the instant it appeared and
                    // shouted while it did.
                    //
                    // Replacing the countdown costs nothing and fixes both:
                    // this slot is already built at a fixed line height for
                    // exactly that reason, so nothing moves — and the
                    // countdown it displaces is meaningless anyway, because
                    // this time cannot be saved. One line, one voice, one
                    // place.
                    child: Text(
                      _timeConflict ?? nivaatInLabel(_draftNextRing),
                      textAlign: TextAlign.center,
                      style: text.bodyMedium,
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _DayChip(
                          label: const [
                            'M',
                            'T',
                            'W',
                            'T',
                            'F',
                            'S',
                            'S',
                          ][d - 1],
                          selected: _weekdays.contains(d),
                          onTap: () => setState(() {
                            if (!_weekdays.remove(d)) _weekdays.add(d);
                          }),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                // Row, not ListTile — same reason as the Keep-checking row below.
                // The old cap was a fraction of the SCREEN (0.67) while ListTile
                // divides the TILE (screen − 48 of sheet padding) and the title's
                // own width never entered the sum: "Court" + ListTile's 16 gap
                // needs ~58 in Roboto, so the row only fit on screens ≥ ~321 — and
                // at 2x text the title doubles and needs ≥ ~448, which no phone
                // has in portrait. Past that, ListTile asserts. Flex negotiates it
                // at layout time instead, so the title can be squeezed but never
                // starved, at any width or text scale (2026-07-26). 5:2 ≈ the same
                // 71/29 split the tuned 0.67 gave at normal text.
                //
                // Selected + menu both wrap (no ellipsis); `itemHeight: null` so
                // wrapped / large-accessibility lines aren't clipped at the 48px
                // default. Open menu ≤ ~1/3 screen (2026-07-22, tuned 07-23).
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      // bodyLarge explicitly: outside ListTile a bare Text
                      // inherits bodyMedium — 14px secondary grey — which
                      // quietly demoted this label below the two beside it.
                      Expanded(
                        flex: 2,
                        child: Text('Court', style: text.bodyLarge),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 5,
                        child: LayoutBuilder(
                          builder: (context, box) => DropdownButton<String>(
                            value: _courtId,
                            isExpanded: true,
                            itemHeight: null,
                            underline: const SizedBox.shrink(),
                            menuMaxHeight:
                                MediaQuery.sizeOf(context).height * 0.33,
                            selectedItemBuilder: (context) => [
                              for (final court in widget.c.courts)
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: Text(
                                    court.name,
                                    textAlign: TextAlign.end,
                                  ),
                                ),
                            ],
                            items: [
                              for (final court in widget.c.courts)
                                DropdownMenuItem(
                                  value: court.id,
                                  // The menu is as wide as the button, so take
                                  // the real laid-out width rather than
                                  // recomputing the old screen fraction.
                                  child: SizedBox(
                                    width: box.maxWidth,
                                    child: Text(court.name),
                                  ),
                                ),
                            ],
                            onChanged: (v) => setState(() => _courtId = v!),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Max wind at court'),
                  subtitle: Text(
                    'Gust guard auto: ≤${gustLimit.round()} km/h',
                    style: text.bodyMedium,
                  ),
                  trailing: DropdownButton<int>(
                    value: _limit,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (
                        var k = WindThresholds.minLimit;
                        k <= WindThresholds.maxLimit;
                        k++
                      )
                        DropdownMenuItem(value: k, child: Text('$k km/h')),
                    ],
                    onChanged: (v) => setState(() => _limit = v!),
                  ),
                ),
                // **Chronological order — Keep, Time, Minimum** (Samyak,
                // 2026-08-25). I argued for condition-then-fallback, which put
                // Keep checking last; his order is the order the morning
                // actually happens in, and it is the same order the timeline
                // below reads. Rows and timeline reinforcing each other beats
                // either one being individually better argued.
                _PlayRow(
                  label: 'Keep checking',
                  hint:
                      'If it\'s too windy, keep watching this long and ring '
                      'when the wind drops.',
                  value: _retryMinutes,
                  options: CheckCascade.retryMinutesOptions,
                  onChanged: (v) => setState(() => _retryMinutes = v),
                ),
                const SizedBox(height: 16),
                // **The wind is checked for when you PLAY, not for when the
                // alarm rings** — these two rows are that whole idea.
                //
                // The hint leads with the ANCHOR (Samyak, 2026-08-25). It used
                // to open with the activities and say what they were measured
                // from only in its second sentence, while `in 23h 45m` sat two
                // rows above — so the reader's live anchor was *now*, and 30m
                // read as half an hour from this moment.
                _PlayRow(
                  label: 'Time until you play',
                  hint:
                      'Starts when the alarm rings — getting ready, travel, '
                      'warm-up.',
                  value: _timeUntilPlay,
                  options: NivaatAlarm.timeUntilPlayOptions,
                  onChanged: (v) => setState(() => _timeUntilPlay = v),
                ),
                const SizedBox(height: 16),
                _PlayRow(
                  label: 'Minimum play time',
                  hint:
                      'The alarm only rings if the wind stays low for this '
                      'whole time.',
                  value: _minPlay,
                  options: NivaatAlarm.minPlayOptions,
                  onChanged: (v) => setState(() => _minPlay = v),
                ),
                const SizedBox(height: 24),
                _Timeline(
                  alarm: NivaatAlarm(
                    id: widget.existing?.id ?? 0,
                    hour: _hour,
                    minute: _minute,
                    courtId: _courtId,
                    courtSpeedLimitKmh: _limit,
                    retryMinutesAfter: _retryMinutes,
                    timeUntilPlayMinutes: _timeUntilPlay,
                    minPlayMinutes: _minPlay,
                    weekdays: _weekdays,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (widget.existing != null)
                      TextButton(
                        onPressed: _confirmDelete,
                        child: const Text(
                          'Delete',
                          style: TextStyle(color: AppPalette.textSecondary),
                        ),
                      ),
                    const Spacer(),
                    FilledButton(
                      onPressed:
                          _weekdays.isEmpty || _saving || _timeConflict != null
                          ? null
                          : _save,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The block above Save: [nivaatAlarmTimeline], laid out as a two-column
/// list so the times line up whatever they say.
///
/// **Measured, not tabled** (2026-08-25). A `Table` with an intrinsic first
/// column aligned the steps for free, but a `TableRow` cannot span columns,
/// and the note has to run the FULL width from the left edge — indented into
/// the second column it read as a fourth step rather than as a footnote on the
/// line above. So the width of the time column is measured off the labels
/// themselves with a [TextPainter] and the rows are plain [Row]s.
///
/// Measured rather than a constant because the widest label is a RANGE
/// (`04:30 – 05:00`), roughly twice a bare time and twice that again at 2x
/// accessibility text — any hand-picked number either wastes a third of the
/// row at 1x or crushes the words at 2x. Three short strings per build.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.alarm});

  final NivaatAlarm alarm;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final timeline = nivaatAlarmTimeline(alarm);
    final style = text.bodyLarge!;
    final scaler = MediaQuery.textScalerOf(context);
    var column = 0.0;
    for (final step in timeline.steps) {
      final painter = TextPainter(
        text: TextSpan(text: step.$1, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      column = math.max(column, painter.width);
    }
    return LayoutBuilder(
      builder: (context, box) {
        // **Two columns while the times leave room for words, stacked when they
        // do not.** At 2x accessibility text `04:30 – 05:00` wants around 210 of
        // a 342pt sheet, and a column that wide leaves the other half of the
        // sentence wrapping in a gutter — so past 45% the step becomes two
        // lines, time over words, and the alignment it was buying is worth
        // nothing anyway.
        final stacked = column + 16 > box.maxWidth * 0.45;
        Widget row((String, String) step) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.$1, style: style),
                    Text(step.$2),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: column + 16,
                      child: Text(step.$1, style: style),
                    ),
                    Expanded(child: Text(step.$2)),
                  ],
                ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Not "YOUR MORNING" (Samyak, 2026-08-25). The codebase calls an
            // occurrence a morning everywhere — the story test, the card
            // comments — and that leaked onto a screen where it is simply
            // wrong: nothing stops you setting this alarm for 15:00.
            //
            // And not the "WHAT HAPPENS" that replaced it either: this block
            // describes the DRAFT on screen, not an alarm as saved, and it is
            // the only heading of the three that says so.
            Text('IF YOU SAVE THIS', style: text.labelSmall),
            const SizedBox(height: 12),
            row(timeline.steps.first),
            // Full width, from the left edge: it is a note on the line above,
            // not a step of its own, and the steps' own column is what it must
            // NOT line up with.
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(timeline.note, style: text.bodyMedium),
            ),
            for (final step in timeline.steps.skip(1)) row(step),
          ],
        );
      },
    );
  }
}

/// One label + hint + segmented trailer — **the shape all three minutes rows
/// share**, Keep checking included since 2026-08-25.
///
/// Extracted when the play-window pair arrived so three rows cannot drift into
/// three slightly different rows. Keep checking kept its own hand-built `Row`
/// and its own `_RetrySegmented` for a day; both are gone, because a row that
/// looks like the others but is built differently is the thing this class
/// exists to prevent.
///
/// The label is an explicit `bodyLarge`: a bare `Text` outside `ListTile`
/// inherits `bodyMedium`, which would render 14px grey beside its 16px white
/// neighbours — the exact regression `alarm_sheet_layout_test` pins.
class _PlayRow extends StatelessWidget {
  const _PlayRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final int value;

  /// The ordinary choices. The dev-gated extra is added by
  /// [_MinutesSegmented], which is the only place that watches the gate.
  final List<int> options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: text.bodyLarge),
              const SizedBox(height: 2),
              Text(hint, style: text.bodyMedium),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _MinutesSegmented(value: value, base: options, onChanged: onChanged),
      ],
    );
  }
}

/// Compact trailing segments — 30 / 60 min, plus [kDevMinutesOption] behind
/// the gate — in the day-chip accent language. Width tracks option count, so
/// the control is a trailer at either size.
///
/// **Every minutes row gets the dev extra now** (Samyak, 2026-08-25). It was
/// Keep checking's alone, which made a test morning half-fast: the retry
/// window shrank to 15 minutes while the play window it was retrying stayed
/// half an hour out and half an hour long.
class _MinutesSegmented extends StatelessWidget {
  const _MinutesSegmented({
    required this.value,
    required this.base,
    required this.onChanged,
  });

  final int value;
  final List<int> base;
  final ValueChanged<int> onChanged;

  /// Listens rather than reads: the gate is seven taps away on the home
  /// screen, so it cannot flip while this sheet is up — but a widget that
  /// silently depends on a notifier it never subscribes to is a bug waiting
  /// for the day something else can flip it.
  ///
  /// One class, not two: the options and the control they draw were split
  /// while `_RetrySegmented` still existed beside them, and once it went the
  /// inner half had exactly one caller left.
  @override
  Widget build(BuildContext context) {
    // "60m" is three glyphs in a box the size of a one-glyph day chip, so this
    // is the tightest text in the sheet: measured, it starts clipping just past
    // 1.3x and loses half the label at 2x — and the ClipRRect below hides that
    // as a silent crop instead of an overflow stripe. Compact segmented
    // controls clamp their own scaling (iOS does the same); the label and hint
    // beside it still scale all the way, so nothing becomes unreadable. The box
    // grows by the SAME clamped factor, so the fit holds at every scale.
    final f = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);
    return ValueListenableBuilder<bool>(
      valueListenable: DevMode.enabled,
      builder: (context, devMode, _) {
        final options =
            minuteOptionsFor(base: base, devMode: devMode, selected: value);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppPalette.hairline),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(
              width: options.length * 52 * f,
              height: 36 * f,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: Row(
                  children: [
                    for (var i = 0; i < options.length; i++) ...[
                      if (i > 0)
                        Container(width: 1, color: AppPalette.hairline),
                      Expanded(
                        child: _Segment(
                          minutes: options[i],
                          selected: value == options[i],
                          onTap: () => onChanged(options[i]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.minutes,
    required this.selected,
    required this.onTap,
  });

  final int minutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Compact trailing labels — "30m" / "60m", and "1m" behind the gate.
    final label = '${minutes}m';
    return Material(
      color: selected ? AppPalette.wind : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Center(
          // Same type as _DayChip two rows up — selection reads from the wind
          // fill and the black-on-accent text, never from extra weight (the
          // quiet styles stay w400 in both type modes; see CLAUDE.md).
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: selected ? AppPalette.trueBlack : AppPalette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? AppPalette.wind : Colors.transparent,
          border: Border.all(
            color: selected ? AppPalette.wind : AppPalette.hairline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? AppPalette.trueBlack : AppPalette.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Zero-pads the wheel's hour, so it reads `06` like the clock above it
/// (Samyak, 2026-08-25).
///
/// Flutter's built-in [DefaultCupertinoLocalizations] returns a bare `6`
/// while its minute column pads to `00`, which put `6 : 30` under a clock
/// showing `06:30` — the one detail that still gave away that the wheel was a
/// borrowed control rather than the thing you tapped.
///
/// [isSupported] answers true for every locale on purpose: this app ships no
/// translations at all, so the parent already resolves to these same English
/// strings whatever the phone is set to — and zero-padding two digits is not
/// a language decision. Answering false for anything else would hand back a
/// wheel that pads on some phones and not others.
class _PaddedHour extends DefaultCupertinoLocalizations {
  const _PaddedHour();

  static const LocalizationsDelegate<CupertinoLocalizations> delegate =
      _PaddedHourDelegate();

  @override
  String datePickerHour(int hour) => hour.toString().padLeft(2, '0');
}

class _PaddedHourDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _PaddedHourDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      SynchronousFuture<CupertinoLocalizations>(const _PaddedHour());

  @override
  bool shouldReload(_PaddedHourDelegate old) => false;
}
