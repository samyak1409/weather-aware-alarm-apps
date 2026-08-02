import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';

import 'app_window.dart';
import 'format.dart';
import 'theme.dart';

/// How long after coming to the foreground the app still counts as "the alarm
/// put us here" rather than "the user was already here".
///
/// The window exists because Dart cannot ask directly: the intent the plugin
/// launches is `getLaunchIntentForPackage`, byte-identical to tapping the icon,
/// and the activity resume races the ring event with no fixed order. So the
/// answer is timed rather than known, and this is the width of the doubt.
///
/// **One second (Samyak, 2026-08-02), down from five.** Erring long hides an
/// app the user had just opened themselves — the more annoying mistake; erring
/// short only leaves the app on screen, as it always used to. Keep it short and
/// fix the cause: with the extra proposed upstream (CLAUDE.md's *Upstream we
/// are waiting on*) `MainActivity` could simply tell Dart, and this constant
/// would be deleted rather than tuned.
const Duration kRingForegroundGrace = Duration(seconds: 1);

/// Did the ALARM put this app on screen, or was the user already in it?
///
/// Decides whether stopping the ring also hides the app ([sendAppToBackground]).
/// A null [sinceForeground] means the app was never seen resumed — same answer,
/// nobody chose to be here. Where it cannot know it says "the alarm did it",
/// but reaches that default through a narrow [kRingForegroundGrace]: the
/// fallback and the width of the doubt are separate decisions.
bool alarmOpenedTheApp({
  required AppLifecycleState? lifecycle,
  required Duration? sinceForeground,
}) =>
    lifecycle != AppLifecycleState.resumed ||
    sinceForeground == null ||
    sinceForeground < kRingForegroundGrace;

/// Wraps the app and overlays a full-screen stop UI whenever an alarm from
/// the `alarm` package is ringing (i.e. the app is open during ring).
///
/// [actionsBuilder] lets an app add per-alarm actions above the STOP button
/// (e.g. Arunoday's bedtime ritual: delay bedtime, adjust tomorrow's wake).
class RingGate extends StatefulWidget {
  const RingGate({
    super.key,
    required this.appName,
    required this.child,
    this.actionsBuilder,
    this.onRingingChanged,
  });

  final String appName;
  final Widget child;
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

class _RingGateState extends State<RingGate> with WidgetsBindingObserver {
  StreamSubscription<AlarmSet>? _sub;
  Set<int> _lastIds = const {};

  /// When the app last became visible, or null while it isn't. Read only at
  /// the moment a ring starts — see [alarmOpenedTheApp].
  DateTime? _foregroundSince;

  /// Whether the ring now sounding is what brought the app on screen, decided
  /// once when it starts. Deciding later would be too late: by the time it
  /// stops, the ring screen itself has made us resumed either way.
  bool _alarmOpenedUs = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _foregroundSince = DateTime.now();
    }
    // Alarm.ringing replays its current value on subscribe: a quiet mount
    // (empty set == _lastIds) fires nothing, while mounting DURING a ring —
    // opening the app from the ring notification — fires immediately, which
    // is exactly when the app wants a resync.
    _sub = Alarm.ringing.listen((set) {
      final ids = set.alarms.map((a) => a.id).toSet();
      final changed =
          ids.length != _lastIds.length || !ids.containsAll(_lastIds);
      final wasRinging = _lastIds.isNotEmpty;
      _lastIds = ids;
      if (ids.isNotEmpty && !wasRinging) {
        final since = _foregroundSince;
        _alarmOpenedUs = alarmOpenedTheApp(
          lifecycle: WidgetsBinding.instance.lifecycleState,
          sinceForeground:
              since == null ? null : DateTime.now().difference(since),
        );
      }
      // Hidden BEFORE the resync callback, deliberately. Every way a ring can
      // end lands here — STOP below, the notification's Stop button, and the
      // swipe the plugin treats as Stop — and getting off the user's screen is
      // the part that must not depend on anything else succeeding. Both apps
      // pass an `async` resync today, which can only reject a future, but
      // `onRingingChanged` is a plain VoidCallback and a future caller could
      // fill it with something that throws where we'd never see it.
      if (ids.isEmpty && wasRinging && _alarmOpenedUs) {
        _alarmOpenedUs = false;
        unawaited(sendAppToBackground());
      }
      if (changed) widget.onRingingChanged?.call();
    });
  }

  /// Stamped on the way in, cleared on the way out. How long we have been
  /// visible is the only thing separating "the user opened this" from "the
  /// full-screen intent did".
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foregroundSince =
        state == AppLifecycleState.resumed ? DateTime.now() : null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AlarmSet>(
      stream: Alarm.ringing,
      builder: (context, snapshot) {
        final ringing = snapshot.data?.alarms ?? const <AlarmSettings>{};
        if (ringing.isEmpty) return widget.child;
        return RingScreen(
          appName: widget.appName,
          alarms: ringing.toList(),
          actionsBuilder: widget.actionsBuilder,
          onStop: () async {
            for (final a in ringing) {
              await Alarm.stop(a.id);
            }
          },
        );
      },
    );
  }
}

/// What you see while an alarm sounds (MESSAGES.md X1) — app label, the
/// alarm's scheduled time, the ring notification's own body, any app actions,
/// and STOP.
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
    this.actionsBuilder,
  });

  final String appName;
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
              Text(fmtClock(first.dateTime), style: text.displayLarge),
              const SizedBox(height: 12),
              Text(
                first.notificationSettings.body,
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
                  child: const Text('STOP', style: TextStyle(letterSpacing: 2)),
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
