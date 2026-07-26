import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

WindSample sample(double rawSpeed, double rawGust) => WindSample(
      rawSpeedKmh: rawSpeed,
      rawGustKmh: rawGust,
      observedAt: DateTime(2026, 7, 11, 6),
      isForecast: false,
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

  group('decide — whole-km/h decision (threshold 4)', () {
    const t = WindThresholds(courtSpeedLimitKmh: 4); // raw gust limit 14.667

    test('calm morning: court 3, gusts 5 raw -> ring at 85%', () {
      final d = decide(sample(5.0, 5.0), t); // court 3.0 = 3L/4 exactly
      expect(d.verdict, WindVerdict.ring);
      expect(d.volume, 0.85);
    });

    test('sneaky morning: court 3 but gusts 16 raw -> skip (gusty)', () {
      final d = decide(sample(5.0, 16.0), t); // gust 16 > round(14.667)=15
      expect(d.verdict, WindVerdict.tooGusty);
      expect(d.shouldRing, isFalse);
    });

    test('windy morning: court 5 -> skip regardless of gusts', () {
      final d = decide(sample(8.4, 7.0), t); // court = 5.04 -> rounds to 5
      expect(d.verdict, WindVerdict.tooWindy);
    });

    // The whole-km/h boundaries: decision rounds the same way the UI shows,
    // so a displayed number can never contradict its cap.
    test('wind rounds: court 4.4 rings, court 4.5 skips', () {
      expect(decide(sample(7.33, 5.0), t).verdict, // court 4.398 -> 4 ≤ 4
          WindVerdict.ring);
      expect(decide(sample(7.5, 5.0), t).verdict, // court 4.5 -> 5 > 4
          WindVerdict.tooWindy);
    });

    test('gust rounds: 15 (=guard) rings, 16 skips', () {
      // 15 rounds to 15, guard 14.667 rounds to 15 → 15 > 15 is false → ring.
      expect(decide(sample(5.0, 15.0), t).verdict, WindVerdict.ring);
      expect(decide(sample(5.0, 16.0), t).verdict, WindVerdict.tooGusty);
    });
  });

  group('check cascade', () {
    final alarmAt = DateTime(2026, 7, 12, 6, 0);

    test('ladder is T-1h down to T-0 (8 rungs, far pre-arms dropped)', () {
      var now = DateTime(2026, 7, 12, 4, 0); // before the first rung (T-1h)
      final points = <DateTime>[];
      for (var i = 0; i < CheckCascade.ladderMinutesBefore.length; i++) {
        final next = CheckCascade.nextCheckTime(now, alarmAt)!;
        points.add(next);
        now = next;
      }
      expect(points.first, DateTime(2026, 7, 12, 5, 0)); // T-1h
      expect(points, contains(DateTime(2026, 7, 12, 5, 50))); // T-10m
      expect(points, contains(DateTime(2026, 7, 12, 5, 59))); // T-1m
      expect(points.last, alarmAt); // T-0
      expect(points.length, CheckCascade.ladderMinutesBefore.length);
    });

    test('after T-0: retries every minute, capped at +30m (for any skip)', () {
      final first = CheckCascade.nextCheckTime(alarmAt, alarmAt);
      expect(first, alarmAt.add(const Duration(minutes: 1)));

      final nearCap = CheckCascade.nextCheckTime(
          alarmAt.add(const Duration(minutes: 29)), alarmAt);
      expect(nearCap, alarmAt.add(const Duration(minutes: 30)));

      final past = CheckCascade.nextCheckTime(
          alarmAt.add(const Duration(minutes: 30)), alarmAt);
      expect(past, isNull);
    });

    test('per-alarm retryCapMinutes: 1-min and 60-min windows', () {
      // 1-min: one post-T retry at T+1, then over.
      expect(
        CheckCascade.nextCheckTime(alarmAt, alarmAt, retryCapMinutes: 1),
        alarmAt.add(const Duration(minutes: 1)),
      );
      expect(
        CheckCascade.nextCheckTime(
          alarmAt.add(const Duration(minutes: 1)),
          alarmAt,
          retryCapMinutes: 1,
        ),
        isNull,
      );
      // 60-min: still booking near the end of the hour.
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
}
