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
  /// denied or unavailable AlarmKit, on Android a rejected `Alarm.set`.
  /// Silently returning here was how Nivaat came to log `Rang` for a morning
  /// nothing was ever armed for (REVIEW #2).
  ///
  /// `true` means the platform accepted it — which on Android is not the same
  /// as proof, because the plugin reports a failed native scheduling as
  /// success (upstream issue #420). That half cannot be fixed from Dart; this
  /// one can, and does.
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
}
