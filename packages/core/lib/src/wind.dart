import 'dart:math' as math;

/// Wind decision engine for Nivaat. All rules locked in SPEC.md and derived
/// from real Open-Meteo data for Tonk and Bengaluru (2026-07-11 research).

/// Weather APIs report wind at 10 m height; at court level (~2 m) wind is
/// ~40% weaker (log wind profile over open/suburban terrain).
const double apiToCourtFactor = 0.6;

class WindThresholds {
  const WindThresholds({required this.courtSpeedLimitKmh});

  /// User-facing dropdown value, 1-6 km/h, semantic = wind felt at the court.
  final int courtSpeedLimitKmh;

  static const int minLimit = 1;
  static const int maxLimit = 6;
  static const int defaultLimit = 4;

  /// The 10 m API speed corresponding to the court-level limit.
  double get rawSpeedLimit => courtSpeedLimitKmh / apiToCourtFactor;

  /// Auto gust rule (uneditable): max(2.2 x raw speed limit, 12 km/h raw).
  /// On calm mornings gusts cluster at 11-14 km/h raw; this only blocks
  /// mornings whose gusts are abnormal for a calm day.
  double get rawGustLimit => math.max(2.2 * rawSpeedLimit, 12.0);
}

class WindSample {
  const WindSample({
    required this.rawSpeedKmh,
    required this.rawGustKmh,
    required this.observedAt,
    required this.isForecast,
  });

  /// 10 m wind speed straight from the API, km/h.
  final double rawSpeedKmh;

  /// 10 m gusts straight from the API, km/h.
  final double rawGustKmh;

  final DateTime observedAt;

  /// True when this came from the hourly forecast (far checks); false when
  /// it is current observed wind (T-0 checks).
  final bool isForecast;

  double get courtSpeedKmh => rawSpeedKmh * apiToCourtFactor;
}

enum WindVerdict { ring, tooWindy, tooGusty }

class WindDecision {
  const WindDecision({
    required this.verdict,
    required this.volume,
    required this.sample,
    required this.thresholds,
  });

  final WindVerdict verdict;

  /// 0.5-1.0 when ringing (wind-proportional ramp), 0.0 otherwise.
  final double volume;

  final WindSample sample;
  final WindThresholds thresholds;

  bool get shouldRing => verdict == WindVerdict.ring;
}

/// Volume ramp locked in SPEC.md: 100% at 0 wind, sliding linearly down to a
/// 50% floor at the threshold. The alarm's loudness tells you how good the
/// badminton weather is before you open your eyes.
double volumeForWind(double courtSpeedKmh, WindThresholds t) {
  final frac = (courtSpeedKmh / t.courtSpeedLimitKmh).clamp(0.0, 1.0);
  return 1.0 - 0.5 * frac;
}

WindDecision decide(WindSample sample, WindThresholds thresholds) {
  if (sample.courtSpeedKmh > thresholds.courtSpeedLimitKmh) {
    return WindDecision(
      verdict: WindVerdict.tooWindy,
      volume: 0,
      sample: sample,
      thresholds: thresholds,
    );
  }
  if (sample.rawGustKmh > thresholds.rawGustLimit) {
    return WindDecision(
      verdict: WindVerdict.tooGusty,
      volume: 0,
      sample: sample,
      thresholds: thresholds,
    );
  }
  return WindDecision(
    verdict: WindVerdict.ring,
    volume: volumeForWind(sample.courtSpeedKmh, thresholds),
    sample: sample,
    thresholds: thresholds,
  );
}

/// Check cascade: T-12h, -6h, -3h, -2h, -1h, -30m, -15m, -8m, -4m, -2m, -1m,
/// T-0, then (only if no check has succeeded yet) every minute up to +30 min.
class CheckCascade {
  CheckCascade._();

  static const List<int> ladderMinutesBefore = [
    720, 360, 180, 120, 60, 30, 15, 8, 4, 2, 1, 0,
  ];

  /// Post-alarm retry window when every pre-alarm check failed.
  static const int retryCapMinutesAfter = 30;

  /// The next moment a check should run, strictly after [now], for an alarm
  /// firing at [alarmAt]. Returns null when the cascade is over.
  ///
  /// [hadSuccessfulCheck] suppresses the post-alarm retry window: retries
  /// after T-0 exist only to recover from "no data at all".
  static DateTime? nextCheckTime(
    DateTime now,
    DateTime alarmAt, {
    required bool hadSuccessfulCheck,
  }) {
    DateTime? best;
    for (final m in ladderMinutesBefore) {
      final t = alarmAt.subtract(Duration(minutes: m));
      if (t.isAfter(now) && (best == null || t.isBefore(best))) best = t;
    }
    if (best != null) return best;
    if (hadSuccessfulCheck) return null;
    // Post-alarm minute-by-minute retries, capped.
    final cap = alarmAt.add(const Duration(minutes: retryCapMinutesAfter));
    if (now.isBefore(cap)) {
      final next = now.add(const Duration(minutes: 1));
      return next.isAfter(cap) ? null : next;
    }
    return null;
  }
}
