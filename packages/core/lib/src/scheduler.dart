import 'host_alarm_events.dart';

/// Platform-alarm abstraction. Screens and engines talk to this interface
/// only; the concrete impls (`AlarmPkgScheduler`, `AlarmKitScheduler`) live in
/// core and are picked by `createAlarmScheduler` — AlarmKit on iOS (min
/// target 26), the `alarm` package on Android. There is NO iOS `alarm`-package
/// fallback: a denied AlarmKit silently no-ops and `AlarmPermissionBanner`
/// (driven by `alarmSchedulingDenied`) nudges the user to Settings.
abstract class AlarmScheduler {
  Future<void> ensureInitialized();

  /// Schedule a ringing alarm.
  ///
  /// **[volume] null means "whatever the phone's alarm volume is".** That is
  /// Arunoday: the user's own alarm slider is the setting, and overriding it
  /// made a phone deliberately turned down ring at full blast. Nivaat passes
  /// 0.0-1.0 because its wind ramp IS a volume decision (quieter when the wind
  /// is borderline — SPEC.md), and there a null would throw that away.
  ///
  /// **Returns whether the alarm is really armed, and a caller that records
  /// "scheduled" must check it.** `false` means no alarm exists: on iOS a
  /// denied or unavailable AlarmKit, on Android a rejected `Alarm.set`
  /// (`AlarmException` since alarm 5.9.0 / upstream #420). Silently returning
  /// here was how Nivaat came to log `Rang` for a morning nothing was ever
  /// armed for (REVIEW #2).
  ///
  /// `true` means the platform accepted and armed it. On Android that claim
  /// was unreliable before 5.9.0 (the plugin reported success on a failed
  /// native schedule); from 5.9.0 a failed arm unsaves and throws, so `true`
  /// is proof again. **It is still not Rang proof** — a successful schedule
  /// only means the ring is owed; audible / host-drop / ambiguous settle is
  /// what finalises history (see host-event bridge / pending ring).
  Future<bool> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double? volume,
  });

  Future<void> cancel(int id);

  Future<Set<int>> scheduledIds();

  /// True while the alarm with [id] is actively ringing.
  Future<bool> isRinging(int id);

  /// **Whether this platform can tell the app an alarm was moved or dropped
  /// without being asked.** Android can, from `alarm 5.10.0` (`Alarm.events`);
  /// AlarmKit cannot, and neither can the harness scheduler.
  ///
  /// This is the difference between "the ring is gone, and nothing said why"
  /// meaning *something went wrong* and it meaning *nothing at all*. Where
  /// drops are reported, a vanished ring with no event is genuinely ambiguous
  /// and Nivaat records `Couldn't confirm`; where they are not, a vanished
  /// ring is just an alarm that fired and was dismissed — the ordinary case —
  /// and reading it as a miss would label **every** iOS morning as unconfirmed.
  /// Nivaat gates its ambiguous-B policy on this; see `_settleRingScheduled`.
  bool get reportsHostEvents;

  /// Drain buffered / queued host alarm events and await their handlers.
  ///
  /// Must be awaited before evaluate / orphan sweep / cancel / re-arm.
  /// Subscribing to a stream is **not** a barrier — call this explicitly.
  /// No-op for schedulers that have no host events (AlarmKit / NoOp).
  Future<void> applyHostAlarmEvents() async {}

  /// **Everything the platform currently has armed, in ONE round trip.**
  ///
  /// The batch shape is not a convenience: `Alarm.getAlarm(id)` fetches the
  /// whole list over Pigeon anyway, so asking per id turned one resync into
  /// twenty-odd platform calls. It also gives a caller a single consistent
  /// snapshot to reason over, instead of a series that can shift underneath it.
  ///
  /// Bookkeeping for move recovery / cancel policy only — **never Rang proof**.
  /// A time surviving in the plugin's storage does not mean the morning rang.
  ///
  /// **Throws if the platform cannot be asked.** An empty map means the
  /// platform answered and holds nothing; it must never stand in for a failed
  /// query, because callers read an absent id as "that ring is gone" and close
  /// the occurrence on it. A caller that cannot tolerate the throw should soft
  /// -fail the whole pass and retry, not guess.
  Future<Map<int, ScheduledAlarmInfo>> scheduledAlarms();

  /// Register the app handler for host drop/move events. Cleared with `null`.
  void setHostAlarmEventHandler(
    Future<void> Function(HostAlarmEvent event)? handler,
  ) {}
}

/// What the plugin currently has stored for one id — never a ring proof.
class ScheduledAlarmInfo {
  const ScheduledAlarmInfo({
    required this.id,
    required this.dateTime,
    this.handles = 1,
  });

  final int id;
  final DateTime dateTime;

  /// How many live platform alarms this id still resolves to.
  ///
  /// **Normally 1, and >1 is a state a caller must not ignore.** On iOS an id
  /// maps to a LIST of AlarmKit UUIDs, because a cancel that was refused keeps
  /// its handle rather than losing the alarm for good (REVIEW #6) — so an
  /// extra handle is a real alarm that will really sound. [dateTime] describes
  /// only the newest, so anything deciding "this id is already correct, leave
  /// it alone" has to check this too, or the older one rings unnoticed and
  /// nothing ever retries the cancel that failed.
  final int handles;
}

/// Opt-in via `--dart-define=SCREENSHOT_HARNESS=true`. Capture builds use
/// [NoOpAlarmScheduler] and skip permission prompts / nudge banners so system
/// dialogs never cover the UI being shot. Off by default — normal builds
/// unchanged.
const bool kScreenshotHarness =
    bool.fromEnvironment('SCREENSHOT_HARNESS', defaultValue: false);

/// Silent scheduler for screenshot / UI harness builds — never touches
/// AlarmKit or the `alarm` package, so system permission dialogs stay away.
class NoOpAlarmScheduler implements AlarmScheduler {
  const NoOpAlarmScheduler();

  @override
  Future<void> ensureInitialized() async {}

  /// `true`, even though nothing is armed — the one place where reporting
  /// success is right.
  ///
  /// This exists so a capture build behaves EXACTLY like production minus the
  /// system dialogs. Answering `false` would send the engine down its
  /// scheduling-failed path — occurrences left open, "still checking" cards
  /// posted at T — and screenshot a state the app never really reaches. It
  /// cannot mislead anyone either: `kScreenshotHarness` is a compile-time
  /// define, so this class is unreachable in a shipped build.
  @override
  Future<bool> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double? volume,
  }) async =>
      true;

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<Set<int>> scheduledIds() async => {};

  @override
  Future<bool> isRinging(int id) async => false;

  /// False, like AlarmKit: a harness build arms nothing, so nothing can ever
  /// report a drop — and Nivaat must not read that silence as a missed ring.
  @override
  bool get reportsHostEvents => false;

  @override
  Future<void> applyHostAlarmEvents() async {}

  @override
  Future<Map<int, ScheduledAlarmInfo>> scheduledAlarms() async => {};

  @override
  void setHostAlarmEventHandler(
    Future<void> Function(HostAlarmEvent event)? handler,
  ) {}
}
