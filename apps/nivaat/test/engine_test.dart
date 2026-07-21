import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/check_scheduler.dart';
import 'package:nivaat/src/controller.dart';
import 'package:nivaat/src/engine.dart';
import 'package:nivaat/src/skip_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeNotifier extends SkipNotifier {
  final List<(HistoryRecord, String)> shown = [];
  final List<(HistoryRecord, String)> extended = [];

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<void> showSkip(HistoryRecord record, String courtName) async {
    shown.add((record, courtName));
  }

  @override
  Future<void> showExtendedCheck(
      HistoryRecord record, String courtName, DateTime until) async {
    extended.add((record, courtName));
  }
}

class FakeRing implements AlarmScheduler {
  final Map<int, ({DateTime at, double volume, String body})> scheduled = {};

  /// Every scheduleRing call in order — [scheduled] only keeps the latest per
  /// id, which hides e.g. a late ring that finalising then rolls over.
  final List<({int id, DateTime at})> log = [];
  final Set<int> ringingIds = {};

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
    log.add((id: id, at: at));
  }

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);

  @override
  Future<Set<int>> scheduledIds() async => scheduled.keys.toSet();

  @override
  Future<bool> isRinging(int id) async => ringingIds.contains(id);
}

/// Throws Exception on any scheduler touch — guards resync/init soft-fail
/// paths (Errors must still propagate; see controller.resync).
class BoomRing extends FakeRing {
  Never _boom() => throw Exception('scheduler boom');

  @override
  Future<void> cancel(int id) async => _boom();

  @override
  Future<void> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double volume,
  }) async =>
      _boom();
}

/// Programming Error on any scheduler touch — must NOT be swallowed by resync.
class ErrorRing extends FakeRing {
  Never _boom() => throw StateError('programming boom');

  @override
  Future<void> cancel(int id) async => _boom();

  @override
  Future<void> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double volume,
  }) async =>
      _boom();
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
// Pin the limit (don't rely on the default) so these wind-decision scenarios
// stay valid if the default changes: raw gust limit 4/0.6*2.2 = 14.667.
const alarm =
    NivaatAlarm(id: 7, hour: 6, minute: 0, courtId: 'c1', courtSpeedLimitKmh: 4);
