import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/check_scheduler.dart';
import 'package:nivaat/src/controller.dart';
import 'package:nivaat/src/engine.dart';
import 'package:nivaat/src/ids.dart';
import 'package:nivaat/src/skip_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeNotifier extends SkipNotifier {
  final List<(HistoryRecord, String)> shown = [];
  final List<(HistoryRecord, String, DateTime, bool)> extended = [];
  final List<int> cancelled = [];
  final List<int> cancelledHeadsUp = [];

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<void> showSkip(HistoryRecord record, String courtName) async {
    shown.add((record, courtName));
  }

  @override
  Future<void> showExtendedCheck(
    HistoryRecord record,
    String courtName,
    DateTime until, {
    bool quietUpdate = false,
  }) async {
    extended.add((record, courtName, until, quietUpdate));
  }

  @override
  Future<void> cancelForAlarm(int alarmId) async {
    cancelled.add(alarmId);
  }

  @override
  Future<void> cancelHeadsUp(int alarmId) async {
    cancelledHeadsUp.add(alarmId);
  }
}

class FakeRing implements AlarmScheduler {
  final Map<int, ({DateTime at, double volume, String title, String body})>
      scheduled = {};

  /// Every scheduleRing call in order — [scheduled] only keeps the latest per
  /// id, which hides e.g. a late ring that finalising then rolls over.
  final List<({int id, DateTime at})> log = [];

  /// Every cancel in order. Needed because a cancel can be immediately
  /// followed by a write to the same locker inside one pass, which [scheduled]
  /// alone cannot distinguish from "never cancelled".
  final List<int> cancelled = [];
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
    scheduled[id] = (at: at, volume: volume, title: title, body: body);
    log.add((id: id, at: at));
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

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

// Ring lockers are split by ROLE: the pre-arm for an occurrence's own time
// vs a LATE ring armed after T. That separation is what stops the next
// occurrence's pre-arm from evicting a late ring.
final todayRing = NivaatIds.ring(alarm.id);
final lateRing = NivaatIds.lateRing(alarm.id);

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
    api.sample = wind(5.0, 5.0); // court 3.0, threshold 4 -> 3L/4 exactly -> volume 0.85
    final now = DateTime(2026, 7, 11, 18, 0); // T-12h
    await engine.evaluateAlarm(alarm, [court], now: now);

