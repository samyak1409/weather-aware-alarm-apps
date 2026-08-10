import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/engine.dart';
import 'package:nivaat/src/ids.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine_fakes.dart';

/// Injects a host drop while [savePendingRing] is awaited — models the
/// auto-drain race against post-T hold / `_rollOn` (C1).
class _DropOnPendingSaveStore extends NivaatStore {
  Future<void> Function(PendingRing pending)? afterFirstHoldSave;
  bool _fired = false;

  @override
  Future<void> savePendingRing(PendingRing pending) async {
    await super.savePendingRing(pending);
    if (_fired || !pending.rollOnDone) return;
    _fired = true;
    final hook = afterFirstHoldSave;
    if (hook != null) await hook(pending);
  }
}

/// Emits a host event from INSIDE `scheduleRing`, before it returns.
///
/// This is the only way to test the real window: the gap between the platform
/// accepting a ring and the app recording that it owes one is a single
/// microtask as that future completes, so a test that clears state afterwards
/// is modelling the shape rather than reproducing it.
class _EmitsDuringSchedule extends FakeRing {
  HostAlarmEvent Function(int id, DateTime at)? emitOnSchedule;

  @override
  Future<bool> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double? volume,
  }) async {
    final ok = await super.scheduleRing(
      id: id,
      at: at,
      title: title,
      body: body,
      volume: volume,
    );
    final make = emitOnSchedule;
    if (ok && make != null) {
      emitOnSchedule = null;
      // **Drained before this returns**, so the handler provably runs while
      // the arming pass is still between accepting the ring and recording it.
      // Merely queueing raced: the pending was usually saved first and the
      // test passed with or without the fix.
      await emitHostEvent(make(id, at));
    }
    return ok;
  }
}

