import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/controller.dart';
import 'package:nivaat/src/engine.dart';
import 'package:nivaat/src/ids.dart';
import 'package:nivaat/src/skip_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine_fakes.dart';

/// Records every push to the occurrence's single card, in order, plus the body
/// each one rendered — the body is where every wording decision lands, so a
/// test that only counts pushes would miss all of them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRing ring;
  late FakeChecks checks;
  late FakeApi api;
  late FakeNotifier notifier;
  late NivaatEngine engine;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ring = FakeRing();
    checks = FakeChecks();
    api = FakeApi();
    notifier = FakeNotifier();
    final store = NivaatStore();
    // Seed the store, the way `occurrence_story_test` already does. The engine
    // re-reads it before it arms anything (`_stillLive`), because an alarm
    // that has left the store mid-pass must not be scheduled — so an alarm
    // that was NEVER in it is a fixture production cannot produce, and tests
    // built on one were quietly asserting against an impossible state.
    await store.saveCourts([court]);
    await store.saveAlarms([alarm]);
    engine = NivaatEngine(
      store: store,
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
    // a bare "18:00" would read as the alarm's own day.
    expect(ring.scheduled[todayRing]!.body,
        'wind 3 (≤4) · gusts 5 (≤15) km/h · checked 11 Jul 18:00');
    // **The window asked for is when you PLAY, never the alarm instant.**
    // Defaults are 30 minutes to get on court and 30 of play, so a 06:00 alarm
    // is decided on 06:30-07:00 — and this pass runs at T-12h, which used to
    // be exactly when the old code read the wrong slot.
    expect(api.asked.last,
        (alarmAt.add(const Duration(minutes: 30)),
            alarmAt.add(const Duration(minutes: 60))));
    // Rungs are booked ALL AT ONCE now, so `booked` holds the soonest still
    // ahead: T-24h and T-12h are gone at 18:00 the evening before, leaving
    // T-6h at midnight.
    expect(checks.booked[7], DateTime(2026, 7, 12, 0, 0));
    expect(checks.bookedRungs[7]!.length, greaterThan(1),
        reason: 'the whole remaining ladder is booked, not just the next rung');
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
    // One code path now — near and far read the same play window. The old
    // `currentWind` switch read "now" instead of the alarm's own slot, which
    // at T-2m meant deciding a 06:00 alarm on the 05:45 wind.
    // ...then the T-0 check runs.
    await engine.evaluateAlarm(alarm, [court], now: alarmAt);
    // Post-T schedule holds pending — settle when audible.
    await settleAudibleRing(
      ring: ring,
      engine: engine,
      alarm: alarm,
      courts: [court],
      now: alarmAt.add(const Duration(seconds: 10)),
    );

    final history = await engine.store.loadHistory();
    expect(history, hasLength(1));
    expect(history.first.outcome, CheckOutcome.rang);
    expect(history.first.ringDisposition, RingDisposition.rang);
    expect(history.first.volume, 0.85);
    // **A rang row RECORDS its slot too** (2026-08-25). Skipped rows carried
    // one from the day the window rule landed; ring rows did not, so the log
    // explained a windy occurrence and shrugged at a calm one. The slot is the
    // windiest minute of the play window, so it is on the grid and inside
    // that window — never the alarm time, which is what a reader would
    // otherwise assume the numbers were taken at.
    //
    // Recorded, not printed: since 2026-08-31 a ring's line stops at the
    // numbers (`nivaatHistoryNumbers`), because a ring is the whole window
    // clearing and no minute in it is the decisive one. The field stays — it
    // is where those numbers came from, and every reader of it degrades on
    // null rather than assuming.
    final slot = history.first.slotAt;
    final (playFrom, playTo) = alarm.playWindow(alarmAt);
    expect(slot, isNotNull, reason: 'the whole point of ringSlotAt');
    expect(slot!.isBefore(playFrom), isFalse);
    expect(slot.isAfter(playTo), isFalse);
    expect(slot.minute % 15, 0, reason: "Open-Meteo's grid");
    // Finalising doesn't stop at the closed occurrence: the same pass
    // evaluates tomorrow — pre-arms it (still calm) and books its ladder —
    // so the cascade never sleeps until the next manual app open.
    final rolled = await engine.store.loadCheckState(7);
    expect(rolled!.alarmAt, alarmAt.add(const Duration(days: 1)),
        reason: "today closed; tomorrow's occurrence is already in flight");
    expect(ring.scheduled[nextRing]!.at, alarmAt.add(const Duration(days: 1)),
        reason: 'tomorrow pre-armed while the forecast is calm');
    expect(ring.scheduled.containsKey(todayRing), isFalse,
        reason: "a roll-on never writes the closing occurrence's own locker");
    // The regression guard for the locker collision: the T-0 ring was
    // committed moments earlier in this same pass, into the LATE locker, and
    // the pre-arm above must NOT have evicted it. Under one locker per alarm
    // this entry was gone.
    expect(ring.scheduled[lateRing]!.at,
        alarmAt.add(const Duration(seconds: 10)),
        reason: "the T-0 ring survives the roll-on pre-arm");
    expect(checks.booked[7], alarmAt.add(const Duration(hours: 12)),
        reason: "tomorrow's soonest remaining rung (T-12h) booked — T-24h for "
            'tomorrow is this very instant, so it is already behind us');
  });

  test('a DEAD FETCH at T-0 leaves the armed ring alone', () async {
    // The other half of the T-0 rule, and it had no test until 2026-08-30
    // (Cursor Grok 4.6): T-0 re-decides an armed ring and cancels it if the
    // play window has turned windy — but only WHEN THE FETCH RETURNS. Both the
    // arm and the skip-cancel sit under `if (decision != null)`, so a network
    // blip at exactly T cannot cost a ring the ladder already decided.
    //
    // Without this, `turns windy at T-0` alone would let a change that
    // cancelled on ANY T-0 outcome keep passing, which is the failure mode the
    // rule exists to prevent — a dead network is the commonest thing that can
    // happen at 6am and the worst possible reason to be left unwoken.
    api.sample = wind(5.0, 5.0); // calm at T-30m -> ring pre-armed
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 30)));
    expect(ring.scheduled, isNotEmpty, reason: 'pre-armed, or this proves nothing');
    final armed = ring.scheduled[todayRing]!.at;

    api.fail = true; // the fetch dies at T
    await engine.evaluateAlarm(alarm, [court], now: alarmAt);

    expect(ring.scheduled[todayRing]?.at, armed,
        reason: 'the ring the ladder decided still stands, at its own time');
    // And the pass is NOT a no-op — it says so, and books the next retry, so
    // the still-checking card can sit beside a pre-arm that then sounds.
    expect(notifier.extended, hasLength(1),
        reason: 'the occurrence is on the record as still checking');
    expect(checks.booked[7], alarmAt.add(const Duration(minutes: 15)),
        reason: 'the retry after T is booked either way');
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
    expect(checks.booked[7], alarmAt.add(const Duration(minutes: 15)),
        reason: 'first retry booked, on the 15-minute wind grid');
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
    // Seeded into the store, not just handed to the engine: `_stillLive`
    // compares the pass's snapshot against what is saved, so an alarm the
    // store has never heard of is a fixture production cannot produce.
    await engine.store.saveAlarms([short]);
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
    // Seeded into the store, not just handed to the engine: `_stillLive`
    // compares the pass's snapshot against what is saved, so an alarm the
    // store has never heard of is a fixture production cannot produce.
    await engine.store.saveAlarms([long]);
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

  test('windy at T, calm in the retry window -> rings late, card gives way',
      () async {
    api.sample = wind(9.0, 10.0); // windy — the occurrence's card posts at T
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 1)));
    await engine.evaluateAlarm(alarm, [court], now: alarmAt);
    expect(notifier.extended, hasLength(1), reason: '"still checking" at T');
    expect((await engine.store.loadHistory()).single.outcome,
        CheckOutcome.skippedWindy,
        reason: 'provisional row from the missed T');

    // Wind drops 7 min after T -> ring late.
    api.sample = wind(5.0, 5.0); // court 3.0 -> ring
    final late = alarmAt.add(const Duration(minutes: 7));
    await engine.evaluateAlarm(alarm, [court], now: late);
    await settleAudibleRing(
      ring: ring,
      engine: engine,
      alarm: alarm,
      courts: [court],
      now: late.add(const Duration(seconds: 10)),
    );

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
    expect(ring.scheduled[nextRing]!.at,
        alarmAt.add(const Duration(days: 1)),
        reason: 'tomorrow pre-arms into its own locker, evicting nothing');
    // Append-only log (2026-07-20): the late ring is a NEW row; the
    // still-checking row stays below it — both moments really happened.
    final history = await engine.store.loadHistory();
    expect(history, hasLength(2));
    expect(history.first.outcome, CheckOutcome.rang);
    expect(history.first.watchedUntil, isNull, reason: 'final rows carry no watch mark');
    expect(history.first.whenChecked, late,
        reason: 'records the check that drove the ring (06:07), not the anchor');
    expect(history.first.at, alarmAt, reason: 'anchor stays the alarm time');
    expect(history.last.outcome, CheckOutcome.skippedWindy,
        reason: 'the at-T row survives the late ring');
    expect(history.last.watchedUntil, isNotNull);
    expect(notifier.shown, isEmpty, reason: 'a ring needs no skip card');
    expect(notifier.extended, hasLength(1),
        reason: 'still the only card push this occurrence made');
    // The ROW stays, the CARD does not: the ring is this occurrence's
    // notification now, and a "still checking" card beside a sounding alarm
    // is noise. (`extended` counts pushes that happened, not what is showing.)
    expect(notifier.cancelled, contains(alarm.id),
        reason: 'the late ring takes the card down');
    expect(notifier.card, isNull);
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
    // Seeded into the store, not just handed to the engine: `_stillLive`
    // compares the pass's snapshot against what is saved, so an alarm the
    // store has never heard of is a fixture production cannot produce.
    await engine.store.saveAlarms([short]);
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
    await settleAudibleRing(
      ring: ring,
      engine: engine,
      alarm: alarm,
      courts: [court],
      now: lateNow.add(const Duration(seconds: 10)),
    );

    // The LATE locker is where a post-T ring lands, and it is what this test
    // is about. (It used to read `todayRing`, which passed for the wrong
    // reason: that locker held TOMORROW's roll-on pre-arm, also "after now".)
    expect(ring.scheduled[lateRing]!.at, lateNow.add(const Duration(seconds: 10)),
        reason: 'rings ten seconds out, never in the past');
    final history = await engine.store.loadHistory();
    expect(history.first.outcome, CheckOutcome.rang);
    expect(notifier.shown, isEmpty, reason: 'a ring needs no card');
  });

  group('scheduling that fails must not read as success (#2, #22)', () {
    test('a refused ring is never recorded as armed, and never as "Rang"',
        () async {
      // The whole of #2. `scheduleRing` used to swallow its failure and return
      // as though it had worked, so the engine set `ringScheduled: true` for
      // an alarm that did not exist — and the next pass read "committed, and
      // its time has passed" as proof it had sounded. You were never woken,
      // and the log said you were.
      ring.accepts = false;
      api.sample = wind(5.0, 5.0); // calm — the wind says ring

      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(hours: 1)));

      expect(ring.scheduled, isEmpty, reason: 'nothing was armed');
      expect((await engine.store.loadCheckState(7))!.ringScheduled, isFalse,
          reason: 'and nothing may claim it was');

      // Now the pass that used to invent the "Rang" row.
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.add(const Duration(seconds: 2)));
      final history = await engine.store.loadHistory();
      expect(history.where((h) => h.outcome == CheckOutcome.rang), isEmpty,
          reason: 'a ring that was never armed cannot have rung');
    });

    test('the cascade keeps trying, and arms as soon as scheduling recovers',
        () async {
      // Leaving the occurrence undecided is the point: a refusal costs this
      // rung, not the occurrence. The ladder has seven more.
      ring.accepts = false;
      api.sample = wind(5.0, 5.0);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(hours: 1)));
      expect(checks.booked[7], isNotNull, reason: 'the ladder carries on');

      ring.accepts = true;
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(minutes: 30)));

      expect(ring.scheduled[todayRing]!.at, alarmAt);
      expect((await engine.store.loadCheckState(7))!.ringScheduled, isTrue);
    });

    test('at T, a refused ring falls through to the watching card', () async {
      // Not silence: the occurrence still gets its one card and its history
      // row, because from the user's side "we could not ring" is a skip like
      // any other and the retry window is still theirs.
      ring.accepts = false;
      api.sample = wind(5.0, 5.0);
      // A rung before T, so the occurrence is in flight when T arrives —
      // without one `nextOccurrence(T)` resolves to TOMORROW and the pass is
      // just a pre-arm, which is a different scenario.
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(minutes: 1)));

      await engine.evaluateAlarm(alarm, [court], now: alarmAt);

      expect(notifier.extended, hasLength(1),
          reason: 'the occurrence is explained rather than dropped');
      expect(ring.scheduled, isEmpty);
    });

    test('a failed LATE arm drops the claim the pre-arm left behind', () async {
      // The half the first fix missed. `armedWith` covers "never armed"; this
      // is "was armed, and the failing pass destroyed it on the way past" —
      // the late branch cancels the pre-arm outright before trying the late
      // locker. Carrying the earlier rung's `ringScheduled: true` forward is
      // REVIEW #2 all over again, and this is the COMMON path: calm at T.
      api.sample = wind(5.0, 5.0);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(hours: 1)));
      expect(ring.scheduled[todayRing]!.at, alarmAt);
      expect((await engine.store.loadCheckState(7))!.ringScheduled, isTrue);

      ring.accepts = false;
      await engine.evaluateAlarm(alarm, [court], now: alarmAt);

      expect(ring.scheduled, isEmpty,
          reason: 'the pre-arm was cancelled and nothing replaced it');
      expect((await engine.store.loadCheckState(7))!.ringScheduled, isFalse,
          reason: 'nothing is armed, so nothing may claim to be');

      // The pass that used to invent the row. No wind reading, so nothing new
      // can be armed and only the stored claim decides.
      api.fail = true;
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.add(const Duration(minutes: 2)));
      expect(
          (await engine.store.loadHistory())
              .where((h) => h.outcome == CheckOutcome.rang),
          isEmpty,
          reason: 'no ring ever sounded, so no row may say it did');
    });

    test('a failed same-id RE-arm mid-ladder drops the claim too', () async {
      // The other way in, and the reason `FakeRing` destroys on refusal: a
      // real `Alarm.set` stops the same id BEFORE it schedules, so a rung that
      // fails has already taken the previous rung's ring with it.
      api.sample = wind(5.0, 5.0);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(hours: 1)));
      expect((await engine.store.loadCheckState(7))!.ringScheduled, isTrue);

      ring.accepts = false;
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(minutes: 30)));

      expect(ring.scheduled.containsKey(todayRing), isFalse,
          reason: 'the re-arm destroyed the old one on its way to failing');
      expect((await engine.store.loadCheckState(7))!.ringScheduled, isFalse);

      api.fail = true;
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.add(const Duration(minutes: 2)));
      expect(
          (await engine.store.loadHistory())
              .where((h) => h.outcome == CheckOutcome.rang),
          isEmpty);
    });

    test('a refused check booking does not pass for a booked cascade (#22)',
        () async {
      // On Android nothing else re-books an alarm — checks only reschedule
      // themselves — so a swallowed booking failure ends the occurrence: no
      // check at T, no retries, no card. The engine may not carry on as though
      // a wakeup exists.
      checks.accepts = false;
      api.sample = wind(5.0, 5.0);

      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(hours: 1)));

      expect(checks.booked, isEmpty, reason: 'nothing is booked');
      // The ring the ladder already committed still stands: losing the next
      // check costs the refinement, not the alarm.
      expect(ring.scheduled[todayRing]!.at, alarmAt);
    });

    test('a failed booking never aborts the other alarms', () async {
      // The old `on Exception` swallow existed for this, and it is worth
      // keeping: one alarm's refused booking must not cost its neighbours
      // their evaluation.
      const other = NivaatAlarm(
          id: 8, hour: 7, minute: 0, courtId: 'c1', courtSpeedLimitKmh: 4);
      await engine.store.saveAlarms([alarm, other]);
      checks.accepts = false;
      api.sample = wind(5.0, 5.0);

      await expectLater(
          engine.evaluateAll(now: alarmAt.subtract(const Duration(hours: 2))),
          completes);
      expect(ring.scheduled.keys,
          containsAll(<int>[todayRing, NivaatIds.ring(other.id)]));
    });
  });

  group('stale snapshots: a deleted alarm must never stay armed (#23)', () {
    // `evaluateAll` reads the alarm list ONCE and then spends seconds per
    // alarm on a wind fetch — with the home screen already up, because `init`
    // renders before it awaits `resync`. So a delete really does land while
    // the loop is holding a stale, still-enabled copy of that alarm. Arming it
    // then is unrecoverable from inside the cascade: `evaluateAll` only ever
    // visits alarms that are in the store, so nothing looks at that id again
    // and the ring fires on schedule for good.
    const other = NivaatAlarm(
        id: 8, hour: 7, minute: 0, courtId: 'c1', courtSpeedLimitKmh: 4);
    final beforeBoth = alarmAt.subtract(const Duration(hours: 2));

    /// Starts a full pass parked on the first alarm's fetch, so the caller can
    /// change the store in that window. Returns the pass to await.
    Future<(NivaatEngine, GatedApi, Future<void>)> passParkedOnFirst() async {
      await engine.store.saveAlarms([alarm, other]);
      final gated = GatedApi()..sample = wind(5.0, 5.0); // calm: would arm
      final raced = NivaatEngine(
        store: engine.store,
        scheduler: ring,
        api: gated,
        checks: checks,
        notifier: notifier,
      );
      final pass = raced.evaluateAll(now: beforeBoth);
      await gated.parked.future;
      return (raced, gated, pass);
    }

    test('deleting an alarm mid-pass never arms it', () async {
      final (_, gated, pass) = await passParkedOnFirst();

      await engine.store.saveAlarms([alarm]); // the user taps Delete
      gated.gate.complete();
      await pass;

      expect(ring.scheduled.containsKey(NivaatIds.ring(other.id)), isFalse,
          reason: 'a deleted alarm must not come back armed — permanently');
      expect(ring.scheduled[todayRing]!.at, alarmAt,
          reason: 'the alarm that survived is still armed as normal');
    });

    test('removing its court mid-pass never arms it', () async {
      // The second door on the same hole. `removeCourt` drops the court and
      // its alarms together, and the pass is holding a stale COURT list too —
      // so `_evaluate`'s court-gone branch sees the court present and lets the
      // alarm straight through.
      final (_, gated, pass) = await passParkedOnFirst();

      await engine.store.saveCourts(const []);
      gated.gate.complete();
      await pass;

      expect(ring.scheduled.containsKey(NivaatIds.ring(other.id)), isFalse);
      expect(ring.scheduled.containsKey(todayRing), isFalse,
          reason: 'no court, no ring — for either alarm');
    });

    test('a pass holding a deleted alarm re-reads before it arms', () async {
      // The cross-isolate delete. This used to need a fake that modelled the
      // per-isolate SharedPreferences cache, because both sides shared one map
      // and the delete was visible whether or not anything refreshed — so the
      // test could only be written by simulating the cache. A store read is a
      // read of the database now, so the stale half is just the argument: the
      // caller hands over the alarm it last saw, and the store no longer has it.
      await engine.store.saveAlarms([alarm]); // the UI isolate deleted `other`
      api.sample = wind(5.0, 5.0); // calm — it would arm if it got that far

      await engine.evaluateAlarm(other, [court], now: beforeBoth);

      expect(ring.scheduled.containsKey(NivaatIds.ring(other.id)), isFalse,
          reason: 'an alarm deleted in another isolate must not be armed here');
    });

    test('an already-armed orphan is swept on the next pass', () async {
      // The recovery half, and the only thing that reaches a ring armed by a
      // build without the guard, or by a background isolate racing this one.
      await ring.scheduleRing(
          id: NivaatIds.ring(other.id),
          at: alarmAt,
          title: 't',
          body: 'b',
          volume: 1);
      api.sample = wind(5.0, 5.0);

      await engine.evaluateAll(now: beforeBoth);

      expect(ring.scheduled.containsKey(NivaatIds.ring(other.id)), isFalse,
          reason: 'alarm 8 is not in the store, so its ring is an orphan');
      expect(ring.scheduled[todayRing]!.at, alarmAt,
          reason: "a live alarm's own ring is never swept");
    });

    test('a cancel that throws does not take the whole pass down', () async {
      // The sweep runs BEFORE the loop, so an exception escaping it aborts
      // `evaluateAll` with no alarm evaluated at all — the safety net taking
      // down the thing it protects. Only `scheduledIds()` was inside the try;
      // the cancels were not.
      final stubborn = UncancellableRing({NivaatIds.ring(other.id)});
      await stubborn.scheduleRing(
          id: NivaatIds.ring(other.id),
          at: alarmAt,
          title: 't',
          body: 'b',
          volume: 1);
      final engine2 = NivaatEngine(
        store: engine.store,
        scheduler: stubborn,
        api: api,
        checks: checks,
        notifier: notifier,
      );
      api.sample = wind(5.0, 5.0);

      await expectLater(engine2.evaluateAll(now: beforeBoth), completes);

      expect(stubborn.scheduled[todayRing]!.at, alarmAt,
          reason: 'the live alarm was still evaluated and armed');
    });

    test('the sweep survives a scheduler that cannot list ids', () async {
      // The net must never become the thing that stops the cascade.
      final blind = NivaatEngine(
        store: engine.store,
        scheduler: BlindRing(),
        api: api,
        checks: checks,
        notifier: notifier,
      );
      api.sample = wind(5.0, 5.0);
      await expectLater(blind.evaluateAll(now: beforeBoth), completes);
    });
  });

  group('NivaatController', () {
    late NivaatController controller;
    setUp(() async {
      // These build a user's data up from nothing, so they want the empty
      // store the app ships with — not the seeded alarm the engine tests need.
      await engine.store.saveAlarms(const []);
      await engine.store.saveCourts(const []);
      controller = NivaatController(engine: engine);
    });

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

    test('a deleted alarm never hands its number to the next one', () async {
      // REVIEW #9. Ids used to be "highest existing + 1", so deleting your
      // newest alarm gave its number straight back. Every id in this app is
      // `block + alarmId`, so the new alarm inherited the old one's ring, late
      // ring, wind check, card and cascade state — leftover work landing on an
      // alarm that never asked for it.
      await engine.store.saveCourts([court]);
      await controller.init();
      await controller.upsertAlarm(
          const NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1'));
      await controller.upsertAlarm(
          const NivaatAlarm(id: 2, hour: 6, minute: 30, courtId: 'c1'));
      expect(controller.nextAlarmId(), 3);

      await controller.deleteAlarm(2);
      await controller.lastEvaluation;
      expect(controller.nextAlarmId(), 3,
          reason: '2 is spent — deleting it does not make it available again');

      // Deleting ALL of them is the same rule: the counter is not a function
      // of what happens to be in the list.
      await controller.deleteAlarm(1);
      await controller.lastEvaluation;
      expect(controller.alarms, isEmpty);
      expect(controller.nextAlarmId(), 3);
    });

    test('the id counter survives a restart — after a delete', () async {
      // In memory it is just a variable; the fix is that it is PERSISTED, so a
      // cold start after a delete does not fall back to "highest + 1". The
      // delete is the point: without it the counter and "highest + 1" agree,
      // and a restart proves nothing.
      await engine.store.saveCourts([court]);
      await controller.init();
      await controller.upsertAlarm(
          const NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1'));
      await controller.deleteAlarm(1);
      await controller.lastEvaluation;

      final restarted = NivaatController(engine: engine);
      await restarted.init();
      expect(restarted.nextAlarmId(), 2, reason: 'read back from the store');
    });

    test('the counter and the alarm that spends it land together', () async {
      // This used to assert an ORDER — counter first (REVIEW #9) — because they
      // were two writes and a crash could land between them, leaving an alarm
      // with no counter past it so the next one created would overwrite it,
      // along with every `block + id` notification and cascade slot hanging off
      // that number. They are one transaction now, so there is no between; what
      // is left to check is that a save never advances one without the other.
      //
      // Asserted on the STORE, not the controller: in memory the controller
      // holds both in fields and would agree with itself either way.
      final store = SeqWatchingStore();
      await store.saveCourts([court]);
      final watched = NivaatController(
        engine: NivaatEngine(
          store: store,
          scheduler: ring,
          api: api,
          checks: checks,
          notifier: notifier,
        ),
      );
      await watched.init();

      await watched.upsertAlarm(
          const NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1'));
      // Compared field by field: a record holding a List does not compare by
      // value, so `expect(saves, [(2, [1])])` would fail on list identity even
      // when the contents match.
      expect(store.afterEachSave, hasLength(1));
      expect(store.afterEachSave.single.$1, 2,
          reason: 'the counter is already past alarm 1');
      expect(store.afterEachSave.single.$2, [1],
          reason: 'and alarm 1 is on disk in the same write');

      // An edit writes the alarms and must leave the counter exactly where it
      // was — most calls here are edits, and one that burned a number every
      // time would walk the counter to the block ceiling.
      await watched.toggleAlarm(1, false);
      expect(store.afterEachSave.last.$1, 2);
      expect(store.afterEachSave.last.$2, [1]);
    });

    test('a counter standing on a live alarm never overwrites it', () async {
      // Storage this build cannot write (the counter is saved first), but it
      // is one hand-seeded prefs blob away — the screenshot pass writes them,
      // and the counter is not a model key. What made it worth guarding, and
      // worth guarding HERE rather than with an assert, is that the damage
      // was SILENT: `nextAlarmId` would hand back 1, and `upsertAlarm` reads a
      // colliding id as an edit, so "add alarm" would quietly replace the
      // 06:00 you already had. A skipped number is the harmless direction.
      await engine.store.saveCourts([court]);
      await engine.store.saveAlarms(const [
        NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1'),
        NivaatAlarm(id: 2, hour: 6, minute: 30, courtId: 'c1'),
      ]);
      final seeded = NivaatController(engine: engine);
      await seeded.init();
      expect(await engine.store.loadAlarmIdSeq(), isNull, reason: 'no counter');
      expect(seeded.nextAlarmId(), 3);

      await seeded.upsertAlarm(
          NivaatAlarm(id: seeded.nextAlarmId(), hour: 7, minute: 0, courtId: 'c1'));
      await seeded.lastEvaluation;
      expect(seeded.alarms.map((a) => a.id), [1, 2, 3]);
      expect(seeded.alarms.first.hour, 6, reason: 'the 06:00 alarm survived');
      // And the save writes the counter through, so the state heals itself.
      expect(await engine.store.loadAlarmIdSeq(), 4);
    });

    test('past the block ceiling it reuses the smallest FREE id (REVIEW #21)',
        () async {
      // A counter that only climbs makes the 9999 ceiling more reachable, not
      // less — past it, `ring(10001)` would BE `lateRing(1)`. Reuse is the
      // lesser evil there, but only of a number no live alarm holds.
      await engine.store.saveCourts([court]);
      await engine.store.saveAlarmIdSeq(NivaatIds.maxAlarmId + 1);
      await engine.store.saveAlarms(const [
        NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1'),
        NivaatAlarm(id: 2, hour: 6, minute: 30, courtId: 'c1'),
        NivaatAlarm(id: 4, hour: 7, minute: 0, courtId: 'c1'),
      ]);
      final full = NivaatController(engine: engine);
      await full.init();
      expect(full.nextAlarmId(), 3, reason: 'the gap, not 5 and not 10000');
      // Still pure: N18 caps coexisting alarms at 1440, so a free number
      // always exists and finding it never consumes anything.
      expect(full.nextAlarmId(), 3);
    });

    test('nextAlarmId is pure — the sheet asks twice and must be told once',
        () async {
      // The alarm sheet mints the id for its live HH:MM conflict check and
      // again for the alarm it saves. If asking advanced the counter those two
      // would disagree: it would validate one alarm and write a different one.
      await engine.store.saveCourts([court]);
      await controller.init();
      expect(controller.nextAlarmId(), controller.nextAlarmId());
      expect(controller.nextAlarmId(), 1, reason: 'and nothing was consumed');
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

    test('deleting an alarm disarms the ring it already had', () async {
      // `_stillLive` stops a stale pass ARMING one, and the sweep catches an
      // orphan on a later pass — but the alarm the user is deleting right now
      // has a live ring in hand, and only delete's own cleanup takes it down.
      // Nothing asserted that until this test (REVIEW #23).
      await engine.store.saveCourts([court]);
      await controller.init();
      api.sample = wind(5.0, 5.0); // calm → the follow-up evaluate arms it
      await controller.upsertAlarm(alarm, now: alarmAt.subtract(const Duration(hours: 1)));
      await controller.lastEvaluation;
      expect(ring.scheduled.keys, contains(todayRing),
          reason: 'precondition: there is something to disarm');

      ring.cancelled.clear();
      await controller.deleteAlarm(7);
      await controller.lastEvaluation;

      for (final id in NivaatIds.allRings(7)) {
        expect(ring.scheduled.containsKey(id), isFalse,
            reason: 'locker $id survived the delete');
      }
      expect(ring.cancelled, containsAll(NivaatIds.allRings(7)),
          reason: 'every locker is cleared by hand, not left to the sweep — '
              'the sweep only runs on the NEXT evaluateAll');
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
    // Simulate stop: gone from the plugin, not ringing → ambiguous B unknown
    // unless we still hear it. Here the user stopped after it sounded, so
    // mark audible settle via the pending Rule 2 promotes on open.
    api.sample = wind(20.0, 24.0); // court 12 >> 4
    await engine.evaluateAlarm(alarm, [court],
        now: alarmAt.add(const Duration(minutes: 5)));
    // Still armed on the plugin → held as pending, not Rang from dateTime.
    expect(await engine.store.loadPendingRing(7), isNotNull);
    expect(await engine.store.loadHistory(), isEmpty,
        reason: 'schedule alone is never Rang proof');
    await settleAudibleRing(
      ring: ring,
      engine: engine,
      alarm: alarm,
      courts: [court],
      now: alarmAt.add(const Duration(minutes: 5)),
    );

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
    await settleAudibleRing(
      ring: ring,
      engine: engine,
      alarm: alarm,
      courts: [court],
      now: alarmAt.add(const Duration(minutes: 45)),
    );

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
    expect(checks.booked[7], alarmAt.add(const Duration(hours: 12)),
        reason: "tomorrow's T-12h check keeps Android's cascade alive");

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
    // Alarm 7's pair is ONE occurrence pushed twice, so they carry different
    // push numbers; sharing one would converge them into a single row by
    // design.
    for (final (id, courtId, seq) in [
      (7, 'c1', 1),
      (7, 'c1', 2),
      (99, 'c1', 1),
      (8, 'c2', 1)
    ]) {
      await engine.store.upsertHistory(HistoryRecord(
          alarmId: id,
          courtId: courtId,
          at: DateTime(2026, 7, 13, 6, id % 60),
          pushSeq: seq,
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
    // `upsertAlarm` publishes its evaluation rather than awaiting it, so
    // without this the pass runs on into the NEXT test — past `setUp`, against
    // a store it has already re-seeded — and writes that test's CheckState for
    // an occurrence off the real clock. It only ever "passed" by winning a
    // race with teardown.
    await controller.lastEvaluation;

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

    test('a check landing just after T leaves the pending ring alone', () async {
      // THE #1 regression guard. The ring for T and the T-0 wind check are two
      // exact alarms for the same instant, with no ordering between them. When
      // the check wins by a hair the ring has not sounded yet, so Rule 1 sees
      // nothing audible and Rule 2 holds pending (not Rang from schedule) —
      // correct, it is about to. What must NOT follow is the roll-on writing
      // tomorrow into the same locker: `Alarm.set` stops the id it is
      // replacing, so the alarm went silent a heartbeat before it would have
      // woken you.
      api.sample = wind(5.0, 5.0); // calm — the ladder commits a ring for T
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(hours: 1)));
      expect(ring.scheduled[todayRing]!.at, alarmAt, reason: 'pre-armed for T');
      ring.cancelled.clear();

      // The check wins the race by two seconds.
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.add(const Duration(seconds: 2)));

      expect(ring.scheduled[todayRing]?.at, alarmAt,
          reason: 'the ring about to sound is still armed, for its own time');
      expect(ring.cancelled, isNot(contains(todayRing)),
          reason: 'and nothing cancelled it on the way past');
      expect(ring.scheduled[nextRing]!.at, alarmAt.add(const Duration(days: 1)),
          reason: 'tomorrow is pre-armed too, in a locker of its own');
      // Held pending — not Rang until audible / drop / ambiguous B.
      expect(await engine.store.loadPendingRing(7), isNotNull);
      expect(await engine.store.loadHistory(), isEmpty,
          reason: 'schedule success is never Rang proof');
    });

    test('the next occurrence hands its pre-arm back to the normal locker',
        () async {
      // The other half: `nextRing` is a staging locker, not a second home. At
      // tomorrow's first ladder rung the pre-arm moves to `ring`, and the
      // staging copy must go — two live alarms for one instant ring twice.
      api.sample = wind(5.0, 5.0);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(hours: 1)));
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.add(const Duration(seconds: 2)));
      final tomorrow = alarmAt.add(const Duration(days: 1));
      expect(ring.scheduled[nextRing]!.at, tomorrow);

      await engine.evaluateAlarm(alarm, [court],
          now: tomorrow.subtract(const Duration(hours: 1)));

      expect(ring.scheduled[todayRing]!.at, tomorrow,
          reason: 'the occurrence now owns its own locker');
      expect(ring.scheduled.containsKey(nextRing), isFalse,
          reason: 'the staged copy is cancelled, or the alarm sounds twice');
    });

    test('arming a late ring disarms the pre-arm it supersedes', () async {
      // The path where this is load-bearing: calm all the way, so the skip
      // branch never runs and nothing else clears the pre-arm. The ladder
      // commits a ring for T itself, then the T-0 check re-decides on live
      // wind and arms a ring 10s out. Both are for the SAME occurrence, so the
      // first must be disarmed — otherwise the alarm sounds at T and again at
      // T+10s. (`cancelled` is what proves this rather than `scheduled`: the
      // cancel and any later write to that locker are indistinguishable in the
      // final map.)
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
      expect(ring.scheduled[nextRing]!.at,
          alarmAt.add(const Duration(days: 1)),
          reason: "tomorrow goes in the roll-on's own locker");
      expect(ring.scheduled.containsKey(todayRing), isFalse,
          reason: 'and the locker it superseded stays empty');
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

    // Toggle-off, delete, edit-abandon and the whole card lifecycle moved to
    // occurrence_story_test.dart, which asserts them as whole rendered strings.

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

    test('a disabled alarm is disarmed in EVERY locker', () async {
      final late = await armLateRing();
      // Two lockers are occupied: the late ring, and tomorrow's roll-on
      // pre-arm. (`todayRing` is empty here — the skip at T cleared it.)
      expect(ring.scheduled.keys, containsAll(<int>[lateRing, nextRing]));

      await engine.evaluateAlarm(alarm.copyWith(enabled: false), [court],
          now: late.add(const Duration(minutes: 1)));

      expect(ring.scheduled.containsKey(todayRing), isFalse);
      expect(ring.scheduled.containsKey(nextRing), isFalse);
      expect(ring.scheduled.containsKey(lateRing), isFalse,
          reason: 'cancelling one locker leaves a disabled alarm still ringing');
    });
  });

  group('nivaatHistoryNote (MESSAGES.md N10)', () {
    HistoryRecord row(
      HistoryKind kind, {
      DateTime? watchedUntil,
      DateTime? checkedAt,
      DateTime? endedAt,
    }) =>
        HistoryRecord(
          alarmId: 7,
          courtId: 'c1',
          at: alarmAt,
          kind: kind,
          watchedUntil: watchedUntil,
          checkedAt: checkedAt,
          checkingEndedAt: endedAt,
          outcome: CheckOutcome.skippedWindy,
        );

    test('a still-checking row states its promise, forever', () {
      final r = row(HistoryKind.stillChecking,
          watchedUntil: alarmAt.add(const Duration(minutes: 30)));
      expect(nivaatHistoryNote(r), 'watching until 06:30');
    });

    test('an outcome row stays quiet when checking ended on its last reading',
        () {
      final r = row(HistoryKind.outcome,
          checkedAt: alarmAt.add(const Duration(minutes: 30)),
          endedAt: alarmAt.add(const Duration(minutes: 30)));
      expect(nivaatHistoryNote(r), isNull,
          reason: 'printing 06:30 twice on one line is noise, not information');
    });

    test('...and speaks up when it outlasted that reading', () {
      final r = row(HistoryKind.outcome,
          checkedAt: alarmAt.add(const Duration(minutes: 29)),
          endedAt: alarmAt.add(const Duration(minutes: 30)));
      expect(nivaatHistoryNote(r), 'watched until 06:30',
          reason: 'the 06:30 attempt is all that separates this from giving '
              'up at 06:29');
    });

    test('seconds inside the same minute do not count as outlasting', () {
      final r = row(HistoryKind.outcome,
          checkedAt: alarmAt.add(const Duration(minutes: 30)),
          endedAt: alarmAt.add(const Duration(minutes: 30, seconds: 40)));
      expect(nivaatHistoryNote(r), isNull,
          reason: 'both display 06:30 — compared as shown, not as instants');
    });

    test('a cancelled row says when you stopped it', () {
      final r = row(HistoryKind.cancelled,
          endedAt: alarmAt.add(const Duration(minutes: 5)));
      expect(nivaatHistoryNote(r), 'stopped 06:05');
    });

    test('a deadline crossing midnight carries its date', () {
      final late = DateTime(2026, 7, 22, 23, 49);
      final r = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: late,
        kind: HistoryKind.stillChecking,
        watchedUntil: late.add(const Duration(minutes: 30)),
        outcome: CheckOutcome.skippedWindy,
      );
      expect(nivaatHistoryNote(r), 'watching until 23 Jul 00:19',
          reason: 'a bare 00:19 would look earlier than the 23:49 alarm');
    });
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

  // The user-visible half of mid-window edits — the card and the rows they
  // produce — is asserted as whole strings in occurrence_story_test.dart. What
  // stays here is the machinery underneath: which occurrence survives, and
  // whether the cascade keeps flying.
  group('mid-window edits keep or abandon the occurrence', () {
    Future<void> windyThroughT() async {
      api.sample = wind(9.0, 10.0);
      await engine.store.saveCourts([court]);
      await engine.store.saveAlarms([alarm]);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(minutes: 1)));
      await engine.evaluateAlarm(alarm, [court], now: alarmAt);
    }

    test('raising the wind limit keeps today flying, and it rings late',
        () async {
      await windyThroughT();
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
          reason: 'the same occurrence rings under the raised limit');
      expect(
          (await engine.store.loadHistory())
              .any((h) => h.kind == HistoryKind.cancelled),
          isFalse,
          reason: 'continue path — nobody cancelled anything');
    });

    test('adding a weekday keeps today flying', () async {
      await windyThroughT();
      final otherDay = alarmAt.weekday % 7 + 1;
      final added = alarm.copyWith(weekdays: {...alarm.weekdays, otherDay});
      final t = alarmAt.add(const Duration(minutes: 5));
      expect(
          nivaatEditAbandonsInFlight(alarm, added,
              state: await engine.store.loadCheckState(7), now: t),
          isFalse);
      await engine.store.saveAlarms([added]);
      await engine.retainInFlightEdits(alarm, added, now: t);
      await engine.evaluateAlarm(added, [court], now: t);

      expect((await engine.store.loadCheckState(7))!.alarmAt, alarmAt,
          reason: 'still the same occurrence');
    });

    test('dropping the in-flight weekday abandons it', () async {
      await windyThroughT();
      final withoutToday = alarm
          .copyWith(weekdays: {...alarm.weekdays}..remove(alarmAt.weekday));
      final t = alarmAt.add(const Duration(minutes: 5));
      expect(
          nivaatEditAbandonsInFlight(alarm, withoutToday,
              state: await engine.store.loadCheckState(7), now: t),
          isTrue);
    });

    test('shrinking Keep checking past now finalises on SAVE, not later',
        () async {
      // Where it finalises is the whole point (2026-07-31). This asserted only
      // that an outcome existed *after* an evaluate, so it stayed green while
      // the retain was pushing an alerting `watching until 06:01` card at
      // 06:02 first — a promise already broken, and an immutable row with it.
      // Split in two now: the retain closes the occurrence, the evaluate only
      // rolls tomorrow on. (`occurrence_story_test` 14d locks how it reads.)
      await windyThroughT();
      final tiny = alarm.copyWith(retryMinutesAfter: 1);
      final t = alarmAt.add(const Duration(minutes: 2));
      await engine.store.saveAlarms([tiny]);
      await engine.retainInFlightEdits(alarm, tiny, now: t);

      var history = await engine.store.loadHistory();
      expect(history.first.kind, HistoryKind.outcome,
          reason: 'the newest row is the ending, written by the retain itself');
      expect(history.first.outcome, isNot(CheckOutcome.rang));
      expect(history.any((h) => h.kind == HistoryKind.cancelled), isFalse,
          reason: 'the window ran out — nobody cancelled it');
      expect(notifier.card!.status, kNivaatSkipped);
      expect(
          history.where((h) => h.kind == HistoryKind.stillChecking).map((h) =>
              h.watchedUntil),
          everyElement(predicate<DateTime?>((u) => u != null && t.isBefore(u))),
          reason: 'no row may promise a deadline that had already passed');
      expect(await engine.store.loadCheckState(7), isNull,
          reason: 'the occurrence is closed and its state cleared');

      // Only now does the evaluate have anything to do: book tomorrow.
      await engine.evaluateAlarm(tiny, [court], now: t);
      history = await engine.store.loadHistory();
      expect(history.first.kind, HistoryKind.outcome,
          reason: 'nothing further was appended');
      expect((await engine.store.loadCheckState(7))?.alarmAt,
          alarmAt.add(const Duration(days: 1)),
          reason: 'today is closed; the roll-on has booked tomorrow');
    });

    test('widening after the old cap died does not resurrect that occurrence',
        () async {
      api.sample = wind(9.0, 10.0);
      final short = alarm.copyWith(retryMinutesAfter: 1);
      await engine.store.saveCourts([court]);
      await engine.store.saveAlarms([short]);
      await engine.evaluateAlarm(short, [court],
          now: alarmAt.subtract(const Duration(minutes: 1)));
      await engine.evaluateAlarm(short, [court], now: alarmAt);
      // Past T+1 and past its minute, without ever evaluating the cap.
      final longer = short.copyWith(retryMinutesAfter: 30);
      final t = alarmAt.add(const Duration(minutes: 2));
      await engine.store.saveAlarms([longer]);
      await engine.retainInFlightEdits(short, longer, now: t);

      final history = await engine.store.loadHistory();
      expect(
          history
              .where((h) => h.kind == HistoryKind.stillChecking)
              .single
              .watchedUntil,
          alarmAt.add(const Duration(minutes: 1)),
          reason: 'the dead window keeps the promise it actually made');
      expect(
          history.any((h) => h.kind == HistoryKind.outcome && h.at == alarmAt),
          isTrue,
          reason: 'finalised instead of reviving under +30m');
      expect(await engine.store.loadCheckState(7), isNull,
          reason: 'a dead window must not reopen on the next evaluate');
    });
  });

  test('nivaatLatestRowPerOccurrence takes the highest pushSeq', () {
    HistoryRecord row(int seq, HistoryKind kind, {DateTime? at}) =>
        HistoryRecord(
          alarmId: 7,
          courtId: 'c1',
          at: at ?? alarmAt,
          kind: kind,
          pushSeq: seq,
          outcome: CheckOutcome.skippedWindy,
        );
    final tomorrow = alarmAt.add(const Duration(days: 1));
    final latest = nivaatLatestRowPerOccurrence([
      row(2, HistoryKind.outcome),
      row(1, HistoryKind.stillChecking),
      row(1, HistoryKind.stillChecking, at: tomorrow),
    ]);

    expect(latest, hasLength(2), reason: 'two occurrences, not four rows');
    expect(latest['7@${alarmAt.millisecondsSinceEpoch}']!.kind,
        HistoryKind.outcome,
        reason: 'list order must not decide it — the push number does');
    expect(latest['7@${tomorrow.millisecondsSinceEpoch}']!.kind,
        HistoryKind.stillChecking);

    // Equal numbers have to break SOMEWHERE, and this function takes any
    // iterable — so the rule is list order, and callers pass newest-first.
    // Resolving a tie the other way reads a finished occurrence as an open
    // window, and home would promise checking that already stopped.
    final tied = nivaatLatestRowPerOccurrence([
      row(0, HistoryKind.outcome),
      row(0, HistoryKind.stillChecking),
    ]);
    expect(tied.values.single.kind, HistoryKind.outcome,
        reason: 'newest-first: the outcome row was written last');
  });

  test('an off-step volume snaps to the nearest file, ties going louder', () {
    // volumeForWind only ever returns a step, but the resolver takes any
    // 0-1 double on purpose: retuning the ramp is meant to be a one-line edit
    // in core plus a render, with no midpoint table here to keep in sync. So
    // every value must land on a file that ships, not off the end of it.
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
    // on the one occurrence it mattered. Sweep the whole ramp against the disk.
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

  test('a failed history write leaves no card behind it', () async {
    // `_pushCard` writes the row first and only then notifies, so the shade
    // can never hold a card the log cannot explain. The reverse order is the
    // one the user cannot recover from: a notification blaming the wind for a
    // occurrence that left no record.
    final failing = NivaatEngine(
      store: FailingHistoryStore(),
      scheduler: ring,
      api: api,
      checks: checks,
      notifier: notifier,
    );
    api.sample = wind(12.0, 14.0); // court 7.2 > 4 → windy → would post the card

    // A pre-T rung first, so the occurrence is in flight at T — without it
    // `nextOccurrence` rolls straight to tomorrow and no card is due at all.
    // It writes no history, so the failing store sails through it.
    await failing.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 5)));
    expect(notifier.pushes, isEmpty, reason: 'nothing is posted before T');

    await expectLater(
      failing.evaluateAlarm(alarm, [court], now: alarmAt),
      throwsA(isA<Exception>()),
      reason: 'the row write is deliberately NOT swallowed — the whole '
          'evaluate unwinds instead',
    );
    expect(notifier.pushes, isEmpty,
        reason: 'nothing was shown, because nothing was recorded');
  });

  group('nivaatHistoryLine', () {
    final at = DateTime(2026, 7, 22, 6);
    HistoryRecord row(CheckOutcome outcome,
            {double? volume, DateTime? slotAt, RingDisposition? disposition}) =>
        HistoryRecord(
            alarmId: 7,
            courtId: 'c1',
            at: at,
            outcome: outcome,
            courtSpeedKmh: 3,
            rawGustKmh: 16,
            courtSpeedLimitKmh: 4,
            rawGustLimitKmh: 14.667,
            slotAt: slotAt,
            ringDisposition: disposition,
            volume: volume);

    test('quotes the volume it rang at, alongside the numbers', () {
      expect(nivaatHistoryLine(row(CheckOutcome.rang, volume: 0.85)),
          'Rang (vol. 85%) · wind 3 (≤4) · gusts 16 (≤15) km/h');
    });

    test('a cancelled row is bare, whatever the wind was doing', () {
      // The kind wins over the reason here — the first branch of the builder,
      // and the only one that ignores its numbers. The record still CARRIES
      // the last known wind (so the data stays true); the line just doesn't
      // speak for it, because you ended the occurrence, not the weather.
      final cancelled = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: at,
        kind: HistoryKind.cancelled,
        checkingEndedAt: at.add(const Duration(minutes: 5)),
        outcome: CheckOutcome.skippedGusty,
        courtSpeedKmh: 3,
        rawGustKmh: 16,
        courtSpeedLimitKmh: 4,
        rawGustLimitKmh: 14.667,
      );
      expect(nivaatHistoryLine(cancelled), 'Cancelled');
    });

    test('a rang row without a volume drops the number, never the sheet', () {
      // `volume` is optional on the record, and history is PERSISTED: force-
      // unwrapping it meant one such row crashed the log open-after-open. The
      // row still has to explain the occurrence, so only the parenthetical
      // goes.
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

    test('the numbers name the slot they came from (2026-08-25)', () {
      // The card learned this when the window rule landed; history had not,
      // and it is the surface that has to explain an occurrence weeks later.
      // `Skipped · wind 6 (≤4)` beside a sub reading `06:00 · last checked
      // 06:00` invites exactly the wrong conclusion — that 06:00 was windy,
      // when 06:00 may have been still and the six came from a slot three
      // quarters of an hour later.
      final slot = at.add(const Duration(minutes: 45));
      expect(
        nivaatHistoryLine(row(CheckOutcome.skippedWindy, slotAt: slot)),
        'Skipped · wind 3 (≤4) · gusts 16 (≤15) km/h · at 06:45',
      );
      // Trailing, where the CARD puts it up front: the card's `Too windy at
      // 06:45` reads as a condition of a moment, while `Skipped at 06:45`
      // would read as when the skip was decided — a different fact, and one
      // the sub already carries.
      expect(nivaatHistoryLine(row(CheckOutcome.skippedWindy, slotAt: slot)),
          isNot(startsWith('Skipped at')));
    });

    test('a ring names no slot — just the numbers (2026-08-31)', () {
      // The card and the home row's ⓘ have said this since 2026-08-25: a skip
      // is caused by ONE slot and can be pinned to it, while a ring is the
      // whole play window clearing. History was the last surface still naming
      // one, and it read as though the ring had a decisive minute. The numbers
      // stay — they earned the ring; only the false pinpoint goes.
      final slot = at.add(const Duration(minutes: 45));
      // The control, and it belongs in THIS test: nothing below would notice
      // if the builder stopped naming slots altogether — the equality expects
      // a slot-less string, and the loop asserts absences outright.
      expect(nivaatHistoryLine(row(CheckOutcome.skippedWindy, slotAt: slot)),
          endsWith(' · at 06:45'));
      expect(
        nivaatHistoryLine(row(CheckOutcome.rang, volume: 0.85, slotAt: slot)),
        'Rang (vol. 85%) · wind 3 (≤4) · gusts 16 (≤15) km/h',
      );
      // Every disposition row is a ring too — they differ in what became of
      // the ring, never in what the wind said — so none of them may name a
      // slot. All three, because all three are separate MESSAGES entries
      // (N4 / N4a / N4b) and this is the rule that changed for each.
      for (final d in RingDisposition.values) {
        expect(
            nivaatHistoryLine(
                row(CheckOutcome.rang, slotAt: slot, disposition: d)),
            isNot(contains('at 06:45')),
            reason: '$d still describes a ring');
      }
    });

    test('a slot from another day carries its date, like every other time', () {
      // Last night's 22:00 reading behind a 06:00 alarm — a bare `22:00` here
      // would read as the alarm's own day, four hours after it.
      expect(
        nivaatHistoryLine(row(CheckOutcome.skippedWindy,
            slotAt: at.subtract(const Duration(hours: 8)))),
        'Skipped · wind 3 (≤4) · gusts 16 (≤15) km/h · at 21 Jul 22:00',
      );
    });

    test('no slot, no suffix — and no dangling "at"', () {
      // Rows written before 2026-08-25 have no slot, and a no-data row never
      // has one. Both must read exactly as they always did.
      expect(nivaatHistoryLine(row(CheckOutcome.skippedWindy)),
          'Skipped · wind 3 (≤4) · gusts 16 (≤15) km/h');
      expect(
          nivaatHistoryLine(HistoryRecord(
              alarmId: 7,
              courtId: 'c1',
              at: at,
              outcome: CheckOutcome.rang,
              slotAt: at)),
          'Rang',
          reason: 'a slot with no readings has nothing to be the slot OF');
    });

    test('ring disposition overrides the wind outcome axis (N4a / N4b)', () {
      // Never reuse skippedNoData for a platform drop: that one means the
      // wind could not be read, which is a different fact about a different
      // thing.
      expect(
          nivaatHistoryLine(HistoryRecord(
            alarmId: 7,
            courtId: 'c1',
            at: at,
            outcome: CheckOutcome.rang,
            ringDisposition: RingDisposition.missed,
            courtSpeedKmh: 3,
            rawGustKmh: 16,
            courtSpeedLimitKmh: 4,
            rawGustLimitKmh: 15,
          )),
          'Missed · wind 3 (≤4) · gusts 16 (≤15) km/h');
      expect(
          nivaatHistoryLine(HistoryRecord(
            alarmId: 7,
            courtId: 'c1',
            at: at,
            outcome: CheckOutcome.rang,
            ringDisposition: RingDisposition.unknown,
          )),
          "Couldn't confirm");
      // A row that never settled still reads off the wind axis, so the two are
      // genuinely orthogonal rather than one shadowing the other.
      expect(
          nivaatHistoryLine(HistoryRecord(
            alarmId: 7,
            courtId: 'c1',
            at: at,
            outcome: CheckOutcome.rang,
            volume: 0.85,
          )),
          'Rang (vol. 85%)');
    });
  });

  /// In-flight cascade for [at] — what the home cue needs to treat a snapshot
  /// as still being checked (toggle-off clears this; toggle-on re-arms later).
  CheckState flying(DateTime at, {int id = 7}) => CheckState(
        alarmId: id,
        alarmAt: at,
        cardShown: true,
        skipCourtSpeedKmh: 5.4,
        skipRawGustKmh: 10,
      );

  test('nivaatAlarmListSub: days, court, limit — and no minutes at all', () {
    expect(nivaatAlarmListSub(alarm, court), 'Every day · Home Court · ≤4 km/h');
    // A non-default Keep checking used to show as `· +60m`. It was the alarm's
    // only tunable minutes then; there are three now, and singling one out
    // says less than showing none (Samyak, 2026-08-25). The row is identical
    // whatever the three are set to — that is the assertion.
    for (final minutes in [1, 15, 60]) {
      expect(
        nivaatAlarmListSub(alarm.copyWith(retryMinutesAfter: minutes), court),
        'Every day · Home Court · ≤4 km/h',
      );
    }
    expect(
      nivaatAlarmListSub(
          alarm.copyWith(timeUntilPlayMinutes: 60, minPlayMinutes: 60), court),
      'Every day · Home Court · ≤4 km/h',
    );
    // The `court removed` fallback was cut on 2026-08-15: deleting a court
    // deletes its alarms in the same step and only the UI isolate writes the
    // alarm list, so no state could render it. `court` is non-null now, and
    // this assertion is what is left of the case — the court is always named.
    expect(nivaatAlarmListSub(alarm, court), contains('Home Court'));
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
    // The window runs to the end of the cap's MINUTE. Any reading taken in
    // that minute still displays as 06:30, so it is honest to count it; the
    // first instant that would display 06:31 is where it stops. Five seconds
    // of slack used to be the rule, and a wake 10s late was enough to make the
    // engine close the books on the previous reading — `last checked 06:29`
    // on a 30-minute window, `06:00` on a 1-minute one (device, 2026-07-26).
    expect(
      nivaatOccurrenceInFlight(
          alarm, state, cap.add(const Duration(seconds: 40))),
      isTrue,
      reason: '06:30:40 still reads as 06:30',
    );
    expect(
      nivaatOccurrenceInFlight(
          alarm, state, cap.add(const Duration(seconds: 59, milliseconds: 999))),
      isTrue,
    );
    expect(
      nivaatOccurrenceInFlight(alarm, state, cap.add(const Duration(minutes: 1))),
      isFalse,
      reason: 'this one would record 06:31 — later than the card promised',
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

  test('nivaatHomeWatchingLine: only while a snapshot window is still open', () {
    final snapshot = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: alarmAt,
        kind: HistoryKind.stillChecking,
        pushSeq: 1,
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
        kind: HistoryKind.stillChecking,
        pushSeq: 1,
        watchedUntil: alarmAt.add(const Duration(minutes: 30)),
        outcome: CheckOutcome.skippedWindy);
    final rang = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: alarmAt,
        pushSeq: 2,
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

  test('nivaatHomeWatchingLine: clears the moment you cancel the occurrence',
      () {
    // Toggling the alarm off mid-window appends a `Cancelled` row. The cue has
    // to go with it — the outcome case above shares this code path, but this
    // is the one you reach by hand, and it is the one that would read as the
    // app ignoring you.
    final snapshot = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: alarmAt,
        kind: HistoryKind.stillChecking,
        pushSeq: 1,
        watchedUntil: alarmAt.add(const Duration(minutes: 30)),
        outcome: CheckOutcome.skippedWindy);
    final cancelled = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: alarmAt,
        kind: HistoryKind.cancelled,
        pushSeq: 2,
        checkingEndedAt: alarmAt.add(const Duration(minutes: 5)),
        outcome: CheckOutcome.skippedWindy);
    expect(
      nivaatHomeWatchingLine([cancelled, snapshot],
          alarms: [alarm],
          checkStates: [flying(alarmAt)],
          now: alarmAt.add(const Duration(minutes: 10))),
      isNull,
      reason: 'the newest row is no longer a promise',
    );
  });

  test('nivaatHomeWatchingLine: a final for a *different* occurrence stays quiet about this one',
      () {
    final snapshot = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: alarmAt,
        kind: HistoryKind.stillChecking,
        pushSeq: 1,
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
        kind: HistoryKind.stillChecking,
        pushSeq: 1,
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
        kind: HistoryKind.stillChecking,
        pushSeq: 1,
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
        kind: HistoryKind.stillChecking,
        pushSeq: 1,
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
        kind: HistoryKind.stillChecking,
        pushSeq: 1,
        watchedUntil: alarmAt.add(const Duration(minutes: 30)),
        outcome: CheckOutcome.skippedWindy);
    final laterAt = alarmAt.add(const Duration(minutes: 15));
    final later = HistoryRecord(
        alarmId: 2,
        courtId: 'c1',
        at: laterAt,
        kind: HistoryKind.stillChecking,
        pushSeq: 1,
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
  test('an edit landing mid-fetch is not armed by the pass that missed it',
      () async {
    // REVIEW #23's race with the alarm still PRESENT. `_stillLive` re-reads the
    // store at the point of no return, but existence alone said "fine" while
    // the pass went on to arm 06:00 — a time the user had already moved away
    // from, on a locker the new occurrence never looks at, so it fires for good.
    final gated = GatedApi()..sample = wind(5.0, 5.0);
    final e = NivaatEngine(
      store: engine.store,
      scheduler: ring,
      api: gated,
      checks: checks,
      notifier: notifier,
    );
    final pass = e.evaluateAlarm(alarm, [court],
        now: alarmAt.subtract(const Duration(minutes: 30)));
    await gated.parked.future;

    // The user moves the alarm an hour later while the fetch is in flight.
    await engine.store.saveAlarms([alarm.copyWith(hour: 7)]);
    gated.gate.complete();
    await pass;

    expect(ring.scheduled.containsKey(todayRing), isFalse,
        reason: 'the stale snapshot must not arm the time it was holding');
    expect(ring.log.where((l) => l.at == alarmAt), isEmpty);
  });

  group('the play window (2026-08-25)', () {
    test('the window asked for is T+ready .. T+ready+play, not T itself', () {
      // The flaw this fixes: the old check read a single instant, and inside
      // the last 15 minutes it read `current` — i.e. NOW — so a 06:00 alarm
      // was decided on the 05:45 wind.
      api.sample = wind(5.0, 5.0);
      return engine
          .evaluateAlarm(alarm, [court], now: alarmAt.subtract(const Duration(hours: 1)))
          .then((_) {
        expect(api.asked.last,
            (alarmAt.add(const Duration(minutes: 30)),
                alarmAt.add(const Duration(minutes: 60))));
      });
    });

    test('ONE windy slot inside the window skips the whole occurrence',
        () async {
      // Calm on arrival, windy ten minutes in. The old single-point check rang
      // this one; you would have got there and not been able to play.
      final from = alarmAt.add(const Duration(minutes: 30));
      api.window = [
        wind(5.0, 5.0, from),
        wind(20.0, 9.0, from.add(const Duration(minutes: 15))),
        wind(5.0, 5.0, from.add(const Duration(minutes: 30))),
      ];
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(hours: 1)));
      expect(ring.scheduled, isEmpty, reason: 'the worst slot decides');
    });

    test('a RETRY judges its own window, not the one T would have had',
        () async {
      // Woken late, you get on court late — so a retry at T+15 must look at
      // T+15+ready onwards. Re-judging T's window would decide the occurrence
      // on wind from a time you will already have missed.
      // The occurrence must SKIP first, or T has a committed ring and the pass
      // at T+15 settles it and rolls on to tomorrow — a different occurrence,
      // and a window a day away.
      api.sample = wind(20.0, 9.0);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(hours: 1)));
      final preT = api.asked.last;

      api.sample = wind(5.0, 5.0);
      final late = alarmAt.add(const Duration(minutes: 15));
      await engine.evaluateAlarm(alarm, [court], now: late);
      // The retry's OWN fetch. Finding calm air it also rings late, finalises
      // the occurrence and rolls on — and the roll-on fetches tomorrow's
      // window, so the last entry belongs to a different occurrence entirely.
      final retry = api.asked[1];

      expect(retry.$1.isAfter(preT.$1), isTrue,
          reason: 'the retry looks further ahead than the pre-T check did');
      // A late ring lands ~10s from now, and the window hangs off THAT.
      expect(retry.$1.difference(late).inMinutes, 30);
      expect(api.asked.last.$1.difference(late).inHours, greaterThan(20),
          reason: "the roll-on asks about tomorrow, and is a separate fetch");
    });

    test('changing the play window is a CONTINUE edit, like the wind limit',
        () {
      // It re-decides the same occurrence under new settings; it does not move
      // the occurrence, so there is nothing to abandon.
      const a = NivaatAlarm(id: 7, hour: 6, minute: 0, courtId: 'c1');
      expect(
          nivaatEditAbandonsInFlight(a, a.copyWith(minPlayMinutes: 60)), isFalse);
      expect(
          nivaatEditAbandonsInFlight(a, a.copyWith(timeUntilPlayMinutes: 60)),
          isFalse);
    });
  });

  group('the ladder is booked all at once (2026-08-25)', () {
    test('every rung still ahead is booked, not just the next one', () async {
      // The chain fix. One booking per pass meant a pass that died mid-fetch
      // deleted every rung after it, and a lone alarm had no backstop at all.
      //
      // T-23h, not earlier: this fixture is a DAILY alarm, so anything before
      // T-24h resolves to yesterday's occurrence instead. Which also means a
      // daily alarm can never book its own T-24h rung — that instant is the
      // previous day's alarm — so eight is the real ceiling here and nine
      // is only reachable for a weekly one.
      api.sample = wind(5.0, 5.0);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(hours: 23)));
      expect(checks.bookedRungs[7]!.keys, [1, 2, 3, 4, 5, 6, 7, 8],
          reason: 'the whole remaining ladder, T-12h through T-0');
      expect(checks.bookedRungs[7]![1],
          alarmAt.subtract(const Duration(hours: 12)));
      expect(checks.bookedRungs[7]![8], alarmAt);
    });

    test('rungs already past are not booked', () async {
      api.sample = wind(5.0, 5.0);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(hours: 2)));
      // T-24h, -12h, -6h, -3h are behind us; -2h is this instant, not after.
      expect(checks.bookedRungs[7]!.keys, [5, 6, 7, 8]);
    });
  });

  group('a retired wind model (2026-08-25)', () {
    test('is pruned from the stored list and the fetch retried', () async {
      // Open-Meteo fails the WHOLE request on a name it does not recognise, and
      // publishes no list of models — so this rejection is the only notice a
      // hard-coded name has been retired.
      final rejecting = _RejectsModels({'cma_grapes_global'}, wind(5.0, 5.0));
      final store = NivaatStore();
      await store.saveCourts([court]);
      await store.saveAlarms([alarm]);
      final e = NivaatEngine(
        store: store,
        scheduler: FakeRing(),
        api: rejecting,
        checks: FakeChecks(),
        notifier: FakeNotifier(),
      );
      await e.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(hours: 1)));

      expect(rejecting.calls, 2, reason: 'refused once, then retried');
      expect(await store.loadWindModels(),
          isNot(contains('cma_grapes_global')));
      expect(await store.loadWindModels(), hasLength(6),
          reason: 'only the named model goes');
    });

    test('a rejection naming something we never asked for does not loop',
        () async {
      final rejecting = _RejectsModels({'not_in_our_list'}, wind(5.0, 5.0));
      final store = NivaatStore();
      await store.saveCourts([court]);
      await store.saveAlarms([alarm]);
      final e = NivaatEngine(
        store: store,
        scheduler: FakeRing(),
        api: rejecting,
        checks: FakeChecks(),
        notifier: FakeNotifier(),
      );
      // Soft-fails as a no-data occurrence rather than spinning.
      await e.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(hours: 1)));
      expect(rejecting.calls, 1);
      expect(await store.loadWindModels(), hasLength(7));
    });

    test('FIVE retired at once still reaches the models that work', () async {
      // The loop used to count UP while the list it was draining counted
      // DOWN — `i <= models.length` re-read the live list — so the two met in
      // the middle and seven names allowed only four prunes before the pass
      // gave up with `wind model list did not settle`, a sentence describing
      // something that had not happened. One retired name (the two cases
      // above) never showed it. Five does: the pass has to get past the fifth
      // refusal to reach the two names that answer.
      final rejecting = _RejectsModels({
        'ecmwf_ifs',
        'ncep_gfs_global',
        'dwd_icon_global',
        'ukmo_global_deterministic_10km',
        'cmc_gem_gdps',
      }, wind(5.0, 5.0));
      final ring = FakeRing();
      final store = NivaatStore();
      await store.saveCourts([court]);
      await store.saveAlarms([alarm]);
      final e = NivaatEngine(
        store: store,
        scheduler: ring,
        api: rejecting,
        checks: FakeChecks(),
        notifier: FakeNotifier(),
      );
      await e.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(hours: 1)));

      // Five refusals, each asking for one fewer name, then the request that
      // answered. Before the fix the drain stopped at four and never got here.
      expect(rejecting.sizes.take(6), [7, 6, 5, 4, 3, 2]);
      expect(await store.loadWindModels(),
          ['meteofrance_arpege_world', 'cma_grapes_global'],
          reason: 'only the five named go, and order is preserved');
      // The assertion that matters: a real verdict came out of it. Stopping
      // early failed the fetch, which the engine reads as a no-data occurrence
      // — so the alarm simply would not have been armed.
      expect(ring.scheduled[todayRing]?.at, alarmAt,
          reason: 'the surviving models decided the occurrence');
    });

    test('every name retired ends as no-data, not as a spin', () async {
      // The far end of the same loop: drained to empty, it has to stop on the
      // empty guard rather than run out of turns first.
      final rejecting =
          _RejectsModels(OpenMeteo.defaultWindModels.toSet(), wind(5.0, 5.0));
      final ring = FakeRing();
      final store = NivaatStore();
      await store.saveCourts([court]);
      await store.saveAlarms([alarm]);
      final e = NivaatEngine(
        store: store,
        scheduler: ring,
        api: rejecting,
        checks: FakeChecks(),
        notifier: FakeNotifier(),
      );
      await e.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(hours: 1)));

      // Seven refusals and then it STOPS. The eighth call is the bug this
      // pins (2026-08-30): pruning the last name emptied the table, the reload
      // inside the loop read an empty table as a fresh install and put all
      // seven back, so the empty-list guard was never reached and every check
      // burned an extra request re-seeding names it had just retired.
      expect(rejecting.sizes, [7, 6, 5, 4, 3, 2, 1]);
      expect(await store.loadWindModels(), isEmpty,
          reason: 'a retired name stays retired across reads');
      expect(ring.scheduled[todayRing], isNull,
          reason: 'nothing answered, so the occurrence has no reading');
    });
  });

  group('the home row dot (N15)', () {
    test('records the verdict and the time the CHECK ran', () async {
      api.sample = wind(5.0, 5.0);
      final at = alarmAt.subtract(const Duration(hours: 1));
      await engine.evaluateAlarm(alarm, [court], now: at);
      final f = (await engine.store.loadForecasts())[7]!;
      expect(f.willRing, isTrue);
      expect(f.checkedAt, at,
          reason: 'when the check ran — not the slot it read');
    });

    test('a failed fetch leaves the PREVIOUS verdict standing', () async {
      // The row shows the check time beside the verdict, so an unchanged
      // answer under an older timestamp is the honest signal. Overwriting it
      // with "not going to ring" would invent a wind reading nobody took.
      api.sample = wind(5.0, 5.0);
      final first = alarmAt.subtract(const Duration(hours: 2));
      await engine.evaluateAlarm(alarm, [court], now: first);

      api.fail = true;
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(hours: 1)));

      final f = (await engine.store.loadForecasts())[7]!;
      expect(f.willRing, isTrue);
      expect(f.checkedAt, first, reason: 'stale, and says so');
    });

    test('a windy occurrence records a NOT-going verdict', () async {
      api.sample = wind(20.0, 9.0);
      await engine.evaluateAlarm(alarm, [court],
          now: alarmAt.subtract(const Duration(hours: 1)));
      expect((await engine.store.loadForecasts())[7]!.willRing, isFalse);
    });
  });

  group('Checking… is for a check YOU started (2026-08-31)', () {
    late _GatedApi gated;
    late NivaatController c;

    /// A controller over a held-able API, already carrying one stored verdict
    /// — the state every case below is about. (A brand-new alarm has no
    /// verdict at all, which is why it was the only one that ever said
    /// `Checking…` before this.)
    Future<void> withAVerdict() async {
      gated = _GatedApi()..sample = wind(5.0, 5.0);
      c = NivaatController(
        engine: NivaatEngine(
          store: engine.store,
          scheduler: ring,
          api: gated,
          checks: checks,
          notifier: notifier,
        ),
      );
      await c.init();
      expect(c.forecasts[7], isNotNull, reason: 'precondition: an answer');
      expect(c.rechecking(7), isFalse);
    }

    test('opening the app re-checks WITHOUT withholding the answer', () async {
      // The passive half, and the reason this is a rule rather than a flag on
      // every check: `resync` runs on app open, on resume, when a ring stops
      // and when a background check pings the UI. Blanking the row to
      // `Checking…` on any of those would take the last answer off the screen
      // at the exact moment you came to read it.
      await withAVerdict();
      gated.hold = true;
      final open = c.resync();
      await gated.arrived();
      expect(c.rechecking(7), isFalse,
          reason: 'nothing you did started this one');
      gated.releaseAll();
      await open;
      expect(c.rechecking(7), isFalse);
    });

    test('switching the alarm back on withholds it until the answer lands',
        () async {
      // The active half — the case that started this (Samyak, 2026-08-31): the
      // verdict survives a toggle-off, so switching back on used to show
      // yesterday's answer under a new switch with no sign a fresh check was
      // even running.
      await withAVerdict();
      await c.toggleAlarm(7, false);
      await c.lastEvaluation;

      gated.hold = true;
      await c.toggleAlarm(7, true);
      await gated.arrived();
      expect(c.rechecking(7), isTrue);
      // The stored verdict is untouched — this withholds it, it does not throw
      // it away, so a fetch that fails leaves the old answer to come back to.
      expect((await engine.store.loadForecasts())[7], isNotNull);

      gated.releaseAll();
      await c.lastEvaluation;
      expect(c.rechecking(7), isFalse);
    });

    test('a fetch that throws still takes the word down', () async {
      // Otherwise the row is stranded on a sentence nothing will ever answer.
      await withAVerdict();
      gated.fail = true;
      await c.toggleAlarm(7, true);
      await c.lastEvaluation;
      expect(c.rechecking(7), isFalse);
    });

    test('a save that THROWS takes the cue down, and repaints', () async {
      // The other end of the same rule. This throw lands before `_saveAlarm`
      // ever notifies, so it looks at first as though the word cannot be on
      // screen yet — but the row reads `rechecking` at build time, and the
      // home rebuilds on its own while a save is in flight (the minute ticker
      // alone does, every wall-clock :00). Clearing the mark without a frame
      // would leave `Checking…` up until the next rebuild from anywhere.
      await withAVerdict();
      final boom = NivaatController(
        engine: _BoomOnSave(
          store: engine.store,
          scheduler: ring,
          api: gated,
          checks: checks,
          notifier: notifier,
        ),
      );
      await boom.init();
      var frames = 0;
      boom.addListener(() => frames++);

      await expectLater(
          boom.toggleAlarm(7, true), throwsA(isA<OpenMeteoException>()));
      expect(boom.rechecking(7), isFalse, reason: 'no check is coming');
      expect(frames, greaterThan(0),
          reason: 'the mark came down, so the row has to be told');
    });

    test('two overlapping checks: the first to finish does not clear the cue',
        () async {
      // Off-then-straight-back-on starts two evaluations. Counted rather than
      // flagged for exactly this: the first one finishing must not take down
      // the cue the second is still earning.
      // They never fetch at the same instant — the engine runs one pass per
      // alarm at a time — but the second save is made and marked while the
      // first check is still out, and it is still owed when that one lands.
      // A flag would be taken down there, mid-check, by the wrong evaluation.
      //
      // Both saves here are EDITS, so this also carries the editor's half of
      // the rule: every save goes through `upsertAlarm`, and a wind limit you
      // just changed is being judged against a reading taken under the old one
      // until the mark clears.
      await withAVerdict();
      gated.hold = true;
      await c.upsertAlarm(c.alarms.single.copyWith(courtSpeedLimitKmh: 9));
      await gated.arrived();
      final first = c.lastEvaluation!;

      // NOT awaited: the second save cannot get past the engine's lane while
      // the first check is parked on the gate. That is the whole scenario —
      // the save has been made, so its mark is already there (it is the first
      // thing `upsertAlarm` does), and the save itself is still waiting.
      final again =
          c.upsertAlarm(c.alarms.single.copyWith(courtSpeedLimitKmh: 10));
      expect(c.rechecking(7), isTrue, reason: 'both saves');

      gated.releaseAll();
      await first;
      expect(c.rechecking(7), isTrue,
          reason: "the first check's answer must not take down the second's "
              'cue — a flag here would leave the row showing a verdict the '
              'check still running is about to replace');

      await again;
      await c.lastEvaluation;
      expect(c.rechecking(7), isFalse);
    });
  });
}

