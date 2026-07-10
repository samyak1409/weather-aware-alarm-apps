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

    test('gust floor: threshold 1 keeps gust limit at 12 raw', () {
      const t = WindThresholds(courtSpeedLimitKmh: 1);
      expect(t.rawGustLimit, 12.0);
    });

    test('API 10m wind converts to court level at x0.6', () {
      expect(sample(10, 0).courtSpeedKmh, closeTo(6.0, 0.001));
    });
  });

  group('volume ramp (100% at calm -> 50% floor at threshold)', () {
    const t = WindThresholds(courtSpeedLimitKmh: 4);
    test('calm = full volume', () => expect(volumeForWind(0, t), 1.0));
    test('half threshold = 75%', () => expect(volumeForWind(2, t), 0.75));
    test('at threshold = 50% floor', () => expect(volumeForWind(4, t), 0.5));
  });

  group('decide — the chat example table (threshold 4)', () {
    const t = WindThresholds(courtSpeedLimitKmh: 4);

    test('calm morning: court 3, gusts 5 raw -> ring at ~63%', () {
      final d = decide(sample(5.0, 5.0), t); // court = 3.0
      expect(d.verdict, WindVerdict.ring);
      expect(d.volume, closeTo(0.625, 0.001));
    });

    test('sneaky morning: court 3 but gusts 15 raw -> skip (gusty)', () {
      final d = decide(sample(5.0, 15.0), t);
      expect(d.verdict, WindVerdict.tooGusty);
      expect(d.shouldRing, isFalse);
    });

    test('windy morning: court 5 -> skip regardless of gusts', () {
      final d = decide(sample(8.4, 7.0), t); // court = 5.04
      expect(d.verdict, WindVerdict.tooWindy);
    });
  });

  group('check cascade', () {
    final alarmAt = DateTime(2026, 7, 12, 6, 0);

    test('walks the ladder from T-12h', () {
      var now = DateTime(2026, 7, 11, 17, 0);
      final points = <DateTime>[];
      while (true) {
        final next = CheckCascade.nextCheckTime(now, alarmAt,
            hadSuccessfulCheck: true);
        if (next == null || points.length > 20) break;
        points.add(next);
        now = next;
      }
      expect(points.first, DateTime(2026, 7, 11, 18, 0)); // T-12h
      expect(points, contains(DateTime(2026, 7, 12, 5, 30))); // T-30m
      expect(points, contains(DateTime(2026, 7, 12, 5, 59))); // T-1m
      expect(points.last, alarmAt); // T-0
      expect(points.length, CheckCascade.ladderMinutesBefore.length);
    });

    test('after T-0 with a successful check: cascade ends', () {
      expect(
        CheckCascade.nextCheckTime(alarmAt, alarmAt, hadSuccessfulCheck: true),
        isNull,
      );
    });

    test('after T-0 with NO successful check: retries 1/min, capped +30m', () {
      final first = CheckCascade.nextCheckTime(alarmAt, alarmAt,
          hadSuccessfulCheck: false);
      expect(first, alarmAt.add(const Duration(minutes: 1)));

      final nearCap = CheckCascade.nextCheckTime(
          alarmAt.add(const Duration(minutes: 29)), alarmAt,
          hadSuccessfulCheck: false);
      expect(nearCap, alarmAt.add(const Duration(minutes: 30)));

      final past = CheckCascade.nextCheckTime(
          alarmAt.add(const Duration(minutes: 30)), alarmAt,
          hadSuccessfulCheck: false);
      expect(past, isNull);
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
