import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';

import 'alarm_launch.dart';
import 'app_window.dart';
import 'format.dart';
import 'theme.dart';

/// Wraps the app and overlays a full-screen stop UI whenever an alarm from
/// the `alarm` package is ringing (i.e. the app is open during ring).
///
/// **Both apps mount this in `MaterialApp.builder`, above the Navigator, and
/// that is a fix rather than a preference (Samyak, 2026-08-13, device-caught).**
/// It used to wrap `home:`, which is the first ROUTE — so a pushed settings
/// page sat on top of it and the ring screen appeared underneath: you had to
/// press back to find it, and tapping the ring notification looked like it did
/// nothing at all (the app was already in front, showing settings). Above the
/// Navigator it covers every route, including sheets and dialogs.
///
/// It also **stacks** rather than swapping the app out, for the same move: the
/// child here is the whole Navigator, and replacing it would tear down the
/// route stack — you would stop the alarm and find yourself back on home with
/// the settings page gone. The Stack is unconditional so the Navigator keeps
/// its element (adding a parent only while ringing would remount it, which is
/// the same loss by another door).
///
/// [actionsBuilder] lets an app add per-alarm actions above the STOP button
/// (e.g. Arunoday's bedtime ritual: delay bedtime, adjust tomorrow's wake).
class RingGate extends StatefulWidget {
  const RingGate({
    super.key,
    required this.appName,
    required this.child,
    this.alarmLabel,
    this.actionsBuilder,
    this.onRingingChanged,
  });

  final String appName;
  final Widget child;

  /// Which alarm this is, in a word — Nivaat's court name (2026-08-13), which
  /// leads the body line under the clock ([ringScreenBody]). Null or empty
  /// adds nothing, which is Arunoday: one wake and one bedtime, already told
  /// apart by the body itself.
  ///
  /// **Rebuilding is the caller's job.** A ring can cold-start the app (the
  /// full screen intent launches it), so the store this name comes from may
  /// still be loading when the screen first draws — Nivaat rebuilds this
  /// widget on its controller so the court appears the moment it is known.
  final String? Function(AlarmSettings alarm)? alarmLabel;

  final Widget Function(BuildContext context, AlarmSettings alarm)?
      actionsBuilder;

  /// Called whenever the set of ringing alarms changes — a ring starting, or
  /// ending (incl. the STOP button here). Apps hook their resync so history
  /// and next-alarm state update the moment a ring begins/ends instead of on
  /// the next app open. Never fires on iOS: rings there are AlarmKit's, so
  /// `Alarm.ringing` stays empty (resync-on-resume covers that platform).
  final VoidCallback? onRingingChanged;

  @override
  State<RingGate> createState() => _RingGateState();
}

class _RingGateState extends State<RingGate> {
  StreamSubscription<AlarmSet>? _sub;
  Set<int> _lastIds = const {};

  @override
  void initState() {
    super.initState();
    // Alarm.ringing replays its current value on subscribe: a quiet mount
    // (empty set == _lastIds) fires nothing, while mounting DURING a ring —
    // opening the app from the ring notification — fires immediately, which
    // is exactly when the app wants a resync.
    _sub = Alarm.ringing.listen(_onRingingChanged);
  }

  /// Ownership is asked at the END of the ring now, not guessed at its start.
  ///
  /// It used to be decided when the ring began, because the only evidence was
  /// how recently the app had resumed and the ring screen destroys that
  /// evidence the moment it appears. [consumeAlarmLaunch] is a fact recorded
  /// by `MainActivity` when the intent arrived, so it neither decays nor races:
  /// asking later is strictly better, and removes the ordering assumption that
  /// the launch must reach Dart before the ring event does.
  Future<void> _onRingingChanged(AlarmSet set) async {
    final ids = set.alarms.map((a) => a.id).toSet();
    final changed = ids.length != _lastIds.length || !ids.containsAll(_lastIds);
    final wasRinging = _lastIds.isNotEmpty;
    // Synchronously, before any await: two ring events must not both read the
    // pre-first-event value and decide the same thing twice.
    _lastIds = ids;
    // Hidden BEFORE the resync callback, deliberately. Every way a ring can
    // end lands here — STOP below, the notification's Stop button, and the
    // swipe the plugin treats as Stop — and getting off the user's screen is
    // the part that must not depend on anything else succeeding. Both apps
    // pass an `async` resync today, which can only reject a future, but
    // `onRingingChanged` is a plain VoidCallback and a future caller could
    // fill it with something that throws where we'd never see it.
    if (ids.isEmpty && wasRinging) {
      final launchedByAlarm = await consumeAlarmLaunch() != null;
      // Re-read `_lastIds` AFTER the await, not before it. A second alarm can
      // start ringing inside that channel round trip — a 06:00 and a 06:01 in
      // Nivaat, or a late ring landing on the heels of an on-time one — and
      // this continuation would otherwise put the app away with the NEW ring's
      // screen already on it.
      //
      // The known cost, and it is deliberate: the launch has been CONSUMED by
      // then, so the second ring's own ending finds nothing and the app stays
      // up. Erring towards visible is the rule everywhere on this path — a
      // wrong hide costs the user the screen they are looking at, a wrong stay
      // costs them one swipe.
      //
      // **Don't "fix" it by keeping the launch alive for the next ring** —
      // not by caching it here, and not by peeking natively instead of
      // consuming. Where the value is stored is not the hazard; outliving its
      // own ring is. Either way it is still sitting there when the second ring
      // ends, which can be minutes later and long after the user has started
      // using the app themselves, and hiding it then is precisely the mistake
      // this mechanism replaced a timer to avoid. Nothing else ever clears it,
      // so "later" has no bound. Trading a millisecond-wide race in the
      // harmless direction for an open-ended one in the harmful direction is a
      // bad trade however it is spelled.
      if (launchedByAlarm && _lastIds.isEmpty) await sendAppToBackground();
    }
    if (changed) widget.onRingingChanged?.call();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AlarmSet>(
      stream: Alarm.ringing,
      builder: (context, snapshot) {
        final ringing = snapshot.data?.alarms ?? const <AlarmSettings>{};
        final alarms = ringing.toList();
        return Stack(
          // Expand, or the app under it is sized by loose constraints and a
          // Scaffold-less child could shrink to nothing.
          fit: StackFit.expand,
          children: [
            // The app is still MOUNTED under the ring screen — that is the
            // point of the Stack — so it stays in the semantics tree unless it
            // is taken out. Without this, TalkBack starts on the settings page
            // underneath and the user swipes through the whole of it to reach
            // STOP, on the one screen you read half awake.
            ExcludeSemantics(excluding: alarms.isNotEmpty, child: widget.child),
            if (alarms.isNotEmpty)
              RingScreen(
                appName: widget.appName,
                alarms: alarms,
                label: widget.alarmLabel?.call(alarms.first),
                actionsBuilder: widget.actionsBuilder,
                onStop: () async {
                  for (final a in ringing) {
                    await Alarm.stop(a.id);
                  }
                },
              ),
          ],
        );
      },
    );
  }
}

