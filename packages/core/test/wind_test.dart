import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

WindSample sample(double rawSpeed, double rawGust, [DateTime? slotAt]) =>
    WindSample(
      rawSpeedKmh: rawSpeed,
      rawGustKmh: rawGust,
      slotAt: slotAt ?? DateTime(2026, 7, 11, 6),
    );

void main() {
  group('thresholds and conversion', () {
    test('court threshold 4 -> raw speed limit 6.67, raw gust limit 14.67',
        () {
      const t = WindThresholds(courtSpeedLimitKmh: 4);
      expect(t.rawSpeedLimit, closeTo(6.667, 0.01));
      expect(t.rawGustLimit, closeTo(14.667, 0.01));
    });

    test('gust limit is exactly 2.2x the raw speed limit — no floor', () {
      expect(const WindThresholds(courtSpeedLimitKmh: 5).rawGustLimit,
          closeTo(2.2 * 5 / 0.6, 0.01)); // 18.33, not a floored 12
      expect(const WindThresholds(courtSpeedLimitKmh: 6).rawGustLimit,
          closeTo(22.0, 0.01));
    });

    test('offered range is 4-6 (sub-4 dropped with the gust floor)', () {
      expect(WindThresholds.minLimit, 4);
      expect(WindThresholds.maxLimit, 6);
      expect(WindThresholds.defaultLimit, 6);
    });

    test('API 10m wind converts to court level at x0.6', () {
      expect(sample(10, 0).courtSpeedKmh, closeTo(6.0, 0.001));
    });
  });

  group('volume ramp — three steps, snapped at a quarter and three quarters',
      () {
    const t4 = WindThresholds(courtSpeedLimitKmh: 4);
    test('calm = full volume', () => expect(volumeForWind(0, t4), 1.0));
    test('100% holds to L/4 inclusive', () {
      expect(volumeForWind(0.99, t4), 1.0);
      expect(volumeForWind(1, t4), 1.0, reason: 'the edge belongs to the louder step');
    });
    test('85% from just past L/4 to 3L/4 inclusive', () {
      expect(volumeForWind(1.01, t4), 0.85);
      expect(volumeForWind(2, t4), 0.85);
      expect(volumeForWind(3, t4), 0.85, reason: '3L/4 is still the middle step');
    });
    test('70% floor above 3L/4', () {
      expect(volumeForWind(3.01, t4), 0.70);
      expect(volumeForWind(4, t4), 0.70);
    });
    test('over the limit still clamps to the floor, never below', () {
      // decide() skips before this is reached, but a lone call must not
      // return a negative or sub-floor volume.
      expect(volumeForWind(99, t4), 0.70);
    });

    test('windVolumeSteps is strictly descending — snapping depends on it', () {
      // Nivaat's asset picker walks these loudest-first and takes the first
      // step whose midpoint the volume clears. Reorder them and every ring
      // silently picks the wrong file.
      for (var i = 0; i < windVolumeSteps.length - 1; i++) {
        expect(windVolumeSteps[i], greaterThan(windVolumeSteps[i + 1]),
            reason: 'step $i must be louder than step ${i + 1}');
      }
      expect(windVolumeSteps.first, 1.0, reason: 'dead calm is full volume');
    });

    test('every limit snaps on its own quarters, no float slip', () {
      // The boundaries are quarters of a whole limit, so they are exact in
      // binary — but only because the comparison multiplies instead of
      // dividing. c/limit <= 0.25 can miss its own edge.
      for (final (limit, lo, hi) in [(6, 1.5, 4.5), (5, 1.25, 3.75), (4, 1.0, 3.0)]) {
        final t = WindThresholds(courtSpeedLimitKmh: limit);
        expect(volumeForWind(lo, t), 1.0, reason: 'limit $limit at L/4');
        expect(volumeForWind(lo + 0.01, t), 0.85, reason: 'limit $limit past L/4');
        expect(volumeForWind(hi, t), 0.85, reason: 'limit $limit at 3L/4');
        expect(volumeForWind(hi + 0.01, t), 0.70, reason: 'limit $limit past 3L/4');
      }
    });

    test('every limit uses all three steps and nothing else', () {
      for (var limit = WindThresholds.minLimit;
          limit <= WindThresholds.maxLimit;
          limit++) {
        final t = WindThresholds(courtSpeedLimitKmh: limit);
        final seen = <double>{};
        for (var tenths = 0; tenths <= limit * 10; tenths++) {
          seen.add(volumeForWind(tenths / 10, t));
        }
        expect(seen, windVolumeSteps.toSet(),
            reason: 'limit $limit must reach every step, and invent none');
      }
    });
  });

  group('decideSlot — whole-km/h decision (threshold 4)', () {
    const t = WindThresholds(courtSpeedLimitKmh: 4); // raw gust limit 14.667

    test('calm slot: court 3, gusts 5 raw -> ring at 85%', () {
      final d = decideSlot(sample(5.0, 5.0), t); // court 3.0 = 3L/4 exactly
      expect(d.verdict, WindVerdict.ring);
      expect(d.volume, 0.85);
    });

    test('sneaky slot: court 3 but gusts 16 raw -> skip (gusty)', () {
      final d = decideSlot(sample(5.0, 16.0), t); // gust 16 > round(14.667)=15
      expect(d.verdict, WindVerdict.tooGusty);
      expect(d.shouldRing, isFalse);
    });

    test('windy slot: court 5 -> skip regardless of gusts', () {
      final d = decideSlot(sample(8.4, 7.0), t); // court = 5.04 -> rounds to 5
      expect(d.verdict, WindVerdict.tooWindy);
    });

    // The whole-km/h boundaries: decision rounds the same way the UI shows,
    // so a displayed number can never contradict its cap.
    test('wind rounds: court 4.4 rings, court 4.5 skips', () {
      expect(decideSlot(sample(7.33, 5.0), t).verdict, // court 4.398 -> 4 ≤ 4
          WindVerdict.ring);
      expect(decideSlot(sample(7.5, 5.0), t).verdict, // court 4.5 -> 5 > 4
          WindVerdict.tooWindy);
    });

    test('gust rounds: 15 (=guard) rings, 16 skips', () {
      // 15 rounds to 15, guard 14.667 rounds to 15 → 15 > 15 is false → ring.
      expect(decideSlot(sample(5.0, 15.0), t).verdict, WindVerdict.ring);
      expect(decideSlot(sample(5.0, 16.0), t).verdict, WindVerdict.tooGusty);
    });
  });

  group('check cascade', () {
    final alarmAt = DateTime(2026, 7, 12, 6, 0);

    test('ladder is T-24h down to T-0, 9 rungs, never closer than 15 min', () {
      var now = alarmAt.subtract(const Duration(days: 2));
      final points = <DateTime>[];
      for (var i = 0; i < CheckCascade.ladderMinutesBefore.length; i++) {
        final next = CheckCascade.nextCheckTime(now, alarmAt)!;
        points.add(next);
        now = next;
      }
      expect(points.first, DateTime(2026, 7, 11, 6, 0)); // T-24h
      expect(points, contains(DateTime(2026, 7, 12, 5, 0))); // T-1h
      expect(points, contains(DateTime(2026, 7, 12, 5, 45))); // T-15m
      expect(points.last, alarmAt); // T-0
      expect(points.length, 9);

      // **The gaps are the point.** Doze throttles `allowWhileIdle` wakeups to
      // roughly one per nine minutes off charger, so the old T-10/-5/-2/-1/T-0
      // cluster spent five tickets inside one quota window and the OS threw
      // about four of them away. Nothing here is closer than 15 minutes.
      for (var i = 1; i < points.length; i++) {
        expect(points[i].difference(points[i - 1]).inMinutes,
            greaterThanOrEqualTo(15),
            reason: 'rung $i lands inside Doze\'s quota window');
      }
    });

    test('after T-0: retries every 15 min on T\'s own grid, capped at +30m',
        () {
      // Every 15 minutes because that is the grid the wind data itself moves
      // on — a retry a minute later would re-read the identical slot and could
      // only reach the identical verdict.
      expect(CheckCascade.nextCheckTime(alarmAt, alarmAt),
          alarmAt.add(const Duration(minutes: 15)));

      // Anchored to T, not to `now`: a wake that arrives late still lands on
      // the next real slot rather than 15 minutes after whenever it woke.
      expect(
        CheckCascade.nextCheckTime(
            alarmAt.add(const Duration(minutes: 7)), alarmAt),
        alarmAt.add(const Duration(minutes: 15)),
      );
      expect(
        CheckCascade.nextCheckTime(
            alarmAt.add(const Duration(minutes: 16)), alarmAt),
        alarmAt.add(const Duration(minutes: 30)),
      );
      expect(
        CheckCascade.nextCheckTime(
            alarmAt.add(const Duration(minutes: 30)), alarmAt),
        isNull,
      );
    });

    test('per-alarm retryCapMinutes: 15-min and 60-min windows', () {
      // 15-min (the dev window): exactly one post-T retry, at the cap.
      expect(
        CheckCascade.nextCheckTime(alarmAt, alarmAt, retryCapMinutes: 15),
        alarmAt.add(const Duration(minutes: 15)),
      );
      expect(
        CheckCascade.nextCheckTime(
          alarmAt.add(const Duration(minutes: 15)),
          alarmAt,
          retryCapMinutes: 15,
        ),
        isNull,
      );
      // 60-min: four retries, and still booking near the end of the hour.
      expect(
        CheckCascade.nextCheckTime(
          alarmAt.add(const Duration(minutes: 31)),
          alarmAt,
          retryCapMinutes: 60,
        ),
        alarmAt.add(const Duration(minutes: 45)),
      );
      expect(
        CheckCascade.nextCheckTime(
          alarmAt.add(const Duration(minutes: 59)),
          alarmAt,
          retryCapMinutes: 60,
        ),
        alarmAt.add(const Duration(minutes: 60)),
      );
      expect(
        CheckCascade.nextCheckTime(
          alarmAt.add(const Duration(minutes: 60)),
          alarmAt,
          retryCapMinutes: 60,
        ),
        isNull,
      );
    });

    test('inside the last minute: books the cap, never finalises early', () {
      // Old rule (`next.isAfter(cap) ? null`) killed a 1-min window on any
      // evaluate between T and T+1, and the last minute of a 30-min window on
      // an off-minute wake.
      expect(
        CheckCascade.nextCheckTime(
          alarmAt.add(const Duration(seconds: 5)),
          alarmAt,
          retryCapMinutes: 1,
        ),
        alarmAt.add(const Duration(minutes: 1)),
        reason: '1-min window must survive a T+5s resync',
      );
      expect(
        CheckCascade.nextCheckTime(
          alarmAt.add(const Duration(minutes: 29, seconds: 30)),
          alarmAt,
        ),
        alarmAt.add(const Duration(minutes: 30)),
        reason: 'last half-minute of the default window books the cap',
      );
    });

    group('which Keep-checking options the editor may show', () {
      // 15m plays a whole occurrence out inside an hour, which is a testing
      // tool and not a choice to put in front of a user — behind the seven-tap
      // gate since 2026-08-06, at 1m until 2026-08-25. The cascade honours
      // whatever is stored, so an alarm saved at 15 keeps working with the gate
      // shut.
      test('30 and 60, plus 15 for dev mode or for an alarm already on it',
          () {
        List<int> keepChecking({required bool devMode, required int selected}) =>
            minuteOptionsFor(
                base: CheckCascade.retryMinutesOptions,
                devMode: devMode,
                selected: selected);
        expect(keepChecking(devMode: false, selected: 30), [30, 60]);
        // The gate decides what is OFFERED, never what already works: an alarm
        // saved at 15m keeps showing 15m after the gate closes, or the control
        // would draw with nothing selected and misrepresent the alarm.
        expect(keepChecking(devMode: true, selected: 30), [15, 30, 60]);
        expect(keepChecking(devMode: false, selected: 15), [15, 30, 60]);
      });

      test('15 is the floor, because a shorter window holds no retry at all',
          () {
        // It was 1 until 2026-08-25. Retries land every `retryStepMinutes`, so
        // a one-minute window contains none and would test nothing.
        expect(kDevMinutesOption, 15);
        expect(kDevMinutesOption, CheckCascade.retryStepMinutes);
      });

      test('every minutes row in the editor offers the same dev extra', () {
        // It was Keep checking's alone until 2026-08-25, which made a test
        // occurrence half-fast: the retry window shrank to a quarter hour while
        // the play window it was retrying stayed half an hour out and half an
        // hour long. `minuteOptionsFor` is now the only place the gate is read,
        // so the three rows cannot drift apart.
        for (final base in [
          CheckCascade.retryMinutesOptions,
          NivaatAlarm.timeUntilPlayOptions,
          NivaatAlarm.minPlayOptions,
        ]) {
          expect(
              minuteOptionsFor(base: base, devMode: false, selected: 30), base);
          expect(minuteOptionsFor(base: base, devMode: true, selected: 30),
              [kDevMinutesOption, ...base]);
        }
      });

      test('always ascending, and never a duplicate', () {
        // The editor renders one segment per option in list order, so this is
        // what puts "1m 30m 60m" on screen in that order.
        for (final dev in [false, true]) {
          for (final selected in [1, 30, 60, 45]) {
            final options = minuteOptionsFor(
                base: CheckCascade.retryMinutesOptions,
                devMode: dev,
                selected: selected);
            expect(options, orderedEquals(List.of(options)..sort()),
                reason: 'dev=$dev selected=$selected must be ascending');
            expect(options.toSet().length, options.length,
                reason: 'dev=$dev selected=$selected has a repeat');
            expect(options, contains(selected),
                reason: 'the selected value must have a segment to sit on');
          }
        }
      });
    });
  });

  group('NivaatAlarm.nextOccurrence', () {
    test('respects weekday selection', () {
      const alarm = NivaatAlarm(
        id: 1,
        hour: 6,
        minute: 0,
        courtId: 'c1',
        weekdays: {DateTime.monday},
      );
      // 2026-07-11 is a Saturday; next Monday is 13 Jul.
      final next = alarm.nextOccurrence(DateTime(2026, 7, 11, 12, 0));
      expect(next, DateTime(2026, 7, 13, 6, 0));
    });

    test('same-day occurrence when time is still ahead', () {
      const alarm = NivaatAlarm(id: 1, hour: 23, minute: 30, courtId: 'c1');
      final next = alarm.nextOccurrence(DateTime(2026, 7, 11, 12, 0));
      expect(next, DateTime(2026, 7, 11, 23, 30));
    });
  });

  group('decide — the whole play window (threshold 4)', () {
    const t = WindThresholds(courtSpeedLimitKmh: 4);
    final at = DateTime(2026, 7, 12, 6, 30);
    DateTime slot(int i) => at.add(Duration(minutes: 15 * i));

    test('every slot calm -> rings', () {
      final d = decide([
        sample(5.0, 5.0, slot(0)),
        sample(5.0, 5.0, slot(1)),
        sample(5.0, 5.0, slot(2)),
      ], t);
      expect(d.verdict, WindVerdict.ring);
    });

    test('ONE bad slot in the middle skips the whole occurrence', () {
      // The flaw this rule fixes: the old check looked at a single instant, so
      // a calm arrival followed by a windy game read as playable.
      final d = decide([
        sample(5.0, 5.0, slot(0)),
        sample(12.0, 7.0, slot(1)), // court 7.2 -> too windy
        sample(5.0, 5.0, slot(2)),
      ], t);
      expect(d.verdict, WindVerdict.tooWindy);
      expect(d.shouldRing, isFalse);
    });

    test('the reported slot is the one that FAILED, so the card can name it',
        () {
      final d = decide([
        sample(5.0, 5.0, slot(0)),
        sample(12.0, 7.0, slot(1)),
        sample(5.0, 5.0, slot(2)),
      ], t);
      expect(d.sample.slotAt, slot(1));
    });

    test('windy outranks gusty, matching decideSlot own precedence', () {
      // decideSlot tests speed before gusts, so a window holding one of each
      // must report windy — or the card would name a reason its own per-slot
      // rule would not have chosen.
      final d = decide([
        sample(5.0, 16.0, slot(0)), // gusty
        sample(12.0, 5.0, slot(1)), // windy
      ], t);
      expect(d.verdict, WindVerdict.tooWindy);
      expect(d.sample.slotAt, slot(1));
    });

    test('among equally-bad slots the windiest is reported', () {
      final d = decide([
        sample(12.0, 5.0, slot(0)),
        sample(20.0, 5.0, slot(1)),
        sample(15.0, 5.0, slot(2)),
      ], t);
      expect(d.sample.slotAt, slot(1));
    });

    test('a ringing window takes its VOLUME from the windiest slot', () {
      // One rule for verdict and loudness, so the ramp can never disagree with
      // the decision that produced it. Court 0.6 alone would ring at 100%;
      // the 3.0 slot is the one you will actually be playing in.
      final loud = decide([sample(1.0, 5.0, slot(0))], t);
      expect(loud.volume, 1.0);
      final d = decide([
        sample(1.0, 5.0, slot(0)), // court 0.6
        sample(5.0, 5.0, slot(1)), // court 3.0 -> 85%
      ], t);
      expect(d.verdict, WindVerdict.ring);
      expect(d.volume, 0.85, reason: 'the worst slot sets the ramp');
      expect(d.sample.slotAt, slot(1));
    });

    test('a single-slot window decides exactly as one sample did', () {
      // Keeps every pre-window fixture meaningful: a flat window is the old
      // behaviour, so nothing that used to ring stops ringing by itself.
      for (final pair in [(5.0, 5.0), (5.0, 16.0), (8.4, 7.0)]) {
        expect(decide([sample(pair.$1, pair.$2)], t).verdict,
            decideSlot(sample(pair.$1, pair.$2), t).verdict);
      }
    });
  });
}
