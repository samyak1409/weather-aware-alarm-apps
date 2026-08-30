import 'package:core/core.dart';
import 'package:nivaat/src/check_scheduler.dart';
import 'package:nivaat/src/engine.dart';
import 'package:nivaat/src/skip_notifier.dart';

/// No-op doubles for controller tests that only care about store / pure logic
/// (not rings, checks, notifications, or wind). Shared so the four classes
/// aren't copy-pasted across test files.

class SilentNotifier extends SkipNotifier {
  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<void> showStillChecking(
      HistoryRecord record, String courtName, DateTime until) async {}

  @override
  Future<void> showSkipped(HistoryRecord record, String courtName) async {}

  @override
  Future<void> showCancelled(HistoryRecord record, String courtName) async {}

  @override
  Future<void> cancelForAlarm(int alarmId) async {}
}

class SilentRing implements AlarmScheduler {
  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<bool> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double? volume,
  }) async =>
      false;

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<Set<int>> scheduledIds() async => {};

  @override
  Future<bool> isRinging(int id) async => false;

  /// False — this is the **iOS-shaped** double. AlarmKit reports nothing it
  /// does on its own, so a ring that is no longer armed says nothing about
  /// whether it sounded, and Nivaat must record an ordinary ring rather
  /// than `Couldn't confirm`. `FakeRing` is the Android side (true).
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

class SilentChecks implements CheckScheduler {
  @override
  Future<void> initialize() async {}

  @override
  Future<bool> scheduleChecks(int alarmId, Map<int, DateTime> rungs) async =>
      true;

  @override
  Future<void> cancelChecks(int alarmId) async {}
}

DateTime _floorToQuarter(DateTime t) =>
    DateTime(t.year, t.month, t.day, t.hour, t.minute ~/ 15 * 15);

class SilentApi extends OpenMeteo {
  @override
  Future<List<WindSample>> windWindow(
    double lat,
    double lon,
    DateTime from,
    DateTime to, {
    List<String> models = OpenMeteo.defaultWindModels,
  }) async =>
      [
        for (var at = _floorToQuarter(from);
            !at.isAfter(to);
            at = at.add(const Duration(minutes: 15)))
          WindSample(rawSpeedKmh: 5, rawGustKmh: 5, slotAt: at),
      ];
}

/// Convenience for the common "quiet engine over an empty store" setup.
NivaatEngine silentEngine(NivaatStore store) => NivaatEngine(
      store: store,
      scheduler: SilentRing(),
      api: SilentApi(),
      checks: SilentChecks(),
      notifier: SilentNotifier(),
    );
