import 'solar.dart';

/// Computes the fixed bedtime for Arunoday.
///
/// Rule locked in SPEC.md: bedtime = midpoint(earliest yearly wake, latest
/// yearly wake) - 8h, then clamped so nightly sleep always stays within
/// [minSleepHours, maxSleepHours]. Wake = civil dawn + user offset.
class SleepPlan {
  SleepPlan._();

  static const double avgSleepHours = 8.0;
  static const double minSleepHours = 7.0;
  static const double maxSleepHours = 9.0;

  /// [earliestWakeMinutes]/[latestWakeMinutes] are minutes-after-midnight of
  /// the earliest and latest wake time across the year (dawn + offset).
  ///
  /// Returns bedtime as minutes-after-midnight (e.g. 1345 = 22:25) plus the
  /// resulting sleep range. `feasible` is false when no fixed bedtime can
  /// satisfy the clamp (only happens at high latitudes); in that case the
  /// closest compromise is returned.
  static SleepPlanResult compute({
    required double earliestWakeMinutes,
    required double latestWakeMinutes,
  }) {
    final mid = (earliestWakeMinutes + latestWakeMinutes) / 2.0;
    var bedtime = mid + 1440.0 - avgSleepHours * 60.0;

    // Sleep on a given day = wake + 1440 - bedtime.
    // Clamp window keeping sleep within [min, max] for every day:
    final lowest = latestWakeMinutes + 1440.0 - maxSleepHours * 60.0;
    final highest = earliestWakeMinutes + 1440.0 - minSleepHours * 60.0;

    var feasible = true;
    if (lowest > highest) {
      feasible = false;
      bedtime = (lowest + highest) / 2.0;
    } else {
      bedtime = bedtime.clamp(lowest, highest);
    }
    bedtime %= 1440.0;

    double sleepFor(double wake) => (wake + 1440.0 - bedtime) % 1440.0;
    return SleepPlanResult(
      bedtimeMinutes: bedtime,
      minSleepMinutes: sleepFor(earliestWakeMinutes),
      maxSleepMinutes: sleepFor(latestWakeMinutes),
      feasible: feasible,
    );
  }

  /// Convenience: full computation from a location + wake offset.
  /// Returns null in polar edge cases where dawn is undefined all year.
  static SleepPlanResult? forLocation({
    required int year,
    required double latDeg,
    required double lonDeg,
    required int wakeOffsetMinutes,
    int? utcOffsetMinutes,
  }) {
    final extremes = Solar.yearlyDawnExtremes(year, latDeg, lonDeg,
        utcOffsetMinutes: utcOffsetMinutes);
    if (extremes == null) return null;
    return compute(
      earliestWakeMinutes:
          (extremes.earliestMinutes + wakeOffsetMinutes) % 1440.0,
      latestWakeMinutes: (extremes.latestMinutes + wakeOffsetMinutes) % 1440.0,
    );
  }
}

class SleepPlanResult {
  const SleepPlanResult({
    required this.bedtimeMinutes,
    required this.minSleepMinutes,
    required this.maxSleepMinutes,
    required this.feasible,
  });

  /// Fixed bedtime, minutes after local midnight.
  final double bedtimeMinutes;

  /// Shortest night of the year (summer), in minutes.
  final double minSleepMinutes;

  /// Longest night of the year (winter), in minutes.
  final double maxSleepMinutes;

  final bool feasible;
}