/// The one line under the clock: the ring notification's own [body], with
/// [label] — which alarm this is — in front of it when there is one.
///
/// One line rather than two (Samyak, 2026-08-13). The court had a small line
/// of its own above the clock, and on the real screen that read as a third
/// thing to take in at 6am; leading the evidence with it says the same thing
/// in the space that was already there, and in the order N1's notification
/// title uses (`{court} · …`).
String ringScreenBody(String body, String? label) =>
    (label == null || label.isEmpty) ? body : '$label · $body';

/// What you see while an alarm sounds (MESSAGES.md X1) — app label, the
/// alarm's scheduled time, the ring notification's own body (led by [label]
/// when the app supplies one), any app actions, and STOP.
///
/// Public and plugin-free on purpose (2026-07-26). [RingGate] decides *when*
/// this appears, which only the `alarm` plugin can drive and so only a device
/// can exercise; what it *says* is just widgets and is asserted by
/// `shared_message_test`. Splitting the two is what makes the most important
/// screen in either app testable at all — the one you read at 6am, half awake.
class RingScreen extends StatelessWidget {
  const RingScreen({
    super.key,
    required this.appName,
    required this.alarms,
    required this.onStop,
    this.label,
    this.actionsBuilder,
  });

  final String appName;

  /// Which alarm is sounding — Nivaat's court. **Prepended to the body line**
  /// as `{label} · {body}`, not given a line of its own (Samyak, 2026-08-13:
  /// a third block of text under the clock broke the screen's stillness).
  /// Null or empty leaves the body exactly as the notification wrote it.
  final String? label;

  final List<AlarmSettings> alarms;
  final Future<void> Function() onStop;
  final Widget Function(BuildContext context, AlarmSettings alarm)?
      actionsBuilder;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final first = alarms.first;
    return Scaffold(
      backgroundColor: AppPalette.trueBlack,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 16),
              Text(appName, style: text.labelSmall),
              const Spacer(),
              // The alarm's scheduled time, not the wall clock: rings can
              // start a second early and this screen doesn't rebuild.
              //
              // 130, over the theme's 64 (Samyak, 2026-08-13). Local, like
              // Arunoday's home clock and for the same reason: `displayLarge`
              // is also both settings pickers', where this would not fit a
              // dialog.
              //
              // **`scaleDown` is what makes a number this big safe.** At 130,
              // `07:11` is about 310pt wide in SF Pro or Roboto against the
              // 319 a 375pt phone has to give — it fits, and it stops fitting
              // the moment the system text size goes up or the phone is
              // narrower. Shrinking to the room available beats wrapping a
              // clock across two lines, and it is the only guard available:
              // no widget test can measure this, because flutter_test draws
              // every glyph a full em wide (`07:11` measures ~650pt there).
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(fmtClock(first.dateTime),
                    style: text.displayLarge!.copyWith(fontSize: 130)),
              ),
              const SizedBox(height: 12),
              Text(
                ringScreenBody(first.notificationSettings.body, label),
                style: text.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 2),
              if (actionsBuilder != null) ...[
                actionsBuilder!(context, first),
                const SizedBox(height: 20),
              ],
              SizedBox(
                width: double.infinity,
                height: 64,
                child: FilledButton(
                  onPressed: onStop,
                  // Size and weight from the theme's `titleLarge` — that is
                  // where the size was chosen and where "Bold clocks &
                  // titles" reaches it; see `buildOledTheme`. No `scaleDown`
                  // like the clock above: 20 is 40pt of line at double system
                  // text, well inside a 64pt bar.
                  //
                  // **Taken piecemeal, never as the style whole.**
                  // `ThemeData` paints every text style with `onSurface`, so
                  // handing `titleLarge` straight to the button made STOP
                  // white on blue (device-caught, 2026-08-13). The colour is
                  // the BUTTON's to give, and it only arrives if this style
                  // stays quiet about it.
                  child: Text(
                    'STOP',
                    style: TextStyle(
                      fontSize: text.titleLarge!.fontSize,
                      fontWeight: text.titleLarge!.fontWeight,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