/// [FakeApi] that can be held mid-fetch, so a test can look at the app while a
/// check is genuinely in flight rather than inferring it afterwards.
///
/// One gate, shared by whatever parks on it. Nothing here releases fetches
/// separately, and sharing is what makes a second arrival harmless: a
/// completer per call would need every one of them completed, and one left
/// behind is a thirty-second timeout with nothing to read.
class _GatedApi extends FakeApi {
  /// Hold every call from here on. Off by default so setup can fetch freely.
  bool hold = false;

  Completer<void>? _gate;

  /// Waits until a call is parked. Every fetch reaches the gate through
  /// database work first, so "the check has started" is only true once the
  /// call actually arrives — asserting before that is a race.
  Future<void> arrived() async {
    while (_gate == null) {
      await pumpEventQueue();
    }
  }

  void releaseAll() {
    hold = false;
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<List<WindSample>> windWindow(
    double lat,
    double lon,
    DateTime from,
    DateTime to, {
    List<String> models = OpenMeteo.defaultWindModels,
  }) async {
    if (hold) await (_gate ??= Completer<void>()).future;
    return super.windWindow(lat, lon, from, to, models: models);
  }
}

/// Refuses exactly one model name the way Open-Meteo does — a hard failure of
/// the WHOLE request, naming the offender — then answers normally.
/// Open-Meteo with some model names retired.
///
/// Takes a SET rather than one name (2026-08-30) because the number retired
/// at once is exactly what `_windowFor`'s loop bound gets wrong — one name is
/// the case that always worked.
class _RejectsModels extends FakeApi {
  _RejectsModels(this.bad, WindSample s) {
    sample = s;
  }