/// Host-event / pending-ring regression matrix. What is NOT here, because a
/// desk cannot check it: the real `Alarm.init()` replay ordering on hardware.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRing ring;
  late FakeChecks checks;
  late FakeApi api;
  late FakeNotifier notifier;
  late NivaatEngine engine;

  const court = SavedLocation(
    id: 'c1',
    name: 'Society Court',
    lat: 26.9,
    lon: 75.8,
  );
  const alarm = NivaatAlarm(
    id: 7,
    hour: 6,
    minute: 0,
    courtId: 'c1',
    courtSpeedLimitKmh: 4,
  );
  final alarmAt = DateTime(2026, 8, 8, 6, 0);
  final tomorrow = alarmAt.add(const Duration(days: 1));
  final dayAfter = alarmAt.add(const Duration(days: 2));
  final lateRing = NivaatIds.lateRing(alarm.id);
  final nextRing = NivaatIds.nextRing(alarm.id);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ring = FakeRing();
    checks = FakeChecks();
    api = FakeApi();
    notifier = FakeNotifier();
    final store = NivaatStore();
    await store.saveCourts([court]);
    await store.saveAlarms([alarm]);
    await store.saveAlarmIdSeq(8);
    engine = NivaatEngine(
      store: store,
      scheduler: ring,
      api: api,
      checks: checks,
      notifier: notifier,
    );
  });

  Future<void> armCalmAtT() async {
    api.sample = wind(5.0, 5.0);
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 2)));
    await engine.evaluateAlarm(alarm, [court], now: alarmAt);
  }

  /// An alarm armed AT T on the live clock, with a pending held for it.
  ///
  /// Any test whose host event is handled OUTSIDE an evaluate lane needs this
  /// rather than the file's 2026-08-08 fixture, because there `_nowFor` falls
  /// back to the wall clock. Two ways that bites. A move about a ring whose
  /// time has passed is correctly ignored as a stale replay, so the test
  /// exercises the rejection path and passes whether or not the rule under
  /// test exists. And `_rollOn` prefers the later of that clock and just-past
  /// `closed`, so a past-dated `closed` never reaches the `afterClosed` guard
  /// — and whatever the wall clock made true the morning the test was written
  /// stops being true a day later (H5 began failing on its own). Seconds are
  /// stripped so `nextOccurrence` lands on the minute rather than rolling to
  /// tomorrow.
  Future<
      ({
        NivaatEngine engine,
        NivaatStore store,
        FakeRing ring,
        NivaatAlarm alarm,
        DateTime at,
      })> armLiveAtT() async {
    SharedPreferences.setMockInitialValues({});
    final base = DateTime.now();
    final at = DateTime(base.year, base.month, base.day, base.hour)
        .add(Duration(minutes: base.minute + 5));
    final live = NivaatAlarm(
      id: 7,
      hour: at.hour,
      minute: at.minute,
      courtId: 'c1',
      courtSpeedLimitKmh: 4,
    );
    final store = NivaatStore();
    await store.saveCourts([court]);
    await store.saveAlarms([live]);
    await store.saveAlarmIdSeq(8);
    final sched = FakeRing();
    final e = NivaatEngine(
      store: store,
      scheduler: sched,
      api: FakeApi()..sample = wind(5.0, 5.0),
      checks: FakeChecks(),
      notifier: FakeNotifier(),
    );
    await e.evaluateAlarm(live, [court],
        now: at.subtract(const Duration(minutes: 2)));
    await e.evaluateAlarm(live, [court], now: at);
    return (engine: e, store: store, ring: sched, alarm: live, at: at);
  }

  test('post-T schedule success holds pending — no Rang until settle', () async {
    await armCalmAtT();
    final history = await engine.store.loadHistory();
    expect(
        history.where((r) =>
            r.outcome == CheckOutcome.rang &&
            r.ringDisposition != RingDisposition.missed &&
            r.ringDisposition != RingDisposition.unknown),
        isEmpty,
        reason: 'schedule success must not write Rang (decision 3)');
    final pending = await engine.store.loadPendingRing(alarm.id);
    expect(pending, isNotNull);
    expect(pending!.occurrenceAt, alarmAt);
    expect(pending.rollOnDone, isTrue);
  });

  test('known drop settles pending as Missed and is idempotent on replay',
      () async {
    await armCalmAtT();
    final pending = (await engine.store.loadPendingRing(alarm.id))!;
    ring.scheduled.remove(pending.pluginId);

    final event = HostAlarmEvent(
      id: pending.pluginId,
      kind: HostAlarmEventKind.dropped,
      cause: HostAlarmEventCause.platformRefusal,
      recordedAt: alarmAt.add(const Duration(seconds: 5)),
      at: pending.scheduledFor,
    );
    await ring.emitHostEvent(event);
    await engine.evaluateAll(now: alarmAt.add(const Duration(seconds: 10)));

    var visible = await engine.store.loadHistory();
    expect(
        visible.where((r) =>
            r.ringDisposition == RingDisposition.missed && r.at == alarmAt),
        isNotEmpty);
    expect(await engine.store.loadPendingRing(alarm.id), isNull);

    await ring.emitHostEvent(event);
    await engine.evaluateAll(now: alarmAt.add(const Duration(seconds: 11)));
    visible = await engine.store.loadHistory();
    expect(
        visible
            .where((r) =>
                r.ringDisposition == RingDisposition.missed && r.at == alarmAt)
            .length,
        1);
  });

  test('ambiguous B: pending with no plugin alarm → Couldn\'t confirm',
      () async {
    await armCalmAtT();
    final pending = (await engine.store.loadPendingRing(alarm.id))!;
    ring.scheduled.remove(pending.pluginId);
    await engine.evaluateAll(now: alarmAt.add(const Duration(minutes: 1)));
    final visible = await engine.store.loadHistory();
    expect(
        visible.any((r) =>
            r.at == alarmAt && r.ringDisposition == RingDisposition.unknown),
        isTrue);
    expect(await engine.store.loadPendingRing(alarm.id), isNull);
  });

  test('audible settle writes Rang with disposition', () async {
    await armCalmAtT();
    await settleAudibleRing(
      ring: ring,
      engine: engine,
      alarm: alarm,
      courts: [court],
      now: alarmAt.add(const Duration(seconds: 10)),
    );
    final visible = await engine.store.loadHistory();
    expect(
        visible.any((r) =>
            r.at == alarmAt &&
            r.outcome == CheckOutcome.rang &&
            (r.ringDisposition == null ||
                r.ringDisposition == RingDisposition.rang)),
        isTrue);
  });

  test('lateRing role decodes separately from alarmAt', () {
    expect(NivaatIds.ringRoleOf(NivaatIds.lateRing(3)), RingLockerRole.lateRing);
    expect(NivaatIds.ringRoleOf(NivaatIds.nextRing(3)), RingLockerRole.nextRing);
    expect(NivaatIds.ringRoleOf(NivaatIds.check(3)), isNull);
  });

  test('C1: drop mid hold+rollOn settles once — only one roll-on', () async {
    SharedPreferences.setMockInitialValues({});
    final store = _DropOnPendingSaveStore();
    await store.saveCourts([court]);
    await store.saveAlarms([alarm]);
    await store.saveAlarmIdSeq(8);
    ring = FakeRing();
    api = FakeApi()..sample = wind(5.0, 5.0);
    engine = NivaatEngine(
      store: store,
      scheduler: ring,
      api: api,
      checks: FakeChecks(),
      notifier: FakeNotifier(),
    );

    store.afterFirstHoldSave = (pending) async {
      ring.scheduled.remove(pending.pluginId);
      await ring.emitHostEvent(HostAlarmEvent(
        id: pending.pluginId,
        kind: HostAlarmEventKind.dropped,
        cause: HostAlarmEventCause.platformRefusal,
        recordedAt: alarmAt.add(const Duration(milliseconds: 1)),
        at: pending.scheduledFor,
      ));
    };

    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 2)));
    await engine.evaluateAlarm(alarm, [court], now: alarmAt);

    final visible = await store.loadHistory();
    expect(
        visible
            .where((r) =>
                r.ringDisposition == RingDisposition.missed && r.at == alarmAt)
            .length,
        1);
    expect(await store.loadPendingRing(alarm.id), isNull);
    expect(
      ring.log.where((e) => e.id == nextRing && e.at == tomorrow).length,
      1,
      reason: '_rollOn must run exactly once for the next occurrence',
    );
    expect(
      ring.log.where((e) => e.at == dayAfter),
      isEmpty,
      reason: 'a second roll would pre-arm the day after',
    );
  });

  test('C2: crash after Missed before clear → recover → one disposition',
      () async {
    await armCalmAtT();
    final pending = (await engine.store.loadPendingRing(alarm.id))!;
    ring.scheduled.remove(pending.pluginId);
    final key = hostAlarmEventClaimKey(
      pending.pluginId,
      alarmAt.add(const Duration(seconds: 3)),
    );
    // Simulate: history write landed, process died before clearPendingRing.
    await engine.store.upsertHistory(HistoryRecord(
      alarmId: alarm.id,
      courtId: court.id,
      at: alarmAt,
      outcome: CheckOutcome.rang,
      kind: HistoryKind.outcome,
      pushSeq: 1,
      checkedAt: alarmAt,
      courtSpeedKmh: pending.courtSpeedKmh,
      rawGustKmh: pending.rawGustKmh,
      courtSpeedLimitKmh: pending.courtSpeedLimitKmh,
      rawGustLimitKmh: pending.rawGustLimitKmh,
      volume: pending.volume,
      ringDisposition: RingDisposition.missed,
      hostEventKey: key,
    ));
    expect(await engine.store.loadPendingRing(alarm.id), isNotNull);

    await engine.evaluateAll(now: alarmAt.add(const Duration(minutes: 2)));

    final visible = await engine.store.loadHistory();
    final dispositions = visible.where((r) =>
        r.at == alarmAt &&
        (r.ringDisposition == RingDisposition.missed ||
            r.ringDisposition == RingDisposition.unknown));
    expect(dispositions.length, 1,
        reason: 'must not stack Missed + Unknown after recovery');
    expect(dispositions.single.ringDisposition, RingDisposition.missed);
    expect(await engine.store.loadPendingRing(alarm.id), isNull);
  });

  test('H2: abandon with pending not ringing clears without Policy B',
      () async {
    await armCalmAtT();
    expect(await engine.store.loadPendingRing(alarm.id), isNotNull);
    await engine.abandonOccurrence(alarm,
        now: alarmAt.add(const Duration(seconds: 20)));
    expect(await engine.store.loadPendingRing(alarm.id), isNull);
    final visible = await engine.store.loadHistory();
    expect(
      visible.where((r) =>
          r.ringDisposition == RingDisposition.unknown ||
          r.ringDisposition == RingDisposition.missed),
      isEmpty,
      reason: 'toggle-off must never use Couldn\'t confirm / Missed',
    );
  });

  test('H5: lateRing drop closes occurrence (scheduledFor ≠ alarmAt), one roll',
      () async {
    api.sample = wind(5.0, 5.0);
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 1)));
    await engine.evaluateAlarm(alarm, [court], now: alarmAt);
    final pending = (await engine.store.loadPendingRing(alarm.id))!;
    expect(pending.role, RingLockerRole.lateRing);
    expect(pending.scheduledFor, isNot(alarmAt));
    expect(pending.pluginId, lateRing);

    ring.scheduled.remove(lateRing);
    final event = HostAlarmEvent(
      id: lateRing,
      kind: HostAlarmEventKind.dropped,
      cause: HostAlarmEventCause.platformRefusal,
      recordedAt: alarmAt.add(const Duration(seconds: 12)),
      at: pending.scheduledFor,
    );
    await ring.emitHostEvent(event);

    final visible = await engine.store.loadHistory();
    expect(
        visible.where((r) =>
            r.ringDisposition == RingDisposition.missed && r.at == alarmAt),
        hasLength(1));
    expect(await engine.store.loadPendingRing(alarm.id), isNull);
    // Post-T already rolled once (rollOnDone); the drop must not roll again.
    // Counted at ANY occurrence past `alarmAt`, not just `tomorrow`: this
    // event is handled outside an evaluate lane, so a second `_rollOn` would
    // take the wall clock and land on a date the 2026-08-08 fixture cannot
    // name — pinning the count to `tomorrow` reads as a double-roll guard
    // while being unable to see one.
    expect(
      ring.log.where((e) => e.id == nextRing && e.at.isAfter(alarmAt)).length,
      1,
    );
    expect(ring.log.where((e) => e.id == nextRing && e.at == tomorrow).length, 1,
        reason: 'and the one roll is the in-lane one, at the next occurrence');
  });

  test('C1b: drop during wind fetch aborts outer evaluate', () async {
    SharedPreferences.setMockInitialValues({});
    final store = NivaatStore();
    await store.saveCourts([court]);
    await store.saveAlarms([alarm]);
    await store.saveAlarmIdSeq(8);
    ring = FakeRing();

    // First pass: pre-arm with a normal FakeApi.
    var apiLocal = FakeApi()..sample = wind(5.0, 5.0);
    engine = NivaatEngine(
      store: store,
      scheduler: ring,
      api: apiLocal,
      checks: FakeChecks(),
      notifier: FakeNotifier(),
    );
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 2)));
    final preArmId = NivaatIds.ring(alarm.id);
    expect(ring.scheduled.containsKey(preArmId), isTrue);

    // Second pass at T: gated fetch — drop while parked.
    final gated = GatedApi()..sample = wind(5.0, 5.0);
    engine = NivaatEngine(
      store: store,
      scheduler: ring,
      api: gated,
      checks: FakeChecks(),
      notifier: FakeNotifier(),
    );
    final eval = engine.evaluateAlarm(alarm, [court], now: alarmAt);
    await gated.parked.future;
    ring.scheduled.remove(preArmId);
    await ring.emitHostEvent(HostAlarmEvent(
      id: preArmId,
      kind: HostAlarmEventKind.dropped,
      cause: HostAlarmEventCause.platformRefusal,
      recordedAt: alarmAt.add(const Duration(milliseconds: 2)),
      at: alarmAt,
    ));
    gated.gate.complete();
    await eval;

    final visible = await store.loadHistory();
    expect(
        visible
            .where((r) =>
                r.ringDisposition == RingDisposition.missed && r.at == alarmAt)
            .length,
        1);
    final after = await store.loadCheckState(alarm.id);
    expect(after?.alarmAt, tomorrow,
        reason: 'roll-on CheckState must survive — outer must not clobber');
    expect(
      ring.log.where((e) => e.id == preArmId && e.at == alarmAt).length,
      1,
      reason: 'outer must not re-arm today after host closed it',
    );
    expect(await store.loadPendingRing(alarm.id), isNull);
  });

  test('H5: nextRing drop while today pending held — close tomorrow, keep today',
      () async {
    // Live-clock fixture, and not merely to avoid a stale date. The drop is
    // emitted OUTSIDE an evaluate lane, so `_nowFor` falls back to the wall
    // clock — and `_rollOn` then picks the later of that clock and just-past
    // `closed`. Dated 2026-08-08, `closed` is in the past, the wall clock
    // wins, and the test never reaches the `afterClosed` guard it is cited
    // for on `_rollOn`; worse, the answer it asserted was whatever the wall
    // clock made true that morning, so it began failing on its own at
    // 2026-08-10 06:00. Armed five minutes ahead, `closed` is genuinely in
    // the future — the branch under test — and the expected roll is fixed.
    final f = await armLiveAtT();
    final tomorrowAt = f.at.add(const Duration(days: 1));
    final dayAfterAt = f.at.add(const Duration(days: 2));

    final todayPending = (await f.store.loadPendingRing(f.alarm.id))!;
    expect(todayPending.occurrenceAt, f.at);
    final state = await f.store.loadCheckState(f.alarm.id);
    expect(state?.alarmAt, tomorrowAt);
    expect(state?.ringScheduled, isTrue);
    expect(f.ring.scheduled.containsKey(nextRing), isTrue);

    final dropNext = HostAlarmEvent(
      id: nextRing,
      kind: HostAlarmEventKind.dropped,
      cause: HostAlarmEventCause.platformRefusal,
      recordedAt: tomorrowAt.add(const Duration(seconds: 1)),
      at: tomorrowAt,
    );
    f.ring.scheduled.remove(nextRing);
    await f.ring.emitHostEvent(dropNext);

    final visible = await f.store.loadHistory();
    expect(
        visible.where((r) =>
            r.ringDisposition == RingDisposition.missed && r.at == tomorrowAt),
        hasLength(1));
    // Today's held pending must survive settling tomorrow's nextRing.
    final stillToday = await f.store.loadPendingRing(f.alarm.id);
    expect(stillToday, isNotNull);
    expect(stillToday!.occurrenceAt, f.at);
    expect(stillToday.pluginId, todayPending.pluginId);

    final after = await f.store.loadCheckState(f.alarm.id);
    expect(after?.alarmAt, dayAfterAt,
        reason: 'closing tomorrow rolls to the day after, never back to today');

    final dayAfterArms =
        f.ring.log.where((e) => e.at == after!.alarmAt).length;
    await f.ring.emitHostEvent(dropNext);
    expect(
        (await f.store.loadHistory())
            .where((r) =>
                r.ringDisposition == RingDisposition.missed &&
                r.at == tomorrowAt)
            .length,
        1);
    expect(f.ring.log.where((e) => e.at == after!.alarmAt).length, dayAfterArms);
    expect(
        (await f.store.loadPendingRing(f.alarm.id))?.occurrenceAt, f.at);
  });

  test('staleAtBoot drop settles as Missed (same as platformRefusal)', () async {
    await armCalmAtT();
    final pending = (await engine.store.loadPendingRing(alarm.id))!;
    ring.scheduled.remove(pending.pluginId);
    await ring.emitHostEvent(HostAlarmEvent(
      id: pending.pluginId,
      kind: HostAlarmEventKind.dropped,
      cause: HostAlarmEventCause.staleAtBoot,
      recordedAt: alarmAt.add(const Duration(seconds: 2)),
      at: pending.scheduledFor,
    ));
    final visible = await engine.store.loadHistory();
    expect(
        visible.where((r) =>
            r.ringDisposition == RingDisposition.missed && r.at == alarmAt),
        hasLength(1));
  });

  test('matrix 16: drop with wrong occurrence scheduledFor does not close tomorrow',
      () async {
    await armCalmAtT();
    final state = await engine.store.loadCheckState(alarm.id);
    expect(state?.alarmAt, tomorrow);
    final pluginId = NivaatIds.ring(alarm.id);
    ring.scheduled.remove(pluginId);
    await ring.emitHostEvent(HostAlarmEvent(
      id: pluginId,
      kind: HostAlarmEventKind.dropped,
      cause: HostAlarmEventCause.platformRefusal,
      recordedAt: tomorrow,
      at: alarmAt,
    ));
    final visible = await engine.store.loadHistory();
    expect(
      visible.where((r) =>
          r.at == tomorrow && r.ringDisposition == RingDisposition.missed),
      isEmpty,
      reason: 'recycled id / stale scheduledFor must not finalize wrong occurrence',
    );
  });

  test('matrix 17: replayed move after plugin booking gone is ignored', () async {
    await armCalmAtT();
    final pending = (await engine.store.loadPendingRing(alarm.id))!;
    final before = pending.scheduledFor;
    ring.scheduled.remove(pending.pluginId);
    await ring.emitHostEvent(HostAlarmEvent(
      id: pending.pluginId,
      kind: HostAlarmEventKind.moved,
      cause: HostAlarmEventCause.platformRefusal,
      recordedAt: alarmAt.add(const Duration(minutes: 1)),
      at: before.add(const Duration(seconds: 30)),
    ));
    final after = await engine.store.loadPendingRing(alarm.id);
    expect(after?.scheduledFor, before);
  });

  test('matrix 13: duplicate inject into same engine — one Missed row', () async {
    await armCalmAtT();
    final pending = (await engine.store.loadPendingRing(alarm.id))!;
    ring.scheduled.remove(pending.pluginId);
    final event = HostAlarmEvent(
      id: pending.pluginId,
      kind: HostAlarmEventKind.dropped,
      cause: HostAlarmEventCause.platformRefusal,
      recordedAt: alarmAt.add(const Duration(seconds: 4)),
      at: pending.scheduledFor,
    );
    await ring.emitHostEvent(event);
    await ring.emitHostEvent(event);
    final visible = await engine.store.loadHistory();
    expect(
        visible
            .where((r) =>
                r.ringDisposition == RingDisposition.missed && r.at == alarmAt)
            .length,
        1);
  });
  test(
      'a platform with no drop channel records an ordinary Rang, '
      'never Couldn\'t confirm', () async {
    // **The iOS shape.** AlarmKit reports nothing it does on its own, and an
    // alarm leaves it the moment it fires and is dismissed — which is exactly
    // what a good morning looks like. It also never opens the app, so Nivaat is
    // essentially never running while the alert sounds and almost never sees
    // the ring as audible. Reading "gone, and nothing said why" as a miss there
    // labelled EVERY iOS ring unconfirmed.
    SharedPreferences.setMockInitialValues({});
    final ios = NoEventRing();
    expect(ios.reportsHostEvents, isFalse);
    final store = NivaatStore();
    await store.saveCourts([court]);
    await store.saveAlarms([alarm]);
    await store.saveAlarmIdSeq(8);
    final iosEngine = NivaatEngine(
      store: store,
      scheduler: ios,
      api: FakeApi()..sample = wind(5.0, 5.0),
      checks: FakeChecks(),
      notifier: FakeNotifier(),
    );

    await iosEngine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 2)));
    await iosEngine.evaluateAlarm(alarm, [court], now: alarmAt);
    final pending = (await store.loadPendingRing(alarm.id))!;
    // The alert fired and the user dismissed it from the system UI: AlarmKit
    // forgets the alarm, and the app was never running to see it sound.
    ios.scheduled.remove(pending.pluginId);

    await iosEngine.evaluateAll(now: alarmAt.add(const Duration(hours: 1)));

    final rows =
        (await store.loadHistory()).where((r) => r.at == alarmAt).toList();
    expect(rows, isNotEmpty, reason: 'the morning must be recorded at all');
    expect(
      rows.where((r) =>
          r.ringDisposition == RingDisposition.missed ||
          r.ringDisposition == RingDisposition.unknown),
      isEmpty,
      reason: 'no drop channel means a vanished ring is not evidence of a miss',
    );
    expect(rows.where((r) => r.ringDisposition == RingDisposition.rang),
        hasLength(1));
    expect(nivaatHistoryLine(rows.first), startsWith('Rang'));
    expect(await store.loadPendingRing(alarm.id), isNull);
  });

  test('Android DOES read the same vanished ring as unconfirmed', () async {
    // The control for the test above: same story, a scheduler that reports
    // drops, opposite answer. Without this the iOS assertion would pass just as
    // well against an engine that had stopped writing dispositions at all.
    await armCalmAtT();
    final pending = (await engine.store.loadPendingRing(alarm.id))!;
    ring.scheduled.remove(pending.pluginId);

    await engine.evaluateAll(now: alarmAt.add(const Duration(hours: 1)));

    final rows = (await engine.store.loadHistory()).where((r) => r.at == alarmAt);
    expect(
      rows.where((r) => r.ringDisposition == RingDisposition.unknown),
      hasLength(1),
    );
  });

  test('a stale lateRing drop from an old occurrence is ignored', () async {
    // lateRing has no fixed time — it is armed "ten seconds from now" by
    // whichever retry found calm air — so it cannot be matched by proximity to
    // the alarm's minute. Bounded by the retry window instead: "any lateRing
    // event at or after alarmAt" is satisfied by every FUTURE morning too, so a
    // replayed drop from days ago would close today and roll the cascade on a
    // day early.
    await armCalmAtT();
    final before = await engine.store.loadPendingRing(alarm.id);
    expect(before, isNotNull);

    await ring.emitHostEvent(HostAlarmEvent(
      id: lateRing,
      kind: HostAlarmEventKind.dropped,
      cause: HostAlarmEventCause.platformRefusal,
      recordedAt: alarmAt.subtract(const Duration(days: 7)),
      // Well past the 30-minute retry window of the occurrence it names.
      at: alarmAt.subtract(const Duration(days: 7)).add(const Duration(hours: 4)),
    ));

    expect(
      (await engine.store.loadHistory()).where(
          (r) => r.ringDisposition == RingDisposition.missed),
      isEmpty,
      reason: 'an event outside the retry window belongs to no live occurrence',
    );
    expect((await engine.store.loadPendingRing(alarm.id))?.occurrenceAt,
        before!.occurrenceAt);
  });

  test('two events for different alarms in one batch cannot deadlock',
      () async {
    // `_activeAlarmId` was a single slot for a per-alarm queue: alarm B's
    // handler finishing cleared the mark for alarm A, so A's own event missed
    // the inline path and queued behind A's still-running job — handler waiting
    // on job, job waiting on handler, evaluateAll never returning.
    const other = NivaatAlarm(
      id: 8,
      hour: 7,
      minute: 0,
      courtId: 'c1',
      courtSpeedLimitKmh: 4,
    );
    await engine.store.saveAlarms([alarm, other]);
    await armCalmAtT();
    final pending = (await engine.store.loadPendingRing(alarm.id))!;
    ring.scheduled.remove(pending.pluginId);

    ring.emitHostEvent(HostAlarmEvent(
      id: NivaatIds.ring(other.id),
      kind: HostAlarmEventKind.dropped,
      cause: HostAlarmEventCause.platformRefusal,
      recordedAt: alarmAt.add(const Duration(seconds: 6)),
      at: alarmAt.add(const Duration(hours: 1)),
    )).ignore();
    ring.emitHostEvent(HostAlarmEvent(
      id: pending.pluginId,
      kind: HostAlarmEventKind.dropped,
      cause: HostAlarmEventCause.platformRefusal,
      recordedAt: alarmAt.add(const Duration(seconds: 7)),
      at: pending.scheduledFor,
    )).ignore();

    await engine
        .evaluateAll(now: alarmAt.add(const Duration(seconds: 20)))
        .timeout(const Duration(seconds: 5));

    expect(
        (await engine.store.loadHistory()).where((r) =>
            r.at == alarmAt && r.ringDisposition == RingDisposition.missed),
        hasLength(1));
  });
  test('a platform we cannot ask is never read as "the ring is gone"',
      () async {
    // "I could not ask" is not "it is not there" — REVIEW #2's rule, pointed at
    // a different call. Answering an empty map on a transient query failure
    // would finalise a morning whose alarm is still sitting in the system,
    // armed and about to sound.
    SharedPreferences.setMockInitialValues({});
    final blind = UnqueryableRing()..blind = false;
    final store = NivaatStore();
    await store.saveCourts([court]);
    await store.saveAlarms([alarm]);
    await store.saveAlarmIdSeq(8);
    final e = NivaatEngine(
      store: store,
      scheduler: blind,
      api: FakeApi()..sample = wind(5.0, 5.0),
      checks: FakeChecks(),
      notifier: FakeNotifier(),
    );
    await e.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 2)));
    await e.evaluateAlarm(alarm, [court], now: alarmAt);
    expect(await store.loadPendingRing(alarm.id), isNotNull);

    // The ring is still armed; the platform simply cannot be reached.
    blind.blind = true;
    await expectLater(
      e.evaluateAll(now: alarmAt.add(const Duration(minutes: 1))),
      throwsException,
      reason: 'the pass soft-fails upstream and retries, rather than guessing',
    );

    expect(
      (await store.loadHistory())
          .where((r) => r.at == alarmAt && r.ringDisposition != null),
      isEmpty,
      reason: 'a failed query must not settle the morning',
    );
    expect(await store.loadPendingRing(alarm.id), isNotNull,
        reason: 'the ring is still owed — nothing has been learned about it');
  });

  test('a crash between the Rang row and the clear adds no second row',
      () async {
    // Recovery re-runs whatever a dead pass left. It must recognise that this
    // occurrence already has a verdict, or it writes a second one beside the
    // first: `Couldn't confirm` under a real `Rang`.
    await armCalmAtT();
    await settleAudibleRing(
      ring: ring,
      engine: engine,
      alarm: alarm,
      courts: [court],
      now: alarmAt.add(const Duration(seconds: 10)),
    );
    final settled = (await engine.store.loadHistory())
        .where((r) => r.at == alarmAt && r.ringDisposition != null)
        .toList();
    expect(settled, hasLength(1));
    expect(settled.single.ringDisposition, RingDisposition.rang);

    // Put the pending slot back, as a death between the row and the clear
    // would have left it, and make the plugin agree the ring is long gone.
    await engine.store.savePendingRing(PendingRing(
      alarmId: alarm.id,
      pluginId: NivaatIds.ring(alarm.id),
      role: RingLockerRole.ring,
      occurrenceAt: alarmAt,
      scheduledFor: alarmAt,
      courtId: court.id,
    ));
    ring.ringingIds.clear();
    for (final id in NivaatIds.allRings(alarm.id)) {
      ring.scheduled.remove(id);
    }

    await engine.evaluateAll(now: alarmAt.add(const Duration(minutes: 5)));

    expect(
      (await engine.store.loadHistory())
          .where((r) => r.at == alarmAt && r.ringDisposition != null),
      hasLength(1),
      reason: 'the morning already had its verdict',
    );
    expect(await engine.store.loadPendingRing(alarm.id), isNull,
        reason: 'and the leftover slot is cleaned up either way');
  });
  test('iOS: a refused re-arm leaves the old ring live — the skip must kill it',
      () async {
    // AlarmKit schedules before it cancels, so a refused create leaves the
    // SUPERSEDED alarm armed (REVIEW #5, deliberate — better a duplicate than
    // a silent morning). The engine records `ringScheduled: false` and stops
    // tracking it, so the only thing standing between that alarm and a windy
    // morning is the skip path's own cancel. This is the invariant Nivaat
    // exists for, and until the fake stopped modelling iOS as destructive it
    // was not tested at all.
    SharedPreferences.setMockInitialValues({});
    final ios = NoEventRing();
    expect(ios.destructiveOnFailure, isFalse);
    final store = NivaatStore();
    await store.saveCourts([court]);
    await store.saveAlarms([alarm]);
    await store.saveAlarmIdSeq(8);
    final windy = FakeApi();
    final e = NivaatEngine(
      store: store,
      scheduler: ios,
      api: windy,
      checks: FakeChecks(),
      notifier: FakeNotifier(),
    );

    // Calm the night before: a ring goes on the platform.
    windy.sample = wind(5.0, 5.0);
    await e.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(hours: 2)));
    final preArm = NivaatIds.ring(alarm.id);
    expect(ios.scheduled.containsKey(preArm), isTrue);

    // A later rung re-decides and AlarmKit refuses the replacement.
    ios.accepts = false;
    await e.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 30)));
    expect(ios.scheduled.containsKey(preArm), isTrue,
        reason: 'iOS keeps the old alarm when a create fails');

    // The wind turns. The morning is skipped — and the ring the engine is no
    // longer tracking must still be taken off the platform.
    ios.accepts = true;
    windy.sample = wind(30.0, 40.0);
    await e.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 10)));

    expect(ios.scheduled.containsKey(preArm), isFalse,
        reason: 'a windy morning must leave nothing armed to sound');
    expect(ios.cancelled, contains(preArm));
  });
  test('a known drop upgrades an earlier Couldn\'t confirm to Missed',
      () async {
    // `Couldn't confirm` does not mean "nothing happened" — it means we never
    // found out. A drop arriving afterwards IS finding out, so refusing it
    // leaves the log permanently vaguer than the evidence.
    //
    // The reachable shape is a crash: the vague verdict reached the log, the
    // pending slot was not cleared, and the drop turns up on the next pass.
    // (Once the slot IS cleared the occurrence is closed and a later drop has
    // nothing to attach to — see the residual note in CLAUDE.md.)
    await armCalmAtT();
    final pending = (await engine.store.loadPendingRing(alarm.id))!;
    ring.scheduled.remove(pending.pluginId);

    await engine.store.upsertHistory(HistoryRecord(
      alarmId: alarm.id,
      courtId: court.id,
      at: alarmAt,
      outcome: CheckOutcome.rang,
      pushSeq: 1,
      checkedAt: alarmAt,
      ringDisposition: RingDisposition.unknown,
    ));

    await ring.emitHostEvent(HostAlarmEvent(
      id: pending.pluginId,
      kind: HostAlarmEventKind.dropped,
      cause: HostAlarmEventCause.platformRefusal,
      recordedAt: alarmAt.add(const Duration(seconds: 30)),
      at: pending.scheduledFor,
    ));

    final rows = (await engine.store.loadHistory())
        .where((r) => r.at == alarmAt && r.ringDisposition != null);
    expect(rows, hasLength(1), reason: 'upgraded in place, not appended');
    expect(rows.single.ringDisposition, RingDisposition.missed);
  });

  test('a late drop never rewrites a morning that audibly rang', () async {
    // The other direction, and the one that would be a real betrayal: the user
    // woke up to it. A drop event arriving after a settled `rang` — a stale
    // replay, or a refusal recorded for a locker we have since reused — must
    // leave that row exactly as it is.
    await armCalmAtT();
    final pending = (await engine.store.loadPendingRing(alarm.id))!;
    await settleAudibleRing(
      ring: ring,
      engine: engine,
      alarm: alarm,
      courts: [court],
      now: alarmAt.add(const Duration(seconds: 10)),
    );
    expect(
        (await engine.store.loadHistory())
            .where((r) => r.at == alarmAt && r.ringDisposition != null)
            .single
            .ringDisposition,
        RingDisposition.rang);

    ring.scheduled.remove(pending.pluginId);
    await ring.emitHostEvent(HostAlarmEvent(
      id: pending.pluginId,
      kind: HostAlarmEventKind.dropped,
      cause: HostAlarmEventCause.platformRefusal,
      recordedAt: alarmAt.add(const Duration(minutes: 3)),
      at: pending.scheduledFor,
    ));

    final rows = (await engine.store.loadHistory())
        .where((r) => r.at == alarmAt && r.ringDisposition != null);
    expect(rows, hasLength(1));
    expect(rows.single.ringDisposition, RingDisposition.rang,
        reason: 'a morning the user woke up to is not rewritten as missed');
  });
  test('a drop landing before its pending is saved is retried, not lost',
      () async {
    // The one window left between arming a ring and recording it: a single
    // microtask as `scheduleRing`'s future completes. A refused foreground
    // service lands in exactly those seconds (upstream #424), so it is the
    // likeliest moment for this drop. The handler must ask for the event back
    // rather than mark it handled with nothing to attach it to.
    await armCalmAtT();
    final pending = (await engine.store.loadPendingRing(alarm.id))!;
    ring.scheduled.remove(pending.pluginId);

    // Deliver it while nothing can match: no pending, no check state.
    await engine.store.clearPendingRing(alarm.id);
    await engine.store.clearCheckState(alarm.id);
    final drop = HostAlarmEvent(
      id: pending.pluginId,
      kind: HostAlarmEventKind.dropped,
      cause: HostAlarmEventCause.platformRefusal,
      recordedAt: alarmAt.add(const Duration(seconds: 2)),
      at: pending.scheduledFor,
    );
    await ring.emitHostEvent(drop);

    expect(
      (await engine.store.loadHistory())
          .where((r) => r.ringDisposition == RingDisposition.missed),
      isEmpty,
      reason: 'nothing to write it against yet',
    );
    // Not marked handled — the bridge is holding it for the next barrier.
    expect(await ring.hostEventClaims.isClaimed(drop), isFalse);

    // The pending reappears (the arming pass got there), and the next barrier
    // finds it.
    await engine.store.savePendingRing(pending);
    await ring.applyHostAlarmEvents();

    expect(
      (await engine.store.loadHistory()).where((r) =>
          r.at == alarmAt && r.ringDisposition == RingDisposition.missed),
      hasLength(1),
      reason: 'the retry found the pending and recorded the miss',
    );
    expect(await ring.hostEventClaims.isClaimed(drop), isTrue);
  });
  test('a move injected DURING scheduleRing survives to update scheduledFor',
      () async {
    // The real window, reproduced rather than modelled: the event is emitted
    // AND drained from inside `scheduleRing`, so the handler provably runs
    // while the pass is still between accepting the ring and recording that it
    // owes one. (Merely queueing it raced — the pending was usually saved
    // first, and the test then passed with or without the fix.)
    //
    // Dated on the LIVE clock, not the file's fixture: a move about a ring
    // whose time has passed is a stale replay and is correctly ignored, and
    // `_nowFor` falls back to the wall clock for an event arriving outside an
    // evaluate lane — so a 2026-08-08 fixture would test the rejection path.
    // Seconds are stripped so the occurrence lands exactly on the minute the
    // engine computes; with seconds, `nextOccurrence` rolls to tomorrow and
    // the pass is a pre-arm, which owes nothing and writes no pending.
    SharedPreferences.setMockInitialValues({});
    final base = DateTime.now();
    final soon = DateTime(base.year, base.month, base.day, base.hour)
        .add(Duration(minutes: base.minute + 5));
    final liveAlarm = NivaatAlarm(
      id: 7,
      hour: soon.hour,
      minute: soon.minute,
      courtId: 'c1',
      courtSpeedLimitKmh: 4,
    );
    final store = NivaatStore();
    await store.saveCourts([court]);
    await store.saveAlarms([liveAlarm]);
    await store.saveAlarmIdSeq(8);
    final sched = _EmitsDuringSchedule();
    final e = NivaatEngine(
      store: store,
      scheduler: sched,
      api: FakeApi()..sample = wind(5.0, 5.0),
      checks: FakeChecks(),
      notifier: FakeNotifier(),
    );

    // Pre-arm first, so the pass AT T resolves the in-flight occurrence rather
    // than rolling forward a day — that is the pass which owes a ring and so
    // writes a pending.
    await e.evaluateAlarm(liveAlarm, [court],
        now: soon.subtract(const Duration(minutes: 2)));

    late DateTime deferred;
    sched.emitOnSchedule = (id, at) {
      // The host defers the ring it has just accepted (upstream #424).
      deferred = at.add(const Duration(seconds: 30));
      sched.scheduled[id] = (at: deferred, volume: null, title: '', body: '');
      return HostAlarmEvent(
        id: id,
        kind: HostAlarmEventKind.moved,
        cause: HostAlarmEventCause.platformRefusal,
        recordedAt: soon,
        at: deferred,
      );
    };

    await e.evaluateAlarm(liveAlarm, [court], now: soon);
    await sched.applyHostAlarmEvents();

    final pending = await store.loadPendingRing(liveAlarm.id);
    expect(pending, isNotNull);
    expect(pending!.scheduledFor, deferred,
        reason: 'a move claimed with no pending leaves scheduledFor stale, and '
            'every later comparison keys on it');
  });
  test('a move for another occurrence never takes the held pending slot',
      () async {
    // One slot per alarm. `_matchPendingForHostEvent` will synthesize a
    // pending for a different morning, and `savePendingRing` keys on alarmId
    // alone — so a deferral of tomorrow's `nextRing` used to write straight
    // over today's held ring and erase the only record it was still owed.
    final f = await armLiveAtT();
    final today = (await f.store.loadPendingRing(f.alarm.id))!;
    expect(today.occurrenceAt, f.at);

    final nextAt = f.at.add(const Duration(days: 1));
    final deferred = nextAt.add(const Duration(seconds: 30));
    f.ring.scheduled[nextRing] =
        (at: deferred, volume: null, title: '', body: '');
    await f.ring.emitHostEvent(HostAlarmEvent(
      id: nextRing,
      kind: HostAlarmEventKind.moved,
      cause: HostAlarmEventCause.platformRefusal,
      recordedAt: f.at.add(const Duration(seconds: 5)),
      at: deferred,
    ));

    final after = await f.store.loadPendingRing(f.alarm.id);
    expect(after, isNotNull, reason: 'today must still be held');
    expect(after!.occurrenceAt, f.at);
    expect(after.pluginId, today.pluginId);
    expect(after.scheduledFor, today.scheduledFor);
  });

  test('a replayed older move never rolls a newer one back', () async {
    // A deferral only ever moves a ring forward, so an event naming an earlier
    // time than the one we hold is a replay of a move already superseded.
    final f = await armLiveAtT();
    final pending = (await f.store.loadPendingRing(f.alarm.id))!;
    final newer = pending.scheduledFor.add(const Duration(seconds: 60));
    await f.store.savePendingRing(pending.copyWith(scheduledFor: newer));
    f.ring.scheduled[pending.pluginId] =
        (at: newer, volume: null, title: '', body: '');

    await f.ring.emitHostEvent(HostAlarmEvent(
      id: pending.pluginId,
      kind: HostAlarmEventKind.moved,
      cause: HostAlarmEventCause.platformRefusal,
      recordedAt: f.at.add(const Duration(seconds: 2)),
      at: pending.scheduledFor.add(const Duration(seconds: 30)),
    ));

    expect((await f.store.loadPendingRing(f.alarm.id))!.scheduledFor, newer,
        reason: 'the older replay must not win');
  });
}
