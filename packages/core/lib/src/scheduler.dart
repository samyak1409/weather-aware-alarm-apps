/// Platform-alarm abstraction. Screens and engines talk to this interface
/// only; the concrete impls (`AlarmPkgScheduler`, `AlarmKitScheduler`) live in
/// core and are picked by `createAlarmScheduler` — AlarmKit on iOS (min
/// target 26), the `alarm` package on Android. There is NO iOS `alarm`-package
/// fallback: a denied AlarmKit silently no-ops and `AlarmPermissionBanner`
/// (driven by `alarmSchedulingDenied`) nudges the user to Settings.
abstract class AlarmScheduler {
  Future<void> ensureInitialized();

  /// Schedule a ringing alarm. [volume] 0.0-1.0 (Nivaat's wind ramp;
  /// Arunoday always passes 1.0).
  Future<void> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double volume,
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

  @override
  Future<void> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double volume,
  }) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<Set<int>> scheduledIds() async => {};

  @override
  Future<bool> isRinging(int id) async => false;
}
