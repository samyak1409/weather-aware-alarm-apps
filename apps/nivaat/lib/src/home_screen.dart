import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'alarm_sheet.dart';
import 'background_banner.dart';
import 'controller.dart';
import 'courts.dart';
import 'engine.dart';
import 'screenshot_harness.dart';
import 'settings_sheet.dart';

/// X3's two Nivaat variants. Android's ring shows an on-screen Stop, so losing
/// notifications costs strictly more there; iOS rings through AlarmKit, whose
/// alert is the OS's own. Named constants so `message_test` can assert BOTH —
/// only one is ever reachable on a given device, and the unreachable one is
/// exactly the kind of string that rots unseen (MESSAGES.md X3).
@visibleForTesting
const String kNivaatNotificationsOffAndroid =
    'Notifications are off — a ringing alarm shows nothing on screen '
    "(sound only, no Stop), and Nivaat can't tell you when it skips an alarm "
    'for wind, or why.';

@visibleForTesting
const String kNivaatNotificationsOffIos =
    "Notifications are off — Nivaat can't tell you when it skips an alarm "
    'for wind, or why.';

/// Home footer caveat (MESSAGES.md N13). Soft-wrap only — no hard `\n`
/// (large accessibility text must reflow cleanly).
///
/// `has enough battery`, not `charged` (2026-08-05, Samyak): "keep the phone
/// charged" reads as *leave it plugged in*, which is not what the cascade
/// needs — it needs the battery not to run out, and to not be throttled by
/// the phone giving up on background work. Nothing here asks for a charger.
///
/// `connected to the internet`, not `online` (2026-07-31, Samyak): to a
/// general reader "online" first suggests *signed in*, which this app has no
/// concept of. The longer phrase is the plain-English one, and the note is a
/// quiet footer with room to wrap.
@visibleForTesting
const String nivaatBackgroundNote =
    'Make sure the phone has enough battery and is connected to the internet '
    'before your alarm — the background wind check needs both.';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    this.permissionFlow,
    this.batteryFlow,
  });

  final NivaatController controller;

  /// The startup notification-permission request; its completion re-checks
  /// the denied-banner (see [NotificationPermissionBanner.recheckAfter]).
  final Future<void>? permissionFlow;

  /// The startup battery-exemption once-ask; its completion re-checks the
  /// background-checks banner (see [BackgroundChecksBanner.recheckAfter]).
  final Future<void>? batteryFlow;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  NivaatController get c => widget.controller;

  /// Ages the per-alarm "in Xh Ym" on every wall-clock :00.
  Timer? _minuteTicker;

  /// The breath under every live dot in the list (Samyak, 2026-08-25) — a
  /// slow fade in and out, so the row reads as *watching* rather than as a
  /// printed label.
  ///
  /// **One controller for the whole list, not one per row.** Rows sharing a
  /// clock breathe together, which is the difference between a screen that is
  /// alive and a screen that is flickering; separate controllers start
  /// whenever their row scrolls into view and drift apart within seconds.
  /// It also costs one ticker no matter how many alarms there are.
  ///
  /// **A two-second cycle on the wall clock** (Samyak, 2026-08-25) — so the
  /// duration is divided by [kMotionSlowdown] rather than set to the number
  /// you want to see. Every ticker in both apps runs through that knob; a
  /// literal 1000 here would breathe for three seconds, not two.
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (1000 / kMotionSlowdown).round()),
  );

  /// **All the way out and all the way back** (Samyak, 2026-08-25). I argued
  /// for a floor — a dot that reaches zero reads as one that has *gone* — and
  /// he took the full fade: the words never leave, so nothing is actually
  /// lost at the bottom of the breath, and the full swing is what makes it
  /// read as alive from across the room.
  late final Animation<double> _dotOpacity = Tween<double>(begin: 0, end: 1)
      .animate(CurvedAnimation(parent: _breath, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_onChanged);
    _armMinuteTicker();
    if (kScreenshotHarness) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(runScreenshotHarness(context, c));
      });
    }
  }

  /// Starts (or stops) the breath, honouring the platform's reduce-motion
  /// setting.
  ///
  /// **Not decoration — a correctness gate.** "Remove animations" is a real
  /// accessibility switch for people whom looping motion makes ill, and a dot
  /// that pulses forever is exactly what it is meant to stop. Held still it
  /// sits at full opacity, so the same information is on screen either way.
  ///
  /// It is also what keeps `pumpAndSettle` usable: an endless animation
  /// schedules frames forever, so every widget test that settles the home
  /// screen would spin until it timed out. Tests turn the switch on rather
  /// than the widget knowing it is under test.
  ///
  /// Here rather than `initState` because it reads `MediaQuery`, and re-run on
  /// every dependency change so flipping the setting takes effect without a
  /// restart.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _breath.stop();
      _breath.value = 1;
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _minuteTicker?.cancel();
    _breath.dispose();
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_onChanged);
    super.dispose();
  }

  /// Single-shot and re-armed from the clock each hop, never `Timer.periodic`:
  /// a periodic timer counts from its own last callback, so it drifts off :00
  /// by however long the app spent suspended — and re-aiming at the wall clock
  /// is the entire reason this ticker exists.
  void _armMinuteTicker() {
    _minuteTicker?.cancel();
    _minuteTicker = Timer(untilNextMinute(), () {
      if (!mounted) return;
      setState(() {});
      _armMinuteTicker();
    });
  }

  void _onChanged() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Background isolates write history the UI isolate's prefs cache can't
    // see — pull on every resume (bg checks also ping via ui_resync). Repaint
    // before re-arming the ticker: re-arming cancels the timer that came due
    // while suspended, and that timer was what would have redrawn the stale
    // minute. (The ticker re-aims itself every hop, so it can't drift beyond
    // one tick on its own — this is only about the frame you're looking at.)
    if (state != AppLifecycleState.resumed) return;
    setState(() {});
    _armMinuteTicker();
    unawaited(c.resync());
  }

  Future<void> _addAlarm() async {
    // No court yet: pick a place first, then open the alarm editor. It used to
    // go through the courts SHEET with `promptAdd`, which opened the picker
    // from inside itself and then had to dismiss itself again on the way back
    // — a whole flag and two pops to make a sheet the user never wanted to see
    // get out of the way. With the courts list living in settings there is
    // nothing in between: the picker is the step, and backing out of it means
    // no alarm, because an alarm has nowhere to check the wind.
    if (c.courts.isEmpty) {
      final added = await pickAndAddCourt(context, c);
      if (!added || !mounted) return;
    }
    await showAlarmSheet(context, c, alarm: null);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (!c.loaded) return const Scaffold(body: SizedBox.shrink());
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _addAlarm,
        backgroundColor: AppPalette.wind,
        foregroundColor: AppPalette.trueBlack,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              // Right pad 28, matching Arunoday's top bar (2026-08-15,
              // Samyak): it was 16, so the same control — the same icon, at
              // the same size, opening the same page — sat 12pt further out in
              // one app than the other. 28 is the body gutter both screens
              // already use for everything else.
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
              child: Row(
                children: [
                  Text('NIVAAT', style: text.labelSmall),
                  const Spacer(),
                  // Sound, courts, and history live in settings now
                  // (2026-07-20, Samyak: one entry point is cleaner); a live
                  // "still checking" cue below doubles as a history shortcut
                  // only while a retry window is open (2026-07-22).
                  IconButton(
                    icon: const Icon(Icons.tune, size: 20),
                    color: AppPalette.textSecondary,
                    onPressed: () => showSettingsSheet(context, c),
                  ),
                ],
              ),
            ),
            // Permission nudges only once there's something to protect
            // (2026-07-22: keep the intro hero clean — same rule as Arunoday).
            if (!kScreenshotHarness && c.alarms.isNotEmpty) ...[
              const AlarmPermissionBanner(
                  appName: 'Nivaat', accent: AppPalette.wind),
              NotificationPermissionBanner(
                accent: AppPalette.wind,
                denied: () =>
                    c.engine.notifier?.notificationsDenied() ??
                    Future.value(false),
                recheckAfter: widget.permissionFlow,
                message: Platform.isAndroid
                    ? kNivaatNotificationsOffAndroid
                    : kNivaatNotificationsOffIos,
              ),
              BackgroundChecksBanner(recheckAfter: widget.batteryFlow),
            ],
            Expanded(
              child: c.alarms.isEmpty ? _empty(text) : _list(text),
            ),
            // Only once there's an alarm — the intro empty state shouldn't
            // nag about background checks before anything is scheduled.
            if (c.alarms.isNotEmpty) _bgNote(text),
            const CraftedBy(accent: AppPalette.wind),
          ],
        ),
      ),
    );
  }

  /// Standing caveat, both platforms: the pre-alarm wind check is background
  /// work, so it needs power and a network. Android throttles background
  /// wakeups under battery saver; iOS only grants BGAppRefresh opportunistically
  /// and Low Power Mode suppresses it outright. Right-padded to clear the FAB.
  Widget _bgNote(TextTheme text) {
    // Top pad: mid-scroll alarm rows sit flush at the Expanded bottom edge,
    // so without air here they kiss this fixed footer (2026-07-22: was 0).
    // Bottom pad lifts the note off CraftedBy without moving the mark
    // (2026-07-20, Samyak: was reading too tight). Soft-wrap only — hard
    // newlines forced a 3-line shape at default scale but overflowed under
    // large accessibility text (2026-07-21).
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 88, 32),
      child: Text(
        nivaatBackgroundNote,
        style: text.bodyMedium!.copyWith(
          fontSize: 12,
          // Quieter than body secondary — a standing caveat, not a headline
          // (2026-07-22, Samyak: was competing with the alarm list).
          color: AppPalette.textSecondary.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  /// The intro hero (MESSAGES.md N14).
  ///
  /// Sits one-third down, not centred — the same 1:2 spacer rhythm Arunoday's
  /// A9 uses (2026-07-31, Samyak: the two intros are the same screen in two
  /// apps and were landing at visibly different heights). Centring reads lower
  /// than it measures here, because the block hangs below its own midpoint and
  /// nothing balances it: A9 has an `Add location` button under the copy,
  /// while Nivaat's action is the FAB, off in the corner.
  /// **Fills the screen when it fits, scrolls when it doesn't** (2026-08-13,
  /// with the 64px hero, same as Arunoday's A9): the 1:2 spacer rhythm has no
  /// give in it, so at a raised system text size the sentence and its body ran
  /// off the bottom of a small phone — and that was already true at the old
  /// 28px at 2x. `IntrinsicHeight` under a `minHeight` of the viewport keeps
  /// the rhythm on every screen that fits.
  Widget _empty(TextTheme text) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: IntrinsicHeight(child: _introBody(text)),
        ),
      ),
    );
  }

  Widget _introBody(TextTheme text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          // The hero size, with Arunoday's A9 (2026-08-13, Samyak): this
          // sentence is the whole screen before you have an alarm, so it gets
          // the 64 an alarm clock would have had.
          Text('The windless alarm.', style: text.displayLarge),
          const SizedBox(height: 12),
          Text(
            'Rings only when the wind at your court is low enough to play. '
            'The calmer the wind, the louder it rings.',
            style: text.bodyMedium,
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  /// N15's live line: **the occurrence's own state when one is open, otherwise
  /// the forecast verdict.**
  ///
  /// This is where the old top-of-screen "still checking" cue went (N11, 2026-
  /// 08-25). That banner spoke for every alarm at once, which is why it had to
  /// pick the SOONEST open window and why tapping it went to history to find
  /// out whose it was. On the row there is nothing to disambiguate — the line
  /// is already inside the alarm it describes — so the picking, the tap target
  /// and the trip to history all go with it.
  ///
  /// A retry window outranks the forecast because it is the newer fact: the
  /// alarm did not ring at T and the occurrence is still live, which no
  /// "going / not going to ring" phrasing can say.
  Widget _liveLine(TextTheme text, NivaatAlarm a) {
    final state = c.checkStates[a.id];
    final forecast = c.forecasts[a.id];
    final watching = nivaatHomeWatchingLine(
      c.history,
      alarms: [a],
      checkStates: [?state],
    );
    // The ⓘ rides on both wordings: an open retry window is still an alarm
    // whose last check produced numbers, and those numbers are the reason it
    // is still watching. Only "Checking…" — nothing read yet — has nothing to
    // show, and it is the one state with no forecast to ask.
    if (watching != null) {
      return _line(text, watching, live: true, forecast: forecast);
    }
    return _line(text, nivaatForecastLine(forecast),
        live: forecast?.willRing ?? false, forecast: forecast);
  }

  /// The dot + words. The accent means "something is live here" — either the
  /// wind says it would ring, or the occurrence is still being checked.
  ///
  /// **Not green/red** (2026-08-25): both apps are built on one accent over
  /// true black, so a third and fourth colour would be the first break in that
  /// system — and roughly one man in twelve cannot separate red from green,
  /// which here would be the entire message. The accent carries "yes" and the
  /// quiet grey carries "no", exactly as the live cue this replaced did, and
  /// **the words say it too** so the colour is never load-bearing on its own.
  Widget _line(
    TextTheme text,
    String line, {
    required bool live,
    required AlarmForecast? forecast,
  }) {
    final body = text.bodyMedium!;
    final colour = live
        ? AppPalette.wind
        : AppPalette.textSecondary.withValues(alpha: 0.7);
    // A drawn circle, not the `●` glyph it used to be (Samyak, 2026-08-25).
    // At bodyMedium the bullet renders about 8px of ink with the font's own
    // side bearings around it — too heavy beside 14px text, and its gap was
    // whatever the glyph decided. Six logical pixels and a stated 8px gap are
    // the same on every device and every font fallback.
    //
    // It grows with the text scale: a fixed 6 next to doubled type reads as a
    // speck, and this dot is half the sentence.
    final size = MediaQuery.textScalerOf(context).scale(6);
    final row = Row(
      children: [
        FadeTransition(
          opacity: _dotOpacity,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 8),
        // Expanded, so the ellipsis lands inside the row rather than the row
        // running past the switch.
        Expanded(
          child: Text(
            line,
            style: body.copyWith(color: colour),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (forecast != null) ...[
          const SizedBox(width: 6),
          // Set in the LINE's type, not `IconButton`'s: a 20px icon in a 48px
          // box is the settings pattern, and on a 14px line inside a row it
          // would add half a row's height for one glyph. At `bodyMedium`'s own
          // size it is another character on the sentence, and the whole line
          // is the target instead.
          Icon(Icons.info_outline, size: body.fontSize, color: colour),
        ],
      ],
    );
    if (forecast == null) return row;
    // **A `Builder`, and it is load-bearing** (2026-08-25). `_line` is a
    // method on the State, so a bare `context` inside the callback below is
    // the State's own — the whole Scaffold. `findRenderObject` on that
    // returned the screen, and the pill landed dead centre over the list
    // instead of on the row that was tapped. This gives the callback a context
    // BELOW the gesture, so the box it measures is this line's.
    return Builder(
      builder: (lineContext) => GestureDetector(
        // Opaque, so the tap stops here. The card behind this line opens the
        // EDITOR, and a detail glance must not be one twitch away from a
        // screen with a Delete button on it.
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // Read at TAP time, not build time: the list may have scrolled
          // since, and a stale y parks the pill over someone else's alarm.
          // Same read `PlaceInfoButton` does.
          final box = lineContext.findRenderObject()! as RenderBox;
          showAppToast(
            lineContext,
            nivaatForecastDetail(forecast),
            accent: AppPalette.wind,
            centerY: box.localToGlobal(box.size.center(Offset.zero)).dy,
          );
        },
        // The dot's line is only ~20px tall, so the vertical padding is what
        // makes this a real target rather than a hairline of one. It is inside
        // the gesture and outside the visible row, so nothing moves.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: row,
        ),
      ),
    );
  }

  Widget _list(TextTheme text) {
    // Same flash-on-open-if-overflowing cue as settings / history
    // (2026-07-22: many alarms made the home list feel "cut off").
    return FlashingScrollbar(
      builder: (scroll) => ListView.separated(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 96),
        itemCount: c.alarms.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, i) {
          final a = c.alarms[i];
          // `!` — deleting a court deletes its alarms in the same step.
          final court = c.courtById(a.courtId)!;
          // Countdown sits with the clock (what it measures) — not buried in
          // the court/limit sub. Enabled only; the switch already says off.
          final inText = a.enabled
              ? nivaatInLabel(nivaatNextRingAt(a, c.checkStates[a.id]))
              : '';
          return InkWell(
            onTap: () => showAlarmSheet(context, c, alarm: a),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sits ON the clock's baseline, right beside it. It
                        // was `Expanded` + end-aligned, which parked it against
                        // the switch with the width of the row in between — so
                        // it read as a label for the toggle, the opposite of
                        // what it describes. `Flexible` (not `Expanded`) takes
                        // only the width it needs and still ellipsises when a
                        // long clock and "in 5d 04h" meet on a narrow phone.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            // Flexible since the clock went to 40 (2026-08-13):
                            // clock + countdown + switch overran the row by
                            // 34px at 1.3x text on a 375pt phone.
                            //
                            // **It SHRINKS rather than truncating, and that is
                            // the point of the `FittedBox`.** Two `Flexible`s
                            // of equal flex split what the switch leaves, so
                            // the wider child gives way first — and the wider
                            // child is the clock. Ellipsis there reads `06:…`
                            // on the one number this list exists to show,
                            // while a test looking for `06:00` still passes
                            // and `takeException` sees nothing. Scaling is
                            // legible; a truncated time is not. The countdown
                            // beside it keeps the ellipsis, where losing the
                            // tail costs nothing.
                            //
                            // **The scaled clock reports an UNSCALED baseline**
                            // — `RenderFittedBox` says so in the SDK ("without
                            // applying any transforms or scaling that would be
                            // applied during paint"), and this Row aligns on
                            // baselines. So when the clock does shrink, `in 7h`
                            // stays on the line the full-size clock would have
                            // sat on. Left as is: the scaling only starts once
                            // the clock outgrows its share, which on a real
                            // phone is a hair at 1.3x and only visible at 2x —
                            // where this column already overflows for reasons
                            // that predate the size pass. `CrossAxisAlignment
                            // .end` is the fix if it ever reads wrong on a
                            // device, at the cost of moving the countdown for
                            // everyone at every size.
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '${a.hour.toString().padLeft(2, '0')}:${a.minute.toString().padLeft(2, '0')}',
                                  maxLines: 1,
                                  // 40, not 28 (Samyak — iOS's alarm list is
                                  // the reference): the time is what you scan
                                  // this screen for, and at 28 it sat level
                                  // with the court/limit line under it.
                                  style: text.displayMedium!.copyWith(
                                    color: a.enabled
                                        ? AppPalette.textPrimary
                                        : AppPalette.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                            if (inText.isNotEmpty)
                              Flexible(
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 10),
                                  child: Text(
                                    inText,
                                    style: text.bodyMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          nivaatAlarmListSub(a, court),
                          style: text.bodyMedium,
                        ),
                        // The live verdict (N15). **Height is reserved even
                        // when it draws nothing**, so the first check landing
                        // cannot make the whole list jump under your thumb —
                        // the same rule the editor's countdown slot follows.
                        // A switched-off alarm is the one case that really
                        // collapses, and that is deliberate: it cannot ring, so
                        // "Going to ring" would be a lie, and the row getting
                        // shorter is a change YOU made by tapping the switch
                        // rather than one data arrival sprang on you.
                        if (a.enabled) ...[
                          // **A rule, not just a gap** (Samyak, 2026-08-25).
                          // The clock and the court/limit line are one block —
                          // what the alarm IS — and this line is a different
                          // kind of sentence: what it is doing right now. Space
                          // alone said "further down the same paragraph"; a
                          // hairline says "something else".
                          //
                          // It stops before the switch because it lives inside
                          // the row's text column, which is what keeps it from
                          // reading as a second copy of the full-bleed
                          // `Divider` between alarms. Same hairline colour on
                          // purpose: on true black a fainter grey is simply
                          // invisible, so the INSET is what tells them apart,
                          // not the tone.
                          const SizedBox(height: 12),
                          Container(height: 1, color: AppPalette.hairline),
                          // 6, not 12: the live line carries another 6 of its
                          // own as tap padding, so the gap you SEE is the same
                          // as the one above the rule.
                          const SizedBox(height: 6),
                          _liveLine(text, a),
                        ],
                      ],
                    ),
                  ),
                  Switch(
                    value: a.enabled,
                    onChanged: (v) => c.toggleAlarm(a.id, v),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