    expect(ring.scheduled[todayRing]!.at, alarmAt);
    expect(ring.scheduled[todayRing]!.volume, 0.85);
    // MESSAGES.md N1: court, the alarm time the user set, then the verdict —
    // no app name (the OS notification header already prints it). The body is
    // the numbers alone; "Play!" moved up into the title (2026-07-22).
    expect(ring.scheduled[todayRing]!.title, 'Home Court · 06:00 · Play! 🏸');
    // Checked at T−12h the evening before, so the note carries the date —
    // a bare "18:00" would read as this morning.
    expect(ring.scheduled[todayRing]!.body,
        'wind 3 (≤4) · gusts 5 (≤15) km/h · checked 11 Jul 18:00');
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
    api.sample = wind(3.0, 6.0); // court 1.8 -> middle step -> volume 0.85
    // T-2m check persists the in-flight occurrence...
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 2)));
    expect(api.lastCallWasCurrent, isTrue, reason: 'within live window');
    // ...then the T-0 check runs.
    await engine.evaluateAlarm(alarm, [court], now: alarmAt);

    final history = await engine.store.loadHistory();
    expect(history, hasLength(1));
    expect(history.first.outcome, CheckOutcome.rang);
    expect(history.first.volume, 0.85);
    // Finalising doesn't stop at the closed occurrence: the same pass
    // evaluates tomorrow — pre-arms it (still calm) and books its ladder —
    // so the cascade never sleeps until the next manual app open.
    final rolled = await engine.store.loadCheckState(7);
    expect(rolled!.alarmAt, alarmAt.add(const Duration(days: 1)),
        reason: "today closed; tomorrow's occurrence is already in flight");
    expect(ring.scheduled[todayRing]!.at, alarmAt.add(const Duration(days: 1)),
        reason: 'tomorrow pre-armed while the forecast is calm');
    // The regression guard for the locker collision: the T-0 ring was
    // committed moments earlier in this same pass, into the LATE locker, and
    // the pre-arm above must NOT have evicted it. Under one locker per alarm
    // this entry was gone.
    expect(ring.scheduled[lateRing]!.at,
        alarmAt.add(const Duration(seconds: 10)),
        reason: "the T-0 ring survives the roll-on pre-arm");
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

  test('per-alarm 1-min retry: watchedUntil = T+1m, finalises at that cap',
      () async {
    // Short window for device testing without waiting half an hour.
    const short = NivaatAlarm(
      id: 7,
      hour: 6,
      minute: 0,
      courtId: 'c1',
      courtSpeedLimitKmh: 4,
      retryMinutesAfter: 1,
    );
    api.sample = wind(9.0, 10.0);
    // Pre-T check seeds CheckState for today's occurrence (evaluating at
    // exact T with no state would roll to tomorrow via nextOccurrence).
    await engine.evaluateAlarm(short, [court],
        now: alarmAt.subtract(const Duration(minutes: 1)));
    await engine.evaluateAlarm(short, [court], now: alarmAt);

    final atT = await engine.store.loadHistory();
    expect(atT, hasLength(1));
    expect(atT.single.watchedUntil, alarmAt.add(const Duration(minutes: 1)),
        reason: 'heads-up / history deadline follows THIS alarm\'s window');
    expect(checks.booked[7], alarmAt.add(const Duration(minutes: 1)));
    expect(notifier.shown, isEmpty);
    expect(notifier.extended, hasLength(1));
    expect(notifier.extended.first.$1.watchedUntil,
        alarmAt.add(const Duration(minutes: 1)));

    // A mid-window resync (app open / sibling alarm) must NOT finalise early.
    await engine.evaluateAlarm(short, [court],
        now: alarmAt.add(const Duration(seconds: 5)));
    expect(notifier.shown, isEmpty,
        reason: 'T+5s is still inside the 1-min window');
    expect(checks.booked[7], alarmAt.add(const Duration(minutes: 1)),
        reason: 'still aiming at the cap');
    expect(await engine.store.loadHistory(), hasLength(1),
        reason: 'no final row until the cap');

    // Cap hit → final skip card + separate final history row.
    await engine.evaluateAlarm(short, [court],
        now: alarmAt.add(const Duration(minutes: 1)));
    final after = await engine.store.loadHistory();
    expect(after, hasLength(2));
    expect(after.first.watchedUntil, isNull, reason: 'final row');
    expect(after.last.watchedUntil, alarmAt.add(const Duration(minutes: 1)));
    expect(notifier.shown, hasLength(1));
  });

  test('per-alarm 60-min retry: watchedUntil = T+60m', () async {
    const long = NivaatAlarm(
      id: 7,
      hour: 6,
      minute: 0,
      courtId: 'c1',
      courtSpeedLimitKmh: 4,
      retryMinutesAfter: 60,
    );
    api.sample = wind(9.0, 10.0);
    await engine.evaluateAlarm(long, [court],
        now: alarmAt.subtract(const Duration(minutes: 1)));
    await engine.evaluateAlarm(long, [court], now: alarmAt);
    expect((await engine.store.loadHistory()).single.watchedUntil,
        alarmAt.add(const Duration(minutes: 60)));
    // Still retrying at +59m.
    await engine.evaluateAlarm(long, [court],
        now: alarmAt.add(const Duration(minutes: 59)));
    expect(notifier.shown, isEmpty, reason: 'not finalised before the hour');
    expect(checks.booked[7], alarmAt.add(const Duration(minutes: 60)));
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
    // THE regression guard. `log` above only proves the late ring was once
    // scheduled; what matters is that it SURVIVES. Finalising rolls straight
    // on to tomorrow in this same pass, and under one-locker-per-alarm that
    // pre-arm overwrote the late ring ~10s before it would have sounded —
    // silently, while history still recorded "Rang". Separate lockers now.
    expect(ring.scheduled[lateRing]!.at, late.add(const Duration(seconds: 10)),
        reason: 'the late ring must outlive the roll-on pre-arm');
    expect(ring.scheduled[todayRing]!.at,
        alarmAt.add(const Duration(days: 1)),
        reason: 'tomorrow pre-arms into its own locker, evicting nothing');
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
    expect(history.first.whenChecked, alarmAt.add(const Duration(minutes: 30)),
        reason: 'final row stamps the cap check, not the T reading');
    expect(history.last.watchedUntil, isNotNull, reason: 'the snapshot row');
    expect(notifier.shown, hasLength(1), reason: 'final card at the cap');
    expect(notifier.shown.first.$2, 'Home Court');
    expect((await engine.store.loadCheckState(7))!.alarmAt,
        alarmAt.add(const Duration(days: 1)),
        reason: "rolled on: tomorrow's occurrence already tracked");
  });

  test('cap wake a few seconds late still stamps checkedAt to that check',
      () async {
    // Device catch with a 1-min window: the wake scheduled for the cap often
    // lands ~1–3s late. Without a grace past the cap, that jumped to tomorrow
    // and reused the T reading as "checked" on the final skip row.
    const short = NivaatAlarm(
      id: 7,
      hour: 6,
      minute: 0,
      courtId: 'c1',
      courtSpeedLimitKmh: 4,
      retryMinutesAfter: 1,
    );
    api.sample = wind(9.0, 10.0);
    await engine.evaluateAlarm(short, [court],
        now: alarmAt.subtract(const Duration(minutes: 1)));
    await engine.evaluateAlarm(short, [court], now: alarmAt);

    final lateCap = alarmAt.add(const Duration(minutes: 1, seconds: 2));
    await engine.evaluateAlarm(short, [court], now: lateCap);

    final history = await engine.store.loadHistory();
    expect(history, hasLength(2));
    expect(history.first.watchedUntil, isNull);
    expect(history.first.whenChecked, lateCap,
        reason: 'slightly-late cap wake must run a fresh check, not reuse T');
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

    expect(ring.scheduled[todayRing]!.at.isAfter(lateNow), isTrue);
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
    ring.scheduled[todayRing] = (
      at: alarmAt,
      volume: 1.0,
      title: 'Home Court · 06:00 · Play! 🏸',
      body: 'ringing now'
    );
    ring.ringingIds.add(todayRing);

    // Resume the app an hour later → re-evaluates the NEXT (future) occurrence,
    // whose forecast is windy → skip. The live ring must survive.
    api.sample = wind(12.0, 14.0); // court 7.2 > 4 → windy
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.add(const Duration(hours: 1)));

    expect(ring.scheduled.containsKey(todayRing), isTrue,
        reason: 'a resync for a future occurrence must not silence the ring');
  });

  test('committed ring that fired (no T-0 check, iOS) is later logged rang, not skip',
      () async {
    // T-30m: a calm forecast commits the ring for THIS occurrence.
    api.sample = wind(5.0, 5.0); // court 3.0 <= 4 -> ring, volume 0.85
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 30)));
    expect(ring.scheduled.containsKey(todayRing), isTrue);

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
    expect(history.first.volume, 0.85);
    expect(notifier.shown, isEmpty, reason: 'a ring must never send a skip card');
    expect((await engine.store.loadCheckState(7))!.alarmAt,
        alarmAt.add(const Duration(days: 1)),
        reason: 'the same open rolls on to tomorrow (windy -> tracked, unarmed)');
  });

  test('committed ring is logged rang even when the app opens past the retry window',
      () async {
    // T-30m: calm forecast commits the ring for this occurrence.
    api.sample = wind(5.0, 5.0); // court 3.0 -> ring, volume 0.85
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 30)));
    expect(ring.scheduled.containsKey(todayRing), isTrue);

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
    expect(rangRows.first.volume, 0.85);
    expect(rangRows.first.courtSpeedLimitKmh, 4);
  });

  test('opening the app while its OWN ring still sounds: logged rang NOW, never cancelled',
      () async {
    api.sample = wind(5.0, 5.0); // calm -> ring committed at T-30m
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 30)));

    // The ring fired at T and is sounding now; wind has since risen.
    ring.ringingIds.add(todayRing);
    api.sample = wind(20.0, 24.0);
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.add(const Duration(minutes: 3)));

    expect(ring.scheduled.containsKey(todayRing), isTrue,
        reason: 'a sounding ring must not be cancelled');
    expect(notifier.shown, isEmpty);
    // Audible = final: the row is in history from THIS moment — before the
    // user stops the ring, not on some later open (2026-07-19).
    var history = await engine.store.loadHistory();
    expect(history, hasLength(1));
    expect(history.single.outcome, CheckOutcome.rang);
    expect(history.single.volume, 0.85);
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
      ringVolume: 0.85,
      lastCheckAt: alarmAt.subtract(const Duration(minutes: 30)),
    ));
    await engine.evaluateAlarm(alarm.copyWith(enabled: false), [court],
        now: alarmAt.add(const Duration(minutes: 2)));

    final history = await engine.store.loadHistory();
    expect(history, hasLength(1));
    expect(history.single.outcome, CheckOutcome.rang);
    expect(history.single.at, alarmAt);
    expect(history.single.volume, 0.85);
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

  group('ring lockers + card cleanup (2026-07-26)', () {
    /// Drives an occurrence to the point where a LATE ring is armed: windy
    /// through T (heads-up + retries), then calm at T+7 so a retry rings late.
    /// Finalising rolls straight on, so tomorrow ends up pre-armed too — both
    /// lockers occupied, which is the state these tests care about.
    Future<DateTime> armLateRing() async {
      api.sample = wind(9.0, 10.0); // windy — puts the occurrence in flight
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(minutes: 1)));
      await engine.evaluateAlarm(alarm, [court], now: alarmAt);
      api.sample = wind(5.0, 5.0); // calms inside the retry window
      final late = alarmAt.add(const Duration(minutes: 7));
      await engine.evaluateAlarm(alarm, [court], now: late);
      return late;
    }

    test('arming a late ring disarms the pre-arm it supersedes', () async {
      // The path where this is load-bearing: calm all the way, so the skip
      // branch never runs and nothing else clears the pre-arm. The ladder
      // commits a ring for T itself, then the T-0 check re-decides on live
      // wind and arms a ring 10s out. Both are for the SAME occurrence, so the
      // first must be disarmed — otherwise the alarm sounds at T and again at
      // T+10s. (The roll-on then refills the pre-arm locker with tomorrow in
      // the same pass, which is why `cancelled` is what proves this, not
      // `scheduled`.)
      api.sample = wind(5.0, 5.0); // calm
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(minutes: 1)));
      expect(ring.scheduled[todayRing]!.at, alarmAt, reason: 'pre-armed for T');
      ring.cancelled.clear();

      await engine.evaluateAlarm(alarm, [court], now: alarmAt);

      expect(ring.cancelled, contains(todayRing),
          reason: 'the superseded pre-arm must be cancelled, not left to fire');
      expect(ring.scheduled[lateRing]!.at,
          alarmAt.add(const Duration(seconds: 10)),
          reason: 'the T-0 ring lands in the late locker');
      expect(ring.scheduled[todayRing]!.at,
          alarmAt.add(const Duration(days: 1)),
          reason: 'the pre-arm locker is refilled with tomorrow');
    });

    test('a skip for the next occurrence never cancels a pending late ring',
        () async {
      final late = await armLateRing();
      expect(ring.scheduled.containsKey(lateRing), isTrue);

      // Tomorrow is now evaluated and is far too windy -> skip branch, which
      // must clear ONLY the pre-arm locker.
      api.sample = wind(20.0, 24.0);
      await engine.evaluateAlarm(alarm, [court],
          now: late.add(const Duration(minutes: 1)));

      expect(ring.scheduled[lateRing]!.at, late.add(const Duration(seconds: 10)),
          reason: 'a later skip must not disarm the ring about to sound');
    });

    test('a resync during a late ring never logs TOMORROW as rang', () async {
      // Regression: late rings live in their own locker, so a ring can be
      // audible while `stored` already tracks the NEXT occurrence (pre-armed
      // by the same roll-on). Rule 1 must not attribute that ring to tomorrow.
      final late = await armLateRing();
      final tomorrow = alarmAt.add(const Duration(days: 1));
      expect((await engine.store.loadCheckState(7))!.alarmAt, tomorrow);

      // The late ring is physically sounding and the user opens the app.
      ring.ringingIds.add(lateRing);
      await engine.evaluateAlarm(alarm, [court],
          now: late.add(const Duration(seconds: 20)));

      final history = await engine.store.loadHistory();
      expect(history.where((h) => h.at == tomorrow), isEmpty,
          reason: 'tomorrow has not happened yet — it cannot have rung');
      expect((await engine.store.loadCheckState(7))!.alarmAt, tomorrow,
          reason: "tomorrow's cascade state must survive a mid-ring resync");
      expect(ring.scheduled.containsKey(lateRing), isTrue,
          reason: 'and the sounding ring is still never cancelled');
    });

    test('deleting an alarm takes its notification cards down with it',
        () async {
      // Without this the "Still checking … watching until 06:30" heads-up
      // outlives the alarm and keeps promising something nothing is doing.
      api.sample = wind(9.0, 10.0); // windy
      await engine.store.saveAlarms([alarm]);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(minutes: 1)));
      await engine.evaluateAlarm(alarm, [court], now: alarmAt);
      expect(notifier.extended, hasLength(1), reason: 'heads-up is posted');
      expect(notifier.cancelled, isEmpty);

      // Delete removes it from the store first (controller order), then
      // evaluates the removed copy with enabled: false.
      await engine.store.saveAlarms([]);
      await engine.evaluateAlarm(alarm.copyWith(enabled: false), [court],
          now: alarmAt.add(const Duration(minutes: 5)));

      expect(notifier.cancelled, contains(alarm.id),
          reason: "a dead alarm's cards must be pulled down");
    });

    /// Controller toggle path: [abandonOccurrence] then evaluate.
    Future<void> toggleOffViaControllerPath(DateTime now) async {
      final off = alarm.copyWith(enabled: false);
      await engine.store.saveAlarms([off]);
      await engine.abandonOccurrence(alarm, now: now);
      await engine.evaluateAlarm(off, [court], now: now);
    }

    test('toggling off mid-window drops the heads-up promise', () async {
      api.sample = wind(9.0, 10.0);
      await engine.store.saveAlarms([alarm]);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(minutes: 1)));
      await engine.evaluateAlarm(alarm, [court], now: alarmAt);
      expect(notifier.extended, hasLength(1));
      expect(notifier.shown, isEmpty, reason: 'final skip not posted yet');

      final stopAt = alarmAt.add(const Duration(minutes: 5));
      await toggleOffViaControllerPath(stopAt);

      expect(notifier.cancelled, isEmpty,
          reason: 'full cancel is for delete/court-gone only');
      expect(notifier.cancelledHeadsUp, contains(alarm.id),
          reason: '"watching until 06:30" is a promise, and disabling the '
              'alarm is what stops anyone watching');
      expect(ring.scheduled, isEmpty, reason: 'rings still disarm');
      final snap = (await engine.store.loadHistory())
          .singleWhere((h) => h.watchedUntil != null);
      expect(snap.watchStoppedAt, stopAt);
      expect(
          nivaatStillWatchingNote(snap, now: stopAt, hasFinal: false),
          'watching until 06:30 · stopped at 06:05');
    });

    test('toggling off after the final skip keeps both shade cards', () async {
      // Window already ran to the cap: both cards are history, not a promise.
      api.sample = wind(9.0, 10.0);
      await engine.store.saveAlarms([alarm]);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(minutes: 1)));
      await engine.evaluateAlarm(alarm, [court], now: alarmAt);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.add(const Duration(minutes: 30)));
      expect(notifier.extended, hasLength(1));
      expect(notifier.shown, hasLength(1), reason: 'final skip card at the cap');

      await toggleOffViaControllerPath(
          alarmAt.add(const Duration(minutes: 31)));

      expect(notifier.cancelled, isEmpty,
          reason: 'cancelForAlarm would have pulled both cards down');
      expect(notifier.cancelledHeadsUp, isEmpty,
          reason: 'we did check until the cap — N2 is no longer a false promise');
      expect(notifier.shown, hasLength(1),
          reason: 'the skip record card is left in the shade');
      expect(notifier.extended, hasLength(1),
          reason: 'the heads-up stays as the at-T half of that morning');
    });

    test('toggling off after a late ring keeps the heads-up', () async {
      // Late ring is the final result; N2 was left standing on purpose.
      // Snapshot's watchedUntil is still in the future — the final row is
      // what marks the promise closed (not the calendar alone).
      api.sample = wind(9.0, 10.0);
      await engine.store.saveAlarms([alarm]);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(minutes: 1)));
      await engine.evaluateAlarm(alarm, [court], now: alarmAt);
      api.sample = wind(5.0, 5.0);
      final late = alarmAt.add(const Duration(minutes: 7));
      await engine.evaluateAlarm(alarm, [court], now: late);
      expect(notifier.extended, hasLength(1));

      await toggleOffViaControllerPath(late.add(const Duration(minutes: 1)));

      expect(notifier.cancelledHeadsUp, isEmpty,
          reason: 'final result already landed — N2 is history, not a promise');
      expect(notifier.extended, hasLength(1));
    });

    test('a missing court cancels cards even when the alarm is still saved',
        () async {
      api.sample = wind(9.0, 10.0);
      await engine.store.saveAlarms([alarm]);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(minutes: 1)));
      await engine.evaluateAlarm(alarm, [court], now: alarmAt);
      expect(notifier.extended, hasLength(1));

      // Court gone → cards go (orphan promise); alarm row may still exist
      // briefly before removeCourt finishes sweeping.
      await engine.evaluateAlarm(alarm, const [],
          now: alarmAt.add(const Duration(minutes: 5)));
      expect(notifier.cancelled, contains(alarm.id));
    });

    test('a disabled alarm is disarmed in BOTH lockers', () async {
      final late = await armLateRing();
      // Both lockers are occupied: the late ring, and tomorrow's pre-arm.
      expect(ring.scheduled.keys, containsAll(<int>[todayRing, lateRing]));

      await engine.evaluateAlarm(alarm.copyWith(enabled: false), [court],
          now: late.add(const Duration(minutes: 1)));

      expect(ring.scheduled.containsKey(todayRing), isFalse);
      expect(ring.scheduled.containsKey(lateRing), isFalse,
          reason: 'cancelling one locker leaves a disabled alarm still ringing');
    });
  });

  test('nivaatStillWatchingNote: live / final / stopped / failed', () {
    final snapshot = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: alarmAt,
        watchedUntil: alarmAt.add(const Duration(minutes: 30)),
        outcome: CheckOutcome.skippedWindy);
    expect(
        nivaatStillWatchingNote(snapshot,
            now: alarmAt.add(const Duration(minutes: 10)), hasFinal: false),
        'watching until 06:30');
    expect(
        nivaatStillWatchingNote(snapshot,
            now: alarmAt.add(const Duration(minutes: 30)), hasFinal: true),
        'watched until 06:30',
        reason: 'final landed — planned cap kept as watched until');
    expect(
        nivaatStillWatchingNote(snapshot,
            now: alarmAt.add(const Duration(minutes: 30)), hasFinal: false),
        'watching until 06:30 · failed',
        reason: 'past cap, no final, not user-stopped');
    expect(
        nivaatStillWatchingNote(
            snapshot.copyWith(
                watchStoppedAt: alarmAt.add(const Duration(minutes: 5))),
            now: alarmAt.add(const Duration(minutes: 40)),
            hasFinal: false),
        'watching until 06:30 · stopped at 06:05',
        reason: 'planned cap preserved; stopped appends');
    expect(
        nivaatStillWatchingNote(
            HistoryRecord(
                alarmId: 7,
                courtId: 'c1',
                at: alarmAt,
                outcome: CheckOutcome.skippedWindy),
            now: alarmAt,
            hasFinal: false),
        isNull,
        reason: 'final rows carry no watch note');
  });

  test('nivaatStillWatchingNote: dates the cap when it crosses midnight vs the alarm',
      () {
    final late = DateTime(2026, 7, 22, 23, 49);
    final snapshot = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: late,
        watchedUntil: late.add(const Duration(minutes: 30)),
        outcome: CheckOutcome.skippedWindy);
    expect(
        nivaatStillWatchingNote(snapshot,
            now: late.add(const Duration(hours: 1)), hasFinal: true),
        'watched until 23 Jul 00:19',
        reason: 'same rule as fmtCheckTime — bare 00:19 would look earlier than 23:49');
  });

  test('nivaatEditAbandonsInFlight: limit/retry/add-weekday continue; time/court/drop abandon',
      () {
    final flying = CheckState(alarmId: 7, alarmAt: alarmAt);
    expect(
        nivaatEditAbandonsInFlight(alarm, alarm.copyWith(courtSpeedLimitKmh: 6),
            state: flying, now: alarmAt.add(const Duration(minutes: 5))),
        isFalse);
    expect(
        nivaatEditAbandonsInFlight(alarm, alarm.copyWith(retryMinutesAfter: 60),
            state: flying, now: alarmAt.add(const Duration(minutes: 5))),
        isFalse);
    expect(
        nivaatEditAbandonsInFlight(
            alarm,
            alarm.copyWith(weekdays: {...alarm.weekdays, alarmAt.weekday % 7 + 1}),
            state: flying,
            now: alarmAt.add(const Duration(minutes: 5))),
        isFalse);
    expect(
        nivaatEditAbandonsInFlight(alarm, alarm.copyWith(hour: 7),
            state: flying, now: alarmAt.add(const Duration(minutes: 5))),
        isTrue);
    expect(
        nivaatEditAbandonsInFlight(alarm, alarm.copyWith(courtId: 'other'),
            state: flying, now: alarmAt.add(const Duration(minutes: 5))),
        isTrue);
    expect(
        nivaatEditAbandonsInFlight(alarm, alarm.copyWith(weekdays: {}),
            state: flying, now: alarmAt.add(const Duration(minutes: 5))),
        isTrue);
    expect(
        nivaatEditAbandonsInFlight(alarm, alarm.copyWith(enabled: false),
            state: flying, now: alarmAt.add(const Duration(minutes: 5))),
        isTrue);
  });

  group('mid-window edits keep or abandon the occurrence', () {
    test('raising the wind limit mid-window keeps retries flying', () async {
      // Windy at ≤4 → raise to ≤6 → wind 5 now rings late under the new limit.
      api.sample = wind(9.0, 10.0);
      await engine.store.saveCourts([court]);
      await engine.store.saveAlarms([alarm]);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(minutes: 1)));
      await engine.evaluateAlarm(alarm, [court], now: alarmAt);
      expect(notifier.extended, hasLength(1));

      final looser = alarm.copyWith(courtSpeedLimitKmh: 6);
      await engine.store.saveAlarms([looser]);
      await engine.retainInFlightEdits(alarm, looser,
          now: alarmAt.add(const Duration(minutes: 5)));
      api.sample = wind(5.0, 5.0);
      await engine.evaluateAlarm(looser, [court],
          now: alarmAt.add(const Duration(minutes: 5)));
      expect(
          ring.scheduled.containsKey(lateRing) ||
              ring.log.any((e) => e.id == lateRing),
          isTrue,
          reason: 'same morning rings late under the raised limit');
      expect(
          (await engine.store.loadHistory())
              .where((h) => h.watchStoppedAt != null),
          isEmpty,
          reason: 'continue path — not a user stop');
    });

    test('upsertAlarm raising the limit mid-window still late-rings', () async {
      // End-to-end through the controller dispatch — hard-wiring always-
      // abandon must fail this. Pins [now] for the clock; awaits
      // [lastEvaluation] so production's fire-and-forget interleaving still runs.
      api.sample = wind(9.0, 10.0);
      await engine.store.saveCourts([court]);
      final controller = NivaatController(engine: engine);
      await controller.init();
      expect(
          await controller.upsertAlarm(alarm,
              now: alarmAt.subtract(const Duration(minutes: 1))),
          isTrue);
      await controller.lastEvaluation;
      await engine.evaluateAlarm(
          controller.alarms.single, controller.courts,
          now: alarmAt);
      expect(notifier.extended, hasLength(1));

      api.sample = wind(5.0, 5.0);
      final t = alarmAt.add(const Duration(minutes: 5));
      expect(
          await controller.upsertAlarm(
              alarm.copyWith(courtSpeedLimitKmh: 6),
              now: t),
          isTrue);
      await controller.lastEvaluation;
      expect(
          ring.scheduled.containsKey(lateRing) ||
              ring.log.any((e) => e.id == lateRing),
          isTrue,
          reason: 'controller continue path — not abandonOccurrence');
      expect(
          (await engine.store.loadHistory())
              .where((h) => h.watchStoppedAt != null),
          isEmpty);
    });

    test('widening Keep checking mid-window moves the deadline only', () async {
      api.sample = wind(9.0, 10.0);
      final short = alarm.copyWith(retryMinutesAfter: 1);
      await engine.store.saveCourts([court]);
      await engine.store.saveAlarms([short]);
      await engine.evaluateAlarm(short, [court],
          now: alarmAt.subtract(const Duration(minutes: 1)));
      await engine.evaluateAlarm(short, [court], now: alarmAt);
      expect((await engine.store.loadHistory()).single.watchedUntil,
          alarmAt.add(const Duration(minutes: 1)));
      final firstBody = nivaatExtendedCheckBody(
        notifier.extended.single.$1,
        notifier.extended.single.$3,
      );

      final longer = short.copyWith(retryMinutesAfter: 30);
      final newCap = alarmAt.add(const Duration(minutes: 30));
      await engine.store.saveAlarms([longer]);
      await engine.retainInFlightEdits(short, longer,
          now: alarmAt.add(const Duration(seconds: 30)));
      expect((await engine.store.loadHistory()).single.watchedUntil, newCap);
      expect(notifier.cancelledHeadsUp, isEmpty,
          reason: 'deadline updates in place — no cancel/re-post');
      expect(notifier.extended, hasLength(2));
      expect(notifier.extended.last.$4, isTrue, reason: 'quiet update');
      final refreshed = nivaatExtendedCheckBody(
        notifier.extended.last.$1,
        notifier.extended.last.$3,
      );
      expect(refreshed, endsWith('watching until 06:30'));
      // Wind / limits stay the first heads-up's — only the deadline moved.
      expect(
        refreshed.replaceFirst(' · watching until 06:30', ''),
        firstBody.replaceFirst(' · watching until 06:01', ''),
      );
    });

    test('raising limit + widening Keep checking keeps first-heads-up numbers',
        () async {
      // The natural edit while staring at "Still checking, too windy": loosen
      // the limit AND extend the window. N2 must not read "Too windy · (≤20)".
      api.sample = wind(9.0, 10.0);
      await engine.store.saveCourts([court]);
      await engine.store.saveAlarms([alarm]);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(minutes: 1)));
      await engine.evaluateAlarm(alarm, [court], now: alarmAt);
      expect(notifier.extended, hasLength(1));

      final edited = alarm.copyWith(
        courtSpeedLimitKmh: 20,
        retryMinutesAfter: 60,
      );
      final newCap = alarmAt.add(const Duration(minutes: 60));
      await engine.store.saveAlarms([edited]);
      await engine.retainInFlightEdits(alarm, edited,
          now: alarmAt.add(const Duration(minutes: 5)));

      expect(notifier.extended, hasLength(2));
      final body = nivaatExtendedCheckBody(
        notifier.extended.last.$1,
        notifier.extended.last.$3,
      );
      expect(body, contains('≤4'),
          reason: 'limits from the decision, not the Save');
      expect(body, isNot(contains('≤20')));
      expect(body, endsWith('watching until 07:00'));
      expect(
        (await engine.store.loadHistory())
            .singleWhere((h) => h.watchedUntil != null)
            .courtSpeedLimitKmh,
        4,
        reason: 'history snapshot keeps decision-time limits too',
      );
      expect(
        (await engine.store.loadHistory())
            .singleWhere((h) => h.watchedUntil != null)
            .watchedUntil,
        newCap,
      );
    });

    test('shrinking Keep checking past now finalises and keeps both cards',
        () async {
      api.sample = wind(9.0, 10.0);
      await engine.store.saveCourts([court]);
      await engine.store.saveAlarms([alarm]);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(minutes: 1)));
      await engine.evaluateAlarm(alarm, [court], now: alarmAt);

      final tiny = alarm.copyWith(retryMinutesAfter: 1);
      final t = alarmAt.add(const Duration(minutes: 2));
      final newCap = alarmAt.add(const Duration(minutes: 1));
      await engine.store.saveAlarms([tiny]);
      await engine.retainInFlightEdits(alarm, tiny, now: t);
      expect(notifier.cancelledHeadsUp, isEmpty,
          reason: 'old promise updates to the new cap — not pulled');
      expect(
        (await engine.store.loadHistory()).single.watchedUntil,
        newCap,
      );
      expect(notifier.extended, hasLength(2));
      expect(
        nivaatExtendedCheckBody(
          notifier.extended.last.$1,
          notifier.extended.last.$3,
        ),
        endsWith('watching until 06:01'),
      );

      await engine.evaluateAlarm(tiny, [court], now: t);

      final history = await engine.store.loadHistory();
      expect(
          history.any((h) =>
              h.watchedUntil == null &&
              h.at == alarmAt &&
              h.outcome != CheckOutcome.rang),
          isTrue,
          reason: 'cap already past → final skip for today, not stopped at');
      expect(history.where((h) => h.watchStoppedAt != null), isEmpty);
      expect(notifier.shown, isNotEmpty, reason: 'final skip card posted');
      expect(notifier.cancelledHeadsUp, isEmpty,
          reason: 'both cards stay — N2 deadline updated, N3 beside it');
    });

    test('changing the alarm time mid-window abandons with stopped at',
        () async {
      api.sample = wind(9.0, 10.0);
      await engine.store.saveCourts([court]);
      await engine.store.saveAlarms([alarm]);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(minutes: 1)));
      await engine.evaluateAlarm(alarm, [court], now: alarmAt);

      final moved = alarm.copyWith(hour: 7);
      final t = alarmAt.add(const Duration(minutes: 5));
      await engine.store.saveAlarms([moved]);
      await engine.abandonOccurrence(alarm, now: t);
      await engine.evaluateAlarm(moved, [court], now: t);

      expect(notifier.cancelledHeadsUp, contains(alarm.id));
      final snap = (await engine.store.loadHistory())
          .firstWhere((h) => h.watchedUntil != null);
      expect(snap.watchStoppedAt, t);
      expect(snap.at, alarmAt, reason: 'snapshot stays the abandoned morning');
    });

    test('adding a weekday mid-window keeps today flying', () async {
      api.sample = wind(9.0, 10.0);
      await engine.store.saveCourts([court]);
      await engine.store.saveAlarms([alarm]);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(minutes: 1)));
      await engine.evaluateAlarm(alarm, [court], now: alarmAt);
      final otherDay = alarmAt.weekday % 7 + 1;
      final added =
          alarm.copyWith(weekdays: {...alarm.weekdays, otherDay});
      expect(
          nivaatEditAbandonsInFlight(alarm, added,
              state: await engine.store.loadCheckState(7),
              now: alarmAt.add(const Duration(minutes: 5))),
          isFalse);
      await engine.store.saveAlarms([added]);
      await engine.retainInFlightEdits(alarm, added,
          now: alarmAt.add(const Duration(minutes: 5)));
      await engine.evaluateAlarm(added, [court],
          now: alarmAt.add(const Duration(minutes: 5)));
      expect((await engine.store.loadCheckState(7))!.alarmAt, alarmAt);
      expect(notifier.cancelledHeadsUp, isEmpty);
    });

    test('dropping the in-flight weekday abandons with stopped at', () async {
      api.sample = wind(9.0, 10.0);
      await engine.store.saveCourts([court]);
      await engine.store.saveAlarms([alarm]);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(minutes: 1)));
      await engine.evaluateAlarm(alarm, [court], now: alarmAt);
      final withoutToday = alarm.copyWith(
          weekdays: {...alarm.weekdays}..remove(alarmAt.weekday));
      final t = alarmAt.add(const Duration(minutes: 5));
      expect(
          nivaatEditAbandonsInFlight(alarm, withoutToday,
              state: await engine.store.loadCheckState(7), now: t),
          isTrue);
      await engine.store.saveAlarms([withoutToday]);
      await engine.abandonOccurrence(alarm, now: t);
      expect(notifier.cancelledHeadsUp, contains(alarm.id));
      expect(
          (await engine.store.loadHistory())
              .singleWhere((h) => h.watchedUntil != null)
              .watchStoppedAt,
          t);
    });

    test('widening Keep checking after the old cap does not resurrect',
        () async {
      // Defence in depth: a real Save always resyncs first (which finalises
      // the dead window), so this branch is rarely hit end-to-end. Keep N2.
      api.sample = wind(9.0, 10.0);
      final short = alarm.copyWith(retryMinutesAfter: 1);
      await engine.store.saveCourts([court]);
      await engine.store.saveAlarms([short]);
      await engine.evaluateAlarm(short, [court],
          now: alarmAt.subtract(const Duration(minutes: 1)));
      await engine.evaluateAlarm(short, [court], now: alarmAt);
      // Past T+1 without evaluating the cap — state still today.
      final longer = short.copyWith(retryMinutesAfter: 30);
      final t = alarmAt.add(const Duration(minutes: 2));
      await engine.store.saveAlarms([longer]);
      await engine.retainInFlightEdits(short, longer, now: t);
      final history = await engine.store.loadHistory();
      expect(
          history
              .firstWhere((h) => h.watchedUntil != null)
              .watchedUntil,
          alarmAt.add(const Duration(minutes: 1)),
          reason: 'must not rewrite a dead 1m window into +30m');
      expect(
          history.any((h) => h.watchedUntil == null && h.at == alarmAt),
          isTrue,
          reason: 'finalises immediately instead of reviving under +30m');
      expect(await engine.store.loadCheckState(7), isNull,
          reason: 'dead window cleared; evaluate must not reopen it');
      expect(notifier.cancelledHeadsUp, isEmpty,
          reason: 'both cards stay after the defence final');
      expect(notifier.shown, isNotEmpty);
    });

    test('toggle-off later does not rewrite an ancient failed snapshot',
        () async {
      final oldAt = alarmAt.subtract(const Duration(days: 7));
      await engine.store.upsertHistory(HistoryRecord(
        alarmId: alarm.id,
        courtId: court.id,
        at: oldAt,
        watchedUntil: oldAt.add(const Duration(minutes: 30)),
        outcome: CheckOutcome.skippedWindy,
      ));
      // No final for that week — shows `· failed`. Toggle off today.
      await engine.store.saveAlarms([alarm.copyWith(enabled: false)]);
      await engine.abandonOccurrence(alarm,
          now: alarmAt.add(const Duration(hours: 1)));
      expect(
          (await engine.store.loadHistory()).single.watchStoppedAt,
          isNull,
          reason: 'ancient failed rows stay failed, not stopped at today');
    });
  });

  test('nivaatHistoryHasFinal keys on alarmId + at', () {
    final snap = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: alarmAt,
        watchedUntil: alarmAt.add(const Duration(minutes: 30)),
        outcome: CheckOutcome.skippedWindy);
    final finalRow = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: alarmAt,
        outcome: CheckOutcome.rang,
        volume: 1);
    expect(nivaatHistoryHasFinal([snap], snap), isFalse);
    expect(nivaatHistoryHasFinal([snap, finalRow], snap), isTrue);
    // Bulk keys include finals; hasFinal guards them out — not equivalent
    // when the probe is itself a final row.
    expect(nivaatHistoryHasFinal([snap, finalRow], finalRow), isFalse);
    expect(
        nivaatFinalizedWatchKeys([snap, finalRow])
            .contains(
                '${finalRow.alarmId}@${finalRow.at.millisecondsSinceEpoch}'),
        isTrue);
    expect(
        nivaatHistoryHasFinal([
          snap,
          HistoryRecord(
              alarmId: 7,
              courtId: 'c1',
              at: alarmAt.add(const Duration(days: 1)),
              outcome: CheckOutcome.rang,
              volume: 1),
        ], snap),
        isFalse,
        reason: 'a final for another morning does not close this snapshot');
  });

  test('an off-step volume snaps to the nearest file, ties going louder', () {
    // volumeForWind only ever returns a step, but a persisted CheckState from
    // an older build can carry anything — it must still resolve to a shipped
    // file rather than falling off the end of the ramp.
    final was = nivaatSelectedSound;
    addTearDown(() => nivaatSelectedSound = was);
    nivaatSelectedSound = null;

    const loud = nivaatDefaultSound;
    const mid = 'assets/sounds/nivaat_ring_85.wav';
    const quiet = 'assets/sounds/nivaat_ring_70.wav';

    expect(nivaatSoundForVolume(0.93), loud);
    expect(nivaatSoundForVolume(0.925), loud, reason: 'tie -> the louder step');
    expect(nivaatSoundForVolume(0.92), mid);
    expect(nivaatSoundForVolume(0.78), mid);
    expect(nivaatSoundForVolume(0.775), mid, reason: 'tie -> the louder step');
    expect(nivaatSoundForVolume(0.77), quiet);
    expect(nivaatSoundForVolume(0), quiet);
    // Out of range on both sides still lands on a real file.
    expect(nivaatSoundForVolume(-1), quiet);
    expect(nivaatSoundForVolume(2), loud);
  });

  test('every sound the ramp can name is actually shipped', () {
    // The ring asset is chosen at schedule time from a computed filename, so a
    // variant that isn't in assets/ fails at RING time — silently, hours later,
    // on the one morning it mattered. Sweep the whole ramp against the disk.
    final was = nivaatSelectedSound;
    addTearDown(() => nivaatSelectedSound = was);
    nivaatSelectedSound = null;

    final named = <String>{};
    for (var i = 0; i <= 100; i++) {
      named.add(nivaatSoundForVolume(i / 100));
    }
    for (final path in named) {
      expect(File(path).existsSync(), isTrue,
          reason: '$path is named by the ramp but not shipped in assets/');
    }
    expect(named, hasLength(windVolumeSteps.length),
        reason: 'one asset per loudness step, no more and no fewer');
    expect(named, contains(nivaatDefaultSound),
        reason: 'full loudness IS the master — no byte-identical _100 copy');

    // And the ramp's own three values must be exactly those assets: a step
    // added to windVolumeSteps without a matching file would silently snap
    // onto its neighbour instead of failing.
    expect(windVolumeSteps.map(nivaatSoundForVolume).toSet(), named);
  });

  group('nivaatHistoryLine', () {
    final at = DateTime(2026, 7, 22, 6);
    HistoryRecord row(CheckOutcome outcome, {double? volume}) => HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: at,
        outcome: outcome,
        courtSpeedKmh: 3,
        rawGustKmh: 16,
        courtSpeedLimitKmh: 4,
        rawGustLimitKmh: 14.667,
        volume: volume);

    test('quotes the volume it rang at, alongside the numbers', () {
      expect(nivaatHistoryLine(row(CheckOutcome.rang, volume: 0.85)),
          'Rang (vol. 85%) · wind 3 (≤4) · gusts 16 (≤15) km/h');
    });

    test('a rang row without a volume drops the number, never the sheet', () {
      // `volume` is optional on the record, and history is PERSISTED: force-
      // unwrapping it meant one such row crashed the log open-after-open. The
      // row still has to explain the morning, so only the parenthetical goes.
      expect(nivaatHistoryLine(row(CheckOutcome.rang)),
          'Rang · wind 3 (≤4) · gusts 16 (≤15) km/h',
          reason: 'degrades like whenChecked and windGustSummary do');
    });

    test('a row with no readings never ends in a dangling separator', () {
      // windGustSummary degrades to '' when the numbers are missing, so the
      // " · " that joins it has to go with them — a row reading "Rang · " is
      // the same broken-looking log the null check was there to avoid.
      final bare = HistoryRecord(
          alarmId: 7, courtId: 'c1', at: at, outcome: CheckOutcome.rang);
      expect(nivaatHistoryLine(bare), 'Rang');
      expect(
          nivaatHistoryLine(HistoryRecord(
              alarmId: 7,
              courtId: 'c1',
              at: at,
              outcome: CheckOutcome.rang,
              volume: 0.85)),
          'Rang (vol. 85%)');
    });

    test('each skip reads as its own reason', () {
      expect(nivaatHistoryLine(row(CheckOutcome.skippedWindy)),
          'Skipped · wind 3 (≤4) · gusts 16 (≤15) km/h');
      expect(nivaatHistoryLine(row(CheckOutcome.skippedGusty)),
          'Skipped (gusty) · wind 3 (≤4) · gusts 16 (≤15) km/h');
      // `row` carries readings, so this also pins that a no-data row SUPPRESSES
      // them: numbers on a row labelled "no data" would contradict the label.
      expect(nivaatHistoryLine(row(CheckOutcome.skippedNoData)),
          'Skipped (no data)',
          reason: 'nothing was measured — no numbers to quote');
    });
  });

  /// In-flight cascade for [at] — what the home cue needs to treat a snapshot
  /// as still being checked (toggle-off clears this; toggle-on re-arms later).
  CheckState flying(DateTime at, {int id = 7}) => CheckState(
        alarmId: id,
        alarmAt: at,
        extendedCheckShown: true,
        skipCourtSpeedKmh: 5.4,
        skipRawGustKmh: 10,
      );

  test('nivaatAlarmListSub: default retry stays silent; others show +Nm', () {
    expect(nivaatAlarmListSub(alarm, court), 'Every day · Home Court · ≤4 km/h');
    expect(
      nivaatAlarmListSub(alarm.copyWith(retryMinutesAfter: 1), court),
      'Every day · Home Court · ≤4 km/h · +1m',
    );
    expect(
      nivaatAlarmListSub(alarm.copyWith(retryMinutesAfter: 60), court),
      'Every day · Home Court · ≤4 km/h · +60m',
    );
    expect(
      nivaatAlarmListSub(alarm, null),
      'Every day · court removed · ≤4 km/h',
    );
  });

  test('nivaatInLabel / nivaatNextRingAt: countdown only for a future ring', () {
    final now = DateTime(2026, 7, 12, 5, 0);
    // Sentence case — Nivaat body text, not Arunoday's ALL-CAPS label strip.
    expect(nivaatInLabel(alarmAt, now: now), 'in 1h 00m');
    expect(nivaatInLabel(alarmAt, now: alarmAt), 'in 0h 00m');
    expect(nivaatInLabel(alarmAt, now: alarmAt.add(const Duration(minutes: 1))),
        '');
    expect(nivaatNextRingAt(alarm, null, now: now), alarmAt);
    expect(
      nivaatNextRingAt(alarm.copyWith(enabled: false), null, now: now),
      isNull,
      reason: 'a home row with its switch off must not advertise a ring',
    );
    expect(
      nivaatNextRingAt(alarm.copyWith(enabled: false), null,
          now: now, ignoreEnabled: true),
      alarmAt,
      reason: 'the editor DOES count down for an off alarm — you are picking a '
          'time there, so the time left is the feedback (Samyak, 2026-07-26)',
    );
    expect(
      nivaatNextRingAt(alarm.copyWith(weekdays: {}), null,
          now: now, ignoreEnabled: true),
      isNull,
      reason: 'no weekday can fire — nothing to count down to, even in the '
          'editor',
    );
    // In-flight pre-T state wins over nextOccurrence.
    final flying = CheckState(alarmId: 7, alarmAt: alarmAt);
    expect(nivaatNextRingAt(alarm, flying, now: now), alarmAt);
    // Post-T retry still open — hide countdown (late ring is anytime).
    expect(
      nivaatNextRingAt(alarm, flying,
          now: alarmAt.add(const Duration(minutes: 10))),
      isNull,
      reason: 'must not flash tomorrow beside Still checking … until …',
    );
    expect(
      nivaatNextRingAt(alarm.copyWith(retryMinutesAfter: 1), flying,
          now: alarmAt.add(const Duration(seconds: 30))),
      isNull,
    );
  });

  test('nivaatInLabel switches to days past 24h', () {
    // Nivaat alarms carry weekdays, so a multi-day gap is ordinary, not an
    // edge: a Sat/Sun badminton alarm is five days out every Monday. Hours
    // alone would read "in 120h 00m".
    final monday = DateTime(2026, 7, 13, 6, 0);
    expect(monday.weekday, DateTime.monday, reason: 'fixture sanity');
    expect(nivaatInLabel(DateTime(2026, 7, 18, 10, 0), now: monday), 'in 5d 04h');
    expect(nivaatInLabel(DateTime(2026, 7, 18, 6, 30), now: monday), 'in 5d 00h');
    // The seam: hours up to 23h59m, days from 24h.
    expect(
        nivaatInLabel(monday.add(const Duration(hours: 23, minutes: 59)),
            now: monday),
        'in 23h 59m');
    expect(nivaatInLabel(monday.add(const Duration(hours: 24)), now: monday),
        'in 1d 00h');
    // Day form truncates to the hour — each form drops what's below its
    // smallest unit, and at a day's range half an hour is noise.
    expect(
        nivaatInLabel(monday.add(const Duration(hours: 24, minutes: 30)),
            now: monday),
        'in 1d 00h');
  });

  test('nivaatOccurrenceInFlight is the one rule home and the engine share',
      () {
    final state = CheckState(alarmId: 7, alarmAt: alarmAt);
    final cap = alarm.retryCapAt(alarmAt);
    expect(nivaatOccurrenceInFlight(alarm, state, cap), isTrue);
    expect(
      nivaatOccurrenceInFlight(
          alarm, state, cap.add(const Duration(seconds: 3))),
      isTrue,
      reason: 'a cap wake landing a few seconds late is still this occurrence',
    );
    expect(
      nivaatOccurrenceInFlight(
          alarm, state, cap.add(const Duration(seconds: 6))),
      isFalse,
    );
    // A state whose weekday is no longer selected isn't in flight — and home
    // has to agree, or it would count down to an occurrence the engine has
    // already dropped (the rule used to live twice, in slightly different
    // forms).
    final movedDay = alarm.copyWith(weekdays: {alarmAt.weekday % 7 + 1});
    expect(nivaatOccurrenceInFlight(movedDay, state, alarmAt), isFalse);
    expect(
      nivaatNextRingAt(movedDay, state, now: alarmAt),
      movedDay.nextOccurrence(alarmAt),
      reason: 'falls through to the next real occurrence, like the engine',
    );
  });

  test('nivaatUntilNextMinute aligns to the next wall-clock :00', () {
    final mid = DateTime(2026, 7, 12, 6, 30, 17, 250);
    expect(nivaatUntilNextMinute(mid), const Duration(seconds: 42, milliseconds: 750));
    final onTheMinute = DateTime(2026, 7, 12, 6, 30);
    expect(nivaatUntilNextMinute(onTheMinute), const Duration(minutes: 1));
  });

  test('nivaatHomeWatchingLine: only while a snapshot window is still open', () {
    final snapshot = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: alarmAt,
        watchedUntil: alarmAt.add(const Duration(minutes: 30)),
        outcome: CheckOutcome.skippedWindy);
    final alarms = [alarm];
    final states = [flying(alarmAt)];
    expect(
      nivaatHomeWatchingLine([snapshot],
          alarms: alarms,
          checkStates: states,
          now: alarmAt.add(const Duration(minutes: 10))),
      'Still checking wind · until 06:30',
    );
    expect(
      nivaatHomeWatchingLine([snapshot],
          alarms: alarms,
          checkStates: states,
          now: alarmAt.add(const Duration(minutes: 30))),
      isNull,
      reason: 'window closed — home stays clean',
    );
    expect(
      nivaatHomeWatchingLine(const [],
          alarms: alarms, checkStates: states, now: alarmAt),
      isNull,
    );
  });

  test('nivaatHomeWatchingLine: clears once a final row lands for that occurrence',
      () {
    // Late ring (or cap skip): history keeps the snapshot, but checking is
    // over — the cue must not contradict the "Rang" / "Skipped" row.
    final snapshot = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: alarmAt,
        watchedUntil: alarmAt.add(const Duration(minutes: 30)),
        outcome: CheckOutcome.skippedWindy);
    final rang = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: alarmAt,
        outcome: CheckOutcome.rang,
        volume: 0.9);
    expect(
      nivaatHomeWatchingLine([rang, snapshot],
          alarms: [alarm],
          checkStates: [flying(alarmAt)],
          now: alarmAt.add(const Duration(minutes: 10))),
      isNull,
      reason: 'final row for same alarmId+at means checking stopped',
    );
  });

  test('nivaatHomeWatchingLine: a final for a *different* occurrence stays quiet about this one',
      () {
    final snapshot = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: alarmAt,
        watchedUntil: alarmAt.add(const Duration(minutes: 30)),
        outcome: CheckOutcome.skippedWindy);
    final otherFinal = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: alarmAt.subtract(const Duration(days: 1)),
        outcome: CheckOutcome.rang,
        volume: 0.9);
    expect(
      nivaatHomeWatchingLine([otherFinal, snapshot],
          alarms: [alarm],
          checkStates: [flying(alarmAt)],
          now: alarmAt.add(const Duration(minutes: 10))),
      'Still checking wind · until 06:30',
      reason: 'yesterday\'s final must not silence today\'s open window',
    );
  });

  test('nivaatHomeWatchingLine: clears when the alarm is deleted or disabled', () {
    final snapshot = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: alarmAt,
        watchedUntil: alarmAt.add(const Duration(minutes: 30)),
        outcome: CheckOutcome.skippedWindy);
    final now = alarmAt.add(const Duration(minutes: 10));
    final states = [flying(alarmAt)];
    expect(
      nivaatHomeWatchingLine([snapshot],
          alarms: const [], checkStates: states, now: now),
      isNull,
      reason: 'deleted — nothing is checking',
    );
    expect(
      nivaatHomeWatchingLine([snapshot],
          alarms: [alarm.copyWith(enabled: false)],
          checkStates: states,
          now: now),
      isNull,
      reason: 'disabled — cascade cancelled',
    );
  });

  test('nivaatHomeWatchingLine: clears when CheckState no longer targets that occurrence',
      () {
    // Skip at 06:00 → toggle off (state discarded) → toggle on (state is
    // tomorrow). Snapshot still says watching until 06:30 — cue must not lie.
    final snapshot = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: alarmAt,
        watchedUntil: alarmAt.add(const Duration(minutes: 30)),
        outcome: CheckOutcome.skippedWindy);
    final now = alarmAt.add(const Duration(minutes: 12));
    expect(
      nivaatHomeWatchingLine([snapshot],
          alarms: [alarm], checkStates: const [], now: now),
      isNull,
      reason: 'discarded — no live cascade for today',
    );
    expect(
      nivaatHomeWatchingLine([snapshot],
          alarms: [alarm],
          checkStates: [flying(alarmAt.add(const Duration(days: 1)))],
          now: now),
      isNull,
      reason: 're-armed for tomorrow — today\'s retries will not resume',
    );
  });

  test('nivaatHomeWatchingLine: dates the cap when it crosses midnight', () {
    final late = DateTime(2026, 7, 22, 23, 49);
    final snapshot = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: late,
        watchedUntil: late.add(const Duration(minutes: 30)),
        outcome: CheckOutcome.skippedWindy);
    expect(
      nivaatHomeWatchingLine([snapshot],
          alarms: [alarm],
          checkStates: [flying(late)],
          now: late.add(const Duration(minutes: 5))),
      'Still checking wind · until 23 Jul 00:19',
    );
  });

  test('nivaatHomeWatchingLine: with several open windows, quotes the soonest',
      () {
    final early = HistoryRecord(
        alarmId: 1,
        courtId: 'c1',
        at: alarmAt,
        watchedUntil: alarmAt.add(const Duration(minutes: 30)),
        outcome: CheckOutcome.skippedWindy);
    final laterAt = alarmAt.add(const Duration(minutes: 15));
    final later = HistoryRecord(
        alarmId: 2,
        courtId: 'c1',
        at: laterAt,
        watchedUntil: alarmAt.add(const Duration(minutes: 45)),
        outcome: CheckOutcome.skippedWindy);
    const a1 = NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1');
    const a2 = NivaatAlarm(id: 2, hour: 6, minute: 15, courtId: 'c1');
    // Newest-first order would surface `later` first — the cue must still
    // name the soonest cap (matches the home dismiss timer).
    expect(
      nivaatHomeWatchingLine([later, early],
          alarms: [a1, a2],
          checkStates: [flying(alarmAt, id: 1), flying(laterAt, id: 2)],
          now: alarmAt.add(const Duration(minutes: 10))),
      'Still checking wind · until 06:30',
    );
  });

  test('a fired ring whose court is gone is cleared, not logged as orphan',
      () async {
    // removeCourt already sweeps history; if evaluate still runs with a stale
    // empty courts list, don't mint a court-less "rang" row (2026-07-22).
    await engine.store.saveCheckState(CheckState(
      alarmId: 7,
      alarmAt: alarmAt,
      ringScheduled: true,
      ringCourtSpeedKmh: 1.8,
      ringRawGustKmh: 6.0,
      ringVolume: 0.85,
      lastCheckAt: alarmAt.subtract(const Duration(minutes: 30)),
    ));
    await engine.evaluateAlarm(alarm, const [],
        now: alarmAt.add(const Duration(minutes: 2)));

    expect(await engine.store.loadHistory(), isEmpty);
    expect(await engine.store.loadCheckState(7), isNull);
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
    expect(nivaatSoundForVolume(0.70), 'assets/sounds/nivaat_ring_70.wav');
  });
}
