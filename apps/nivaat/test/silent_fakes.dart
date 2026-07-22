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
  Future<void> showSkip(HistoryRecord record, String courtName) async {}

  @override
  Future<void> showExtendedCheck(
      HistoryRecord record, String courtName, DateTime until) async {}
}

class SilentRing implements AlarmScheduler {
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

class SilentChecks implements CheckScheduler {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> scheduleCheck(int alarmId, DateTime at) async {}

  @override
  Future<void> cancelCheck(int alarmId) async {}
}

class SilentApi extends OpenMeteo {
  @override
  Future<WindSample> forecastWindAt(
          double lat, double lon, DateTime target) async =>
      WindSample(
        rawSpeedKmh: 5,
        rawGustKmh: 5,
        observedAt: DateTime(2026, 7, 11),
        isForecast: true,
      );

  @override
  Future<WindSample> currentWind(double lat, double lon) async =>
      forecastWindAt(lat, lon, DateTime.now());
}

/// Convenience for the common "quiet engine over an empty store" setup.
NivaatEngine silentEngine(NivaatStore store) => NivaatEngine(
      store: store,
      scheduler: SilentRing(),
      api: SilentApi(),
      checks: SilentChecks(),
      notifier: SilentNotifier(),
    );
