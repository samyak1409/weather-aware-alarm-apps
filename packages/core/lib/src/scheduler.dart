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
