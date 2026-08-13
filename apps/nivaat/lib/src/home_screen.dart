import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'alarm_sheet.dart';
import 'background_banner.dart';
import 'controller.dart';
import 'courts_sheet.dart';
import 'engine.dart';
import 'history_sheet.dart';
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  NivaatController get c => widget.controller;

  /// Fires when an active still-checking retry window ends so the home cue
  /// clears without waiting for the next resync.
  Timer? _watchExpiry;

  /// Ages the per-alarm "in Xh Ym" on every wall-clock :00.
  Timer? _minuteTicker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_onChanged);
    _armWatchExpiry();
    _armMinuteTicker();
    if (kScreenshotHarness) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(runScreenshotHarness(context, c));
      });
    }
  }

  @override
  void dispose() {
    _watchExpiry?.cancel();
    _minuteTicker?.cancel();
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

  void _onChanged() {
    _armWatchExpiry();
    setState(() {});
  }

  void _armWatchExpiry() {
    _watchExpiry?.cancel();
    _watchExpiry = null;
    // Same pick as the cue text — clears with late ring / alarm gone too.
    final open = nivaatSoonestOpenWatch(
      c.history,
      alarms: c.alarms,
      checkStates: c.checkStates.values,
    );
    final until = open?.watchedUntil;
    if (until == null) return;
    final delay = until.difference(DateTime.now());
    _watchExpiry = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!mounted) return;
      // Re-arm: another alarm may still be inside its retry window.
      _armWatchExpiry();
      setState(() {});
    });
  }

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
    // No court yet: bootstrap via place picker, then open the alarm editor
    // (courts sheet auto-dismisses after the first save — Settings keeps the
    // list open when adding from there).
    if (c.courts.isEmpty) {
      final added = await showCourtsSheet(context, c, promptAdd: true);
      if (!added || !mounted) return;
    }
    await showAlarmSheet(context, c, alarm: null);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (!c.loaded) return const Scaffold(body: SizedBox.shrink());
    final watchingLine = nivaatHomeWatchingLine(
      c.history,
      alarms: c.alarms,
      checkStates: c.checkStates.values,
    );

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
              padding: const EdgeInsets.fromLTRB(28, 24, 16, 8),
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
            if (watchingLine != null) _watchingCue(text, watchingLine),
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

  /// Live "still checking" cue only (MESSAGES N11). Tap → full history.
  ///
  /// Leading wind-accent ● in the text run (not a separate widget) — "live +
  /// tappable" without a word prefix. Full-width [InkWell] so a short line
  /// still highlights edge-to-edge. Outer bottom 8 + ink bottom 8 keeps the
  /// same 16px gap to the list.
  Widget _watchingCue(TextTheme text, String line) {
    final body = text.bodyMedium!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showHistorySheet(context, c),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
              child: Text.rich(
                TextSpan(
                  style: body,
                  children: [
                    TextSpan(
                      text: '● ',
                      style: body.copyWith(color: AppPalette.wind),
                    ),
                    TextSpan(text: line),
                  ],
                ),
              ),
            ),
          ),
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
            'The calmer the morning, the louder it rings.',
            style: text.bodyMedium,
          ),
          const Spacer(flex: 2),
        ],
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
          final court = c.courtById(a.courtId);
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
