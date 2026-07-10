import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/check_scheduler.dart';
import 'package:nivaat/src/engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeRing implements AlarmScheduler {
  final Map<int, ({DateTime at, double volume, String body})> scheduled = {};

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<void> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double volume,
  }) async {
    scheduled[id] = (at: at, volume: volume, body: body);
  }

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);

  @override
  Future<Set<int>> scheduledIds() async => scheduled.keys.toSet();

  @override
  Future<bool> isRinging(int id) async => false;
}

class FakeChecks implements CheckScheduler {
  final Map<int, DateTime> booked = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scheduleCheck(int alarmId, DateTime at) async =>
      booked[alarmId] = at;

  @override
  Future<void> cancelCheck(int alarmId) async => booked.remove(alarmId);
}

class FakeApi extends OpenMeteo {
  FakeApi();

  WindSample? sample;
  bool fail = false;
  bool lastCallWasCurrent = false;

  @override
  Future<WindSample> forecastWindAt(double lat, double lon, DateTime target) async {
    lastCallWasCurrent = false;
    if (fail || sample == null) throw OpenMeteoException('down');
    return sample!;
  }

  @override
  Future<WindSample> currentWind(double lat, double lon) async {
    lastCallWasCurrent = true;
    if (fail || sample == null) throw OpenMeteoException('down');
    return sample!;
  }
}

WindSample wind(double rawSpeed, double rawGust) => WindSample(
      rawSpeedKmh: rawSpeed,
      rawGustKmh: rawGust,
      observedAt: DateTime(2026, 7, 11),
      isForecast: false,
    );

const court = SavedLocation(id: 'c1', name: 'Home Court', lat: 26.17, lon: 75.79);
const alarm = NivaatAlarm(id: 7, hour: 6, minute: 0, courtId: 'c1');
final alarmAt = DateTime(2026, 7, 12, 6, 0); // 11 Jul 2026 is a Saturday

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRing ring;
  late FakeChecks checks;
  late FakeApi api;
  late NivaatEngine engine;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ring = FakeRing();
    checks = FakeChecks();
    api = FakeApi();
    engine = NivaatEngine(
      store: NivaatStore(),
      scheduler: ring,
      api: api,
      checks: checks,
    );
  });

  test('calm forecast far out: ring scheduled with ramp volume, next check booked',
      () async {
    api.sample = wind(5.0, 5.0); // court 3.0, threshold 4 -> volume 0.625
    final now = DateTime(2026, 7, 11, 18, 0); // T-12h
    await engine.evaluateAlarm(alarm, [court], now: now);

    expect(ring.scheduled[7]!.at, alarmAt);
    expect(ring.scheduled[7]!.volume, closeTo(0.625, 0.001));
    expect(api.lastCallWasCurrent, isFalse, reason: 'far out uses forecast');
    expect(checks.booked[7], DateTime(2026, 7, 12, 0, 0)); // T-6h next
  });

  test('windy forecast far out: no ring, cascade continues', () async {
    api.sample = wind(12.0, 14.0); // court 7.2 > 4
    await engine.evaluateAlarm(alarm, [court],
        now: DateTime(2026, 7, 11, 18, 0));
    expect(ring.scheduled, isEmpty);
    expect(checks.booked[7], isNotNull);
  });

  test('T-0 calm: live wind, ring, history "rang", cascade done', () async {
    api.sample = wind(3.0, 6.0); // court 1.8 -> volume 0.775
    // T-2m check persists the in-flight occurrence...
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 2)));
    expect(api.lastCallWasCurrent, isTrue, reason: 'within live window');
    // ...then the T-0 check runs.
    await engine.evaluateAlarm(alarm, [court], now: alarmAt);

    final history = await engine.store.loadHistory();
    expect(history, hasLength(1));
    expect(history.first.outcome, CheckOutcome.rang);
    expect(history.first.volume, closeTo(0.775, 0.001));
    expect(await engine.store.loadCheckState(7), isNull,
        reason: 'occurrence complete');
  });

  test('turns windy at T-0: pending ring cancelled, skip recorded', () async {
    api.sample = wind(5.0, 5.0); // calm at T-30m -> ring scheduled
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 30)));
    expect(ring.scheduled, isNotEmpty);

    api.sample = wind(9.0, 10.0); // court 5.4 -> windy at T-0
    await engine.evaluateAlarm(alarm, [court], now: alarmAt);

    expect(ring.scheduled, isEmpty, reason: 'ring cancelled');
    final history = await engine.store.loadHistory();
    expect(history.first.outcome, CheckOutcome.skippedWindy);
  });

  test('API dead all the way to the +30m cap: skippedNoData recorded',
      () async {
    api.fail = true;
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 1)));
    expect(ring.scheduled, isEmpty);
    // retries keep getting booked...
    expect(checks.booked[7], alarmAt);

    // ...the final retry fires exactly at the cap.
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.add(const Duration(minutes: 30)));

    final history = await engine.store.loadHistory();
    expect(history, hasLength(1));
    expect(history.first.outcome, CheckOutcome.skippedNoData);
    expect(await engine.store.loadCheckState(7), isNull);
  });

  test('late success in retry window rings late, never in the past', () async {
    api.fail = true;
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 1)));

    api.fail = false;
    api.sample = wind(2.0, 4.0);
    final lateNow = alarmAt.add(const Duration(minutes: 5));
    await engine.evaluateAlarm(alarm, [court], now: lateNow);

    expect(ring.scheduled[7]!.at.isAfter(lateNow), isTrue);
    final history = await engine.store.loadHistory();
    expect(history.first.outcome, CheckOutcome.rang);
  });

  test('disabled alarm clears everything', () async {
    api.sample = wind(5.0, 5.0);
    await engine.evaluateAlarm(alarm, [court],
        now: DateTime(2026, 7, 11, 18, 0));
    expect(ring.scheduled, isNotEmpty);

    await engine.evaluateAlarm(alarm.copyWith(enabled: false), [court],
        now: DateTime(2026, 7, 11, 18, 1));
    expect(ring.scheduled, isEmpty);
    expect(checks.booked, isEmpty);
  });
}
