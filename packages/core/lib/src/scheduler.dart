/// Platform-alarm abstraction. Screens and engines talk to this interface
/// only; the `alarm` pub package implementation lives in each app so the
/// iOS AlarmKit swap (v1.1) stays a contained change.
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
