import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SleepPlan.compute (Samyak midpoint-minus-8h rule)', () {
    test('Jaipur-like wake 05:32-07:17 gives bedtime ~22:25, sleep 7.1-8.9h',
        () {
      final r = SleepPlan.compute(
        earliestWakeMinutes: 5 * 60 + 32,
        latestWakeMinutes: 7 * 60 + 17,
      );
      // Verified against real data: bedtime 22:25, avg sleep 7.96h.
      expect(r.bedtimeMinutes, closeTo(22 * 60 + 24.5, 1));
      expect(r.minSleepMinutes / 60, closeTo(7.12, 0.05));
      expect(r.maxSleepMinutes / 60, closeTo(8.87, 0.05));
      expect(r.feasible, isTrue);
    });

    test('with avg=8 and clamp [7,9], midpoint bedtime is always in-window '
        'whenever a window exists (symmetry)', () {
      final r = SleepPlan.compute(
        earliestWakeMinutes: 5 * 60,
        latestWakeMinutes: 7 * 60, // swing exactly 2h = clamp width
      );
      expect(r.feasible, isTrue);
      expect(r.minSleepMinutes / 60, closeTo(7.0, 0.01));
      expect(r.maxSleepMinutes / 60, closeTo(9.0, 0.01));
    });

    test('London-like swing >2h is infeasible; compromise splits the excess',
        () {
      final r = SleepPlan.compute(
        earliestWakeMinutes: 4 * 60, // 04:00
        latestWakeMinutes: 8 * 60, // 08:00, swing 4h
      );
      expect(r.feasible, isFalse);
      // Compromise = midpoint - 8h = 22:00; violations split evenly.
      expect(r.bedtimeMinutes, closeTo(22 * 60, 1));
      expect(r.minSleepMinutes / 60, closeTo(6.0, 0.01));
      expect(r.maxSleepMinutes / 60, closeTo(10.0, 0.01));
    });
  });

  group('SleepPlan.forLocation end-to-end', () {
    test('Tonk with +0 offset: bedtime ~22:07, sleep within clamp', () {
      final r = SleepPlan.forLocation(
        year: 2026,
        latDeg: 26.17,
        lonDeg: 75.79,
        wakeOffsetMinutes: 0,
        utcOffsetMinutes: 330,
      )!;
      // Dawn 05:08-06:51 -> midpoint 05:59.5 -> bedtime 21:59.5.
      expect(r.bedtimeMinutes, closeTo(21 * 60 + 59.5, 3));
      expect(r.feasible, isTrue);
      expect(r.minSleepMinutes / 60, greaterThanOrEqualTo(7.0));
      expect(r.maxSleepMinutes / 60, lessThanOrEqualTo(9.0));
    });

    test('wake offset shifts bedtime by the same amount', () {
      final base = SleepPlan.forLocation(
          year: 2026,
          latDeg: 26.17,
          lonDeg: 75.79,
          wakeOffsetMinutes: 0,
          utcOffsetMinutes: 330)!;
      final shifted = SleepPlan.forLocation(
          year: 2026,
          latDeg: 26.17,
          lonDeg: 75.79,
          wakeOffsetMinutes: 120,
          utcOffsetMinutes: 330)!;
      expect(shifted.bedtimeMinutes - base.bedtimeMinutes, closeTo(120, 0.5));
    });
  });
}