final alarmAt = DateTime(2026, 7, 12, 6, 0); // 11 Jul 2026 is a Saturday

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRing ring;
  late FakeChecks checks;
  late FakeApi api;
  late FakeNotifier notifier;
  late NivaatEngine engine;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ring = FakeRing();
    checks = FakeChecks();
    api = FakeApi();
    notifier = FakeNotifier();
    engine = NivaatEngine(
      store: NivaatStore(),
      scheduler: ring,
      api: api,
      checks: checks,
      notifier: notifier,
    );
  });

  test('calm forecast far out: ring scheduled with ramp volume, next check booked',
      () async {
    api.sample = wind(5.0, 5.0); // court 3.0, threshold 4 -> volume 0.8125
    final now = DateTime(2026, 7, 11, 18, 0); // T-12h
    await engine.evaluateAlarm(alarm, [court], now: now);

    expect(ring.scheduled[7]!.at, alarmAt);
    expect(ring.scheduled[7]!.volume, closeTo(0.8125, 0.001));
    expect(api.lastCallWasCurrent, isFalse, reason: 'far out uses forecast');
    expect(checks.booked[7], DateTime(2026, 7, 12, 5, 0)); // T-1h, first rung
  });

  test('windy forecast far out: no ring, cascade continues', () async {
    api.sample = wind(12.0, 14.0); // court 7.2 > 4
    await engine.evaluateAlarm(alarm, [court],
        now: DateTime(2026, 7, 11, 18, 0));
    expect(ring.scheduled, isEmpty);
    expect(checks.booked[7], isNotNull);
  });

  test('T-0 calm: live wind, ring, history "rang", rolls into tomorrow',
      () async {
    api.sample = wind(3.0, 6.0); // court 1.8 -> volume 0.8875
    // T-2m check persists the in-flight occurrence...
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 2)));
    expect(api.lastCallWasCurrent, isTrue, reason: 'within live window');
    // ...then the T-0 check runs.
    await engine.evaluateAlarm(alarm, [court], now: alarmAt);

    final history = await engine.store.loadHistory();
    expect(history, hasLength(1));
    expect(history.first.outcome, CheckOutcome.rang);
    expect(history.first.volume, closeTo(0.8875, 0.001));
    // Finalising doesn't stop at the closed occurrence: the same pass
    // evaluates tomorrow — pre-arms it (still calm) and books its ladder —
    // so the cascade never sleeps until the next manual app open.
    final rolled = await engine.store.loadCheckState(7);
    expect(rolled!.alarmAt, alarmAt.add(const Duration(days: 1)),
        reason: "today closed; tomorrow's occurrence is already in flight");
    expect(ring.scheduled[7]!.at, alarmAt.add(const Duration(days: 1)),
        reason: 'tomorrow pre-armed while the forecast is calm');
    expect(checks.booked[7],
        alarmAt.add(const Duration(days: 1, hours: -1)),
        reason: "tomorrow's first rung (T-1h) booked");
  });

  test('turns windy at T-0: ring cancelled, heads-up posted (no final card yet)',
      () async {
    api.sample = wind(5.0, 5.0); // calm at T-30m -> ring pre-armed
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 30)));
    expect(ring.scheduled, isNotEmpty);

    api.sample = wind(9.0, 10.0); // court 5.4 -> windy at T-0
    await engine.evaluateAlarm(alarm, [court], now: alarmAt);

    expect(ring.scheduled, isEmpty, reason: 'pending ring cancelled');
    // The occurrence is in history from its first missed T (2026-07-19):
    // a provisional row the retries keep fresh — dismissing the heads-up
    // notification must not hide what happened.
    final history = await engine.store.loadHistory();
    expect(history, hasLength(1), reason: 'provisional row appears at T');
    expect(history.single.outcome, CheckOutcome.skippedWindy);
    expect(history.single.watchedUntil,
        alarmAt.add(const Duration(minutes: 30)),
        reason: 'marked as the heads-up snapshot (its final row comes later)');
    expect(notifier.shown, isEmpty, reason: 'no FINAL card until the cap');
    expect(notifier.extended, hasLength(1), reason: '"still checking" card at T');
    expect(notifier.extended.first.$1.outcome, CheckOutcome.skippedWindy);
    expect(checks.booked[7], alarmAt.add(const Duration(minutes: 1)),
        reason: 'first retry booked');
  });

  test('no card of any kind before T', () async {
    api.sample = wind(9.0, 10.0); // windy
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(seconds: 20)));
    expect(notifier.shown, isEmpty);
    expect(notifier.extended, isEmpty, reason: 'heads-up only at/after T');
    expect(await engine.store.loadHistory(), isEmpty);
    expect(checks.booked[7], alarmAt, reason: 'final ladder check booked at T');
  });

  test('windy at T, calm in the retry window -> rings late (heads-up left in place)',
      () async {
    api.sample = wind(9.0, 10.0); // windy — heads-up posted at T
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 1)));
    await engine.evaluateAlarm(alarm, [court], now: alarmAt);
    expect(notifier.extended, hasLength(1), reason: 'heads-up at T');
    expect((await engine.store.loadHistory()).single.outcome,
        CheckOutcome.skippedWindy,
        reason: 'provisional row from the missed T');

    // Wind drops 7 min after T -> ring late.
    api.sample = wind(5.0, 5.0); // court 3.0 -> ring
    final late = alarmAt.add(const Duration(minutes: 7));
    await engine.evaluateAlarm(alarm, [court], now: late);

    expect(
        ring.log.any((e) =>
            e.at == late.add(const Duration(seconds: 10))),
        isTrue,
        reason: 'rings late, never in the past');
    // Append-only log (2026-07-20): the late ring is a NEW row; the heads-up
    // snapshot stays below it — both moments really happened.
    final history = await engine.store.loadHistory();
    expect(history, hasLength(2));
    expect(history.first.outcome, CheckOutcome.rang);
    expect(history.first.watchedUntil, isNull, reason: 'final rows carry no watch mark');
    expect(history.first.whenChecked, late,
        reason: 'records the check that drove the ring (06:07), not the anchor');
    expect(history.first.at, alarmAt, reason: 'anchor stays the alarm time');
    expect(history.last.outcome, CheckOutcome.skippedWindy,
        reason: 'the at-T snapshot survives the late ring');
    expect(history.last.watchedUntil, isNotNull);
    expect(notifier.shown, isEmpty, reason: 'a ring needs no skip card');
    expect(notifier.extended, hasLength(1),
        reason: 'heads-up is not cleared by the late ring');
    expect((await engine.store.loadCheckState(7))!.alarmAt,
        alarmAt.add(const Duration(days: 1)),
        reason: 'rolled straight on to tomorrow (calm -> pre-armed)');
  });

  test('first wake past +30m cap (windy set-time forecast) -> skip logged + one card',
      () async {
    api.sample = wind(9.0, 10.0); // windy at set-time and after
    // Set-time evaluation (2h before T) persists the windy skip state; the app
    // then never runs again until past the retry cap.
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(hours: 2)));
    expect(await engine.store.loadHistory(), isEmpty);
    expect(notifier.shown, isEmpty);

    // First run again only at T+31m: today's occurrence has rolled to tomorrow,
    // but its skip must still be finalised, not silently dropped.
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.add(const Duration(minutes: 31)));

    final history = await engine.store.loadHistory();
    expect(history, hasLength(1));
    expect(history.first.outcome, CheckOutcome.skippedWindy);
    expect(history.first.at, alarmAt, reason: "today's occurrence, not tomorrow");
    expect(history.first.whenChecked, alarmAt.subtract(const Duration(hours: 2)),
        reason: 'skip carries the set-time check, its only reading');
    expect(notifier.shown, hasLength(1), reason: 'exactly one skip card');
    expect(notifier.extended, isEmpty, reason: 'no heads-up past the cap');
  });

  test('windy through the +30m cap -> heads-up at T, final card at the cap',
      () async {
    api.sample = wind(9.0, 10.0); // windy, and stays windy
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 1)));
    await engine.evaluateAlarm(alarm, [court], now: alarmAt);
    expect(notifier.extended, hasLength(1), reason: 'heads-up at T');
    expect(notifier.shown, isEmpty, reason: 'no final card yet');
    expect(await engine.store.loadHistory(), hasLength(1),
        reason: 'provisional row from T onwards');

    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.add(const Duration(minutes: 30)));
    // Two rows now, like the two notifications: the heads-up snapshot from T
    // and the cap's final verdict (append-only log, 2026-07-20).
    final history = await engine.store.loadHistory();
    expect(history, hasLength(2));
    expect(history.first.outcome, CheckOutcome.skippedWindy);
    expect(history.first.watchedUntil, isNull, reason: 'the final row');
    expect(history.last.watchedUntil, isNotNull, reason: 'the snapshot row');
    expect(notifier.shown, hasLength(1), reason: 'final card at the cap');
    expect(notifier.shown.first.$2, 'Home Court');
    expect((await engine.store.loadCheckState(7))!.alarmAt,
        alarmAt.add(const Duration(days: 1)),
        reason: "rolled on: tomorrow's occurrence already tracked");
  });

  test('windy, then API dies exactly at the cap -> still labelled windy',
      () async {
    api.sample = wind(9.0, 10.0); // windy — remembered as the skip reason
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 1)));
    await engine.evaluateAlarm(alarm, [court], now: alarmAt);

    api.fail = true; // network dies right at the +30m cap
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.add(const Duration(minutes: 30)));

    final history = await engine.store.loadHistory();
    expect(history, hasLength(2), reason: 'snapshot at T + final at the cap');
    expect(history.first.outcome, CheckOutcome.skippedWindy,
        reason: 'uses the last known reason, not the cap failure');
    expect(history.first.courtSpeedKmh, closeTo(5.4, 0.01));
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
    expect(history.first.whenChecked, alarmAt.add(const Duration(minutes: 30)),
        reason: 'no-data records the last *attempt* (the cap), not a reading');
    expect((await engine.store.loadCheckState(7))!.alarmAt,
        alarmAt.add(const Duration(days: 1)),
        reason: 'rolled on to tomorrow even while the API is down');
    expect(notifier.shown, hasLength(1), reason: 'API failure also notifies');
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
    expect(notifier.shown, isEmpty, reason: 'a ring needs no card');
  });

  group('NivaatController', () {
    late NivaatController controller;
    setUp(() => controller = NivaatController(engine: engine));

    test('addCourt persists, courtById finds it, existingCourtNear (~100m)',
        () async {
      await controller.init();
      await controller.addCourt(const GeoPlace(
          name: 'Court A', region: 'x', lat: 12.9, lon: 77.6));
      final saved = controller.courts.single;
      expect(saved.name, 'Court A');
      expect(controller.courtById(saved.id)!.name, 'Court A');
      // ~50 m away → duplicate; a different city → not.
      expect(controller.existingCourtNear(12.9003, 77.6003), isNotNull);
      expect(controller.existingCourtNear(28.61, 77.20), isNull);
    });

    test('nextAlarmId increments; upsert adds then edits in place', () async {
      await engine.store.saveCourts([court]);
      await controller.init();
      expect(controller.nextAlarmId(), 1);
      await controller.upsertAlarm(
          const NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1'));
      expect(controller.alarms.single.hour, 6);
      expect(controller.nextAlarmId(), 2);
      await controller.upsertAlarm(
          const NivaatAlarm(id: 1, hour: 7, minute: 0, courtId: 'c1'));
      expect(controller.alarms.length, 1, reason: 'edited in place');
      expect(controller.alarms.single.hour, 7);
    });

    test('toggleAlarm flips enabled; deleteAlarm removes', () async {
      await engine.store.saveCourts([court]);
      await controller.init();
      await controller.upsertAlarm(alarm); // id 7
      await controller.toggleAlarm(7, false);
      expect(controller.alarms.single.enabled, isFalse);
      await controller.deleteAlarm(7);
      expect(controller.alarms, isEmpty);
    });

    test('init stays loaded when resync hits a scheduler Exception', () async {
      api.sample = wind(5.0, 5.0); // calm → scheduleRing path hits BoomRing
      await engine.store.saveCourts([court]);
      await engine.store.saveAlarms([alarm]);
      final boomEngine = NivaatEngine(
        store: engine.store,
        scheduler: BoomRing(),
        api: api,
        checks: checks,
        notifier: notifier,
      );
      final c = NivaatController(engine: boomEngine);
      await expectLater(c.init(), completes);
      expect(c.loaded, isTrue);
    });

    test('resync swallows evaluateAll Exceptions', () async {
      api.sample = wind(5.0, 5.0);
      await engine.store.saveCourts([court]);
      await engine.store.saveAlarms([alarm]);
      final boomEngine = NivaatEngine(
        store: engine.store,
        scheduler: BoomRing(),
        api: api,
        checks: checks,
        notifier: notifier,
      );
      final c = NivaatController(engine: boomEngine);
      await c.init();
      await expectLater(c.resync(), completes);
    });

    test('resync lets programming Errors propagate', () async {
      api.sample = wind(5.0, 5.0);
      await engine.store.saveCourts([court]);
      await engine.store.saveAlarms([alarm]);
      final boomEngine = NivaatEngine(
        store: engine.store,
        scheduler: ErrorRing(),
        api: api,
        checks: checks,
        notifier: notifier,
      );
      final c = NivaatController(engine: boomEngine);
      await expectLater(c.init(), throwsStateError);
    });
  });

  test('opening the app during a ring never cancels it (future occurrence)',
      () async {
    // The alarm is currently ringing (a past occurrence fired and cleared).
    ring.scheduled[7] =
        (at: alarmAt, volume: 1.0, body: 'ringing now');
    ring.ringingIds.add(7);

    // Resume the app an hour later → re-evaluates the NEXT (future) occurrence,
    // whose forecast is windy → skip. The live ring must survive.
    api.sample = wind(12.0, 14.0); // court 7.2 > 4 → windy
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.add(const Duration(hours: 1)));

    expect(ring.scheduled.containsKey(7), isTrue,
        reason: 'a resync for a future occurrence must not silence the ring');
  });

  test('committed ring that fired (no T-0 check, iOS) is later logged rang, not skip',
      () async {
    // T-30m: a calm forecast commits the ring for THIS occurrence.
    api.sample = wind(5.0, 5.0); // court 3.0 <= 4 -> ring, volume 0.8125
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 30)));
    expect(ring.scheduled.containsKey(7), isTrue);

    // No exact T-0 check runs (iOS has none). The ring fired at T and the user
    // stopped it. The app is opened 5 min later and the wind has since risen
    // far past the limit — a naive re-check would call this a skip.
    api.sample = wind(20.0, 24.0); // court 12 >> 4
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.add(const Duration(minutes: 5)));

    final history = await engine.store.loadHistory();
    expect(history, hasLength(1));
    expect(history.first.outcome, CheckOutcome.rang,
        reason: 'the ring already fired — honour it, never relabel as skipped');
    expect(history.first.volume, closeTo(0.8125, 0.001));
    expect(notifier.shown, isEmpty, reason: 'a ring must never send a skip card');
    expect((await engine.store.loadCheckState(7))!.alarmAt,
        alarmAt.add(const Duration(days: 1)),
        reason: 'the same open rolls on to tomorrow (windy -> tracked, unarmed)');
  });

  test('committed ring is logged rang even when the app opens past the retry window',
      () async {
    // T-30m: calm forecast commits the ring for this occurrence.
    api.sample = wind(5.0, 5.0); // court 3.0 -> ring, volume 0.8125
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 30)));
    expect(ring.scheduled.containsKey(7), isTrue);

    // No T-0 check runs (iOS). The app is first opened 45 min after T — past
    // the 30-min window, so the engine resolves TOMORROW's occurrence. The ring
    // that fired must still land in history, not vanish.
    api.sample = wind(3.0, 6.0); // tomorrow's forecast, calm
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.add(const Duration(minutes: 45)));

    final rangRows = (await engine.store.loadHistory())
        .where((h) => h.outcome == CheckOutcome.rang && h.at == alarmAt);
    expect(rangRows, hasLength(1),
        reason: 'the fired ring is recorded exactly once, even on a late open');
    expect(rangRows.first.volume, closeTo(0.8125, 0.001));
    expect(rangRows.first.courtSpeedLimitKmh, 4);
  });

  test('opening the app while its OWN ring still sounds: logged rang NOW, never cancelled',
      () async {
    api.sample = wind(5.0, 5.0); // calm -> ring committed at T-30m
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 30)));

    // The ring fired at T and is sounding now; wind has since risen.
    ring.ringingIds.add(7);
    api.sample = wind(20.0, 24.0);
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.add(const Duration(minutes: 3)));

    expect(ring.scheduled.containsKey(7), isTrue,
        reason: 'a sounding ring must not be cancelled');
    expect(notifier.shown, isEmpty);
    // Audible = final: the row is in history from THIS moment — before the
    // user stops the ring, not on some later open (2026-07-19).
    var history = await engine.store.loadHistory();
    expect(history, hasLength(1));
    expect(history.single.outcome, CheckOutcome.rang);
    expect(history.single.volume, closeTo(0.8125, 0.001));
    expect(await engine.store.loadCheckState(7), isNull,
        reason: 'occurrence finalised while still audible');
    // And the cascade survives the mid-ring return: with no post-T checks
    // left to book themselves, the next occurrence's first rung is booked
    // here (its own id space — never touches the sounding ring).
    expect(checks.booked[7],
        alarmAt.add(const Duration(days: 1, hours: -1)),
        reason: "tomorrow's T-1h check keeps Android's cascade alive");

    // A second mid-ring pass (another resync) must not double-log.
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.add(const Duration(minutes: 4)));
    history = await engine.store.loadHistory();
    expect(history, hasLength(1), reason: 'idempotent while sounding');
  });

  test('removing a court deletes its alarms and history, sparing other courts',
      () async {
    const court2 = SavedLocation(id: 'c2', name: 'Other', lat: 26.2, lon: 75.8);
    const alarm2 = NivaatAlarm(
        id: 8, hour: 7, minute: 0, courtId: 'c2', courtSpeedLimitKmh: 4);
    final controller = NivaatController(engine: engine);
    await engine.store.saveCourts([court, court2]);
    await engine.store.saveAlarms([alarm, alarm2]); // alarm.courtId == court.id
    // c1 has two rows from its live alarm (7) plus one from an alarm deleted
    // earlier (99) — court-keyed, so that orphan is still c1's and gets deleted.
    for (final (id, courtId) in [(7, 'c1'), (7, 'c1'), (99, 'c1'), (8, 'c2')]) {
      await engine.store.addHistory(HistoryRecord(
          alarmId: id,
          courtId: courtId,
          at: DateTime(2026, 7, 13, 6, id % 60),
          outcome: CheckOutcome.rang));
    }
    await controller.init();
    expect(controller.alarmsForCourt(court.id), 1);
    expect(controller.historyForCourt(court.id), 3,
        reason: "c1's two live rows + one orphan");
    expect(controller.historyForCourt(court2.id), 1);

    await controller.removeCourt(court.id);
    expect(controller.courts.map((c) => c.id), ['c2']);
    expect(controller.alarms.map((a) => a.id), [8],
        reason: 'orphaned alarms must not linger with a dead court id');
    expect(controller.history.map((h) => h.courtId), ['c2'],
        reason: "every c1 row deleted (incl. the orphan), c2 kept");
    expect(await engine.store.loadHistory(), hasLength(1),
        reason: 'deletion is persisted, not just in-memory');
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
    expect(await engine.store.loadHistory(), isEmpty,
        reason: 'the pre-armed ring never FIRED — nothing to record');
  });

  test('toggle-off after an unlogged fired ring still lands the rang row',
      () async {
    // The ring fired while the app was closed; its committed state is the
    // only evidence (no evaluate ran in between). Disabling the alarm used to
    // clear that state unread — the ring vanished from history forever.
    await engine.store.saveCheckState(CheckState(
      alarmId: 7,
      alarmAt: alarmAt,
      ringScheduled: true,
      ringCourtSpeedKmh: 1.8,
      ringRawGustKmh: 6.0,
      ringVolume: 0.8875,
      lastCheckAt: alarmAt.subtract(const Duration(minutes: 30)),
    ));
    await engine.evaluateAlarm(alarm.copyWith(enabled: false), [court],
        now: alarmAt.add(const Duration(minutes: 2)));

    final history = await engine.store.loadHistory();
    expect(history, hasLength(1));
    expect(history.single.outcome, CheckOutcome.rang);
    expect(history.single.at, alarmAt);
    expect(history.single.volume, closeTo(0.8875, 0.001));
    expect(await engine.store.loadCheckState(7), isNull);
  });

  test("the reput bug: editing after a fired ring doesn't lose its history",
      () async {
    // Device-reproduced 2026-07-19: set alarm -> rang -> re-set ("reput") ->
    // that ring never appeared in history, ever. The edit's blind
    // clearCheckState destroyed the un-logged committed ring.
    await engine.store.saveCourts([court]);
    await engine.store.saveAlarms([alarm]);
    await engine.store.saveCheckState(CheckState(
      alarmId: 7,
      alarmAt: alarmAt,
      ringScheduled: true,
      ringCourtSpeedKmh: 0.6,
      ringRawGustKmh: 2.0,
      ringVolume: 1.0,
    ));
    final controller = NivaatController(engine: engine);
    controller.alarms = await engine.store.loadAlarms();
    controller.courts = await engine.store.loadCourts();

    api.sample = wind(5.0, 5.0); // whatever tomorrow's forecast says
    await controller.upsertAlarm(alarm.copyWith(hour: 7));

    final history = await engine.store.loadHistory();
    expect(history, hasLength(1),
        reason: 'the fired ring survives the edit');
    expect(history.single.outcome, CheckOutcome.rang);
    expect(history.single.at, alarmAt,
        reason: 'anchored to the occurrence that rang, pre-edit');
    expect(history.single.volume, closeTo(1.0, 0.001));
  });

  test('retries never rewrite the heads-up snapshot row', () async {
    api.sample = wind(9.0, 10.0); // court 5.4 -> windy
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 1)));
    await engine.evaluateAlarm(alarm, [court], now: alarmAt);
    expect((await engine.store.loadHistory()).single.courtSpeedKmh,
        closeTo(5.4, 0.01));

    api.sample = wind(12.0, 14.0); // court 7.2 — a stronger reading
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.add(const Duration(minutes: 5)));

    final history = await engine.store.loadHistory();
    expect(history, hasLength(1), reason: 'retries append nothing');
    expect(history.single.courtSpeedKmh, closeTo(5.4, 0.01),
        reason: 'the snapshot keeps exactly what the heads-up card said');
    expect(history.single.watchedUntil, isNotNull);
  });

  test('nivaatStillWatchingNote: snapshot rows watch then remember; final rows stay quiet',
      () {
    final snapshot = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: alarmAt,
        watchedUntil: alarmAt.add(const Duration(minutes: 30)),
        outcome: CheckOutcome.skippedWindy);
    expect(
        nivaatStillWatchingNote(snapshot,
            now: alarmAt.add(const Duration(minutes: 10))),
        'watching until 06:30',
        reason: 'inside the retry window — a late ring may still follow');
    expect(
        nivaatStillWatchingNote(snapshot,
            now: alarmAt.add(const Duration(minutes: 30))),
        'watched until 06:30',
        reason: 'stays forever as the mark of the at-T moment');
    final finalSkip = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: alarmAt,
        outcome: CheckOutcome.skippedWindy);
    expect(nivaatStillWatchingNote(finalSkip, now: alarmAt), isNull,
        reason: 'final rows carry no watch note');
  });

  test('concurrent evaluations of one alarm serialize — no duplicate history',
      () async {
    // Yesterday's occurrence was skipped windy and never finalised (app closed
    // through the retry window). Two overlapping evaluations — the app-open
    // resync racing a toggle tapped moments later — would both read the
    // unfinalised state and both write the "Skipped (windy)" row and card.
    await engine.store.saveCheckState(CheckState(
      alarmId: 7,
      alarmAt: alarmAt,
      skipCourtSpeedKmh: 7.2,
      skipRawGustKmh: 14.0,
      lastCheckAt: alarmAt,
      lastAttemptAt: alarmAt,
    ));
    api.sample = wind(12.0, 14.0); // still windy for the next occurrence
    final past = DateTime(2026, 7, 12, 7, 0); // an hour past T, beyond the cap

    // Deliberately NOT awaited one-by-one — they must overlap to race.
    await Future.wait([
      engine.evaluateAlarm(alarm, [court], now: past),
      engine.evaluateAlarm(alarm, [court], now: past),
    ]);

    final rows =
        (await engine.store.loadHistory()).where((r) => r.at == alarmAt);
    expect(rows.length, 1, reason: 'one occurrence, one history row');
    expect(notifier.shown.length, 1, reason: 'one occurrence, one skip card');
  });

  test('standard() loads the selected tone — every entrypoint, not just main()',
      () async {
    // Regression: the iOS Workmanager entrypoint used to skip this load, so a
    // background-scheduled ring fell back to the default Court Call.
    SharedPreferences.setMockInitialValues({'nivaat.sound': '/tones/temple.ogg'});
    nivaatSelectedSound = null; // fresh background isolate
    await NivaatEngine.standard();
    expect(nivaatSelectedSound, '/tones/temple.ogg');
    expect(nivaatSoundForVolume(1.0), '/tones/temple.ogg');

    // And with nothing stored, the wind-ramp default still applies.
    SharedPreferences.setMockInitialValues({});
    await NivaatEngine.standard();
    expect(nivaatSelectedSound, isNull);
    expect(nivaatSoundForVolume(0.75), 'assets/sounds/nivaat_ring_75.wav');
  });
}