  final Set<String> bad;
  int calls = 0;

  /// How many models each request asked for, in order — the shape of the
  /// drain. A raw call COUNT is not safe to assert on here: a pass can roll on
  /// into the next occurrence and fetch again, and that second pass is not
  /// awaited by `evaluateAlarm`, so the count at assertion time is a race. The
  /// first drain's prefix is not.
  final List<int> sizes = [];

  @override
  Future<List<WindSample>> windWindow(
    double lat,
    double lon,
    DateTime from,
    DateTime to, {
    List<String> models = OpenMeteo.defaultWindModels,
  }) {
    calls++;
    sizes.add(models.length);
    // One offender per refusal, exactly as the real 400 body names one — so
    // the caller has to come back for each, which is the whole point.
    final dead = models.where(bad.contains);
    if (dead.isNotEmpty) throw OpenMeteoUnknownModel(dead.first);
    return super.windWindow(lat, lon, from, to, models: models);
  }
}

/// An engine whose save-side work fails. `retainInFlightEdits` is the half a
/// toggle on an already-enabled alarm takes, and it stands in for the whole
/// class (a write that will not land, a plugin that refuses): all that matters
/// is that `upsertAlarm` throws AFTER marking the row.
class _BoomOnSave extends NivaatEngine {
  _BoomOnSave({
    required super.store,
    required super.scheduler,
    required super.api,
    required super.checks,
    required super.notifier,
  });

  @override
  Future<void> retainInFlightEdits(
    NivaatAlarm previous,
    NivaatAlarm next, {
    DateTime? now,
  }) async =>
      throw OpenMeteoException('save failed');
}
