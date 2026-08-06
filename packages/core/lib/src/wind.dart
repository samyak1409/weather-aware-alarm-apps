/// Wind decision engine for Nivaat. All rules locked in SPEC.md and derived
/// from real Open-Meteo data for Tonk and Bengaluru (2026-07-11 research).
library;

/// Weather APIs report wind at 10 m height; at court level (~2 m) wind is
/// ~40% weaker (log wind profile over open/suburban terrain).
const double apiToCourtFactor = 0.6;

/// Gust ceiling as a multiple of the (10 m) speed limit — a typical low-wind
/// gust factor, above the ~1.4–1.7 seen in the field, so only abnormal gusts
/// block a ring. No additive floor: court-wind settings below 4 would have
/// needed one (their 2.2× falls under the ~12–15 km/h near-surface gust
/// baseline), so those settings are simply not offered — see SPEC.md.
const double gustFactor = 2.2;

class WindThresholds {
  const WindThresholds({required this.courtSpeedLimitKmh});

  /// User-facing dropdown value, 4-6 km/h, semantic = wind felt at the court.
  final int courtSpeedLimitKmh;

  static const int minLimit = 4;
  static const int maxLimit = 6;
  static const int defaultLimit = 6;

  /// The 10 m API speed corresponding to the court-level limit.
  double get rawSpeedLimit => courtSpeedLimitKmh / apiToCourtFactor;

  /// Auto gust rule (uneditable): [gustFactor] × the raw speed limit, no floor.
  double get rawGustLimit => gustFactor * rawSpeedLimit;
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

  /// One of [windVolumeSteps] when ringing (wind-proportional), 0.0 otherwise.
  final double volume;

  final WindSample sample;
  final WindThresholds thresholds;

  bool get shouldRing => verdict == WindVerdict.ring;
}

/// The three loudness steps, loudest first. The alarm's volume tells you how
/// good the badminton weather is before you open your eyes.
const List<double> windVolumeSteps = [1.0, 0.85, 0.70];

/// Volume ramp locked in SPEC.md: the old linear 100%→floor slide, **snapped
/// to the nearest of [windVolumeSteps]** (2026-07-26, Samyak — option B over
/// an even-thirds split; the floor moved 75% → 70% with the step count).
///
/// The midpoints between steps fall at a quarter and three quarters of your
/// limit, so: 100% up to L/4, 85% up to 3L/4, 70% above. Limit 6 → 100% to
/// 1.5, 85% to 4.5, then 70%.
///
/// Three steps, because Android can't deliver more. The `alarm` package sets a
/// system stream volume and the OS quantises it to an index — on a 7-step
/// device the previous six values collapsed to three clicks anyway
/// (5/6/6/6/7/7), so four of the six were fiction. These three land on
/// distinct clicks at both common step counts: 7-step → 7/6/5, 15-step →
/// 15/13/11.
double volumeForWind(double courtSpeedKmh, WindThresholds t) {
  final limit = t.courtSpeedLimitKmh;
  final c = courtSpeedKmh.clamp(0.0, limit.toDouble());
  // Multiplied out rather than divided: `c / limit <= 0.25` can miss its own
  // boundary by a float hair, while quarters of a whole limit are exact in
  // binary. The edge belongs to the LOUDER step (snapping to nearest, ties up).
  if (c * 4 <= limit) return windVolumeSteps[0];
  if (c * 4 <= limit * 3) return windVolumeSteps[1];
  return windVolumeSteps[2];
}

WindDecision decide(WindSample sample, WindThresholds thresholds) {
  // Decide in whole km/h (2026-07-13). The API delivers 0.1-km/h wind, but a
  // heuristic "is it calm enough to play" gate reads cleanest as integers — and
  // rounding BOTH the reading and the limit before a strict `>` makes the
  // decision and the displayed numbers agree by construction (no "skipped at 15
  // vs ≤15" contradiction). Cost: ≤~0.8 km/h of threshold resolution, always
  // on the lenient side — fine for a guard whose job is to sit above the normal
  // gust band (see SPEC.md "wind model").
  if (sample.courtSpeedKmh.round() > thresholds.courtSpeedLimitKmh) {
    return WindDecision(
      verdict: WindVerdict.tooWindy,
      volume: 0,
      sample: sample,
      thresholds: thresholds,
    );
  }
  if (sample.rawGustKmh.round() > thresholds.rawGustLimit.round()) {
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

/// Check cascade (2026-07-15): T-1h, -30m, -15m, -10m, -5m, -2m, -1m, T-0, then
/// every minute up to the per-alarm retry cap (default +30 min; options 30 / 60
/// since 2026-07-26, plus a dev-only 1 since 2026-08-06). The far pre-arm rungs
/// (T-12h…-2h) were dropped — they only ever ran on Android (exact wakeups),
/// where the near ladder + T-0 carry it, and on iOS the whole ladder is
/// opportunistic anyway. The post-T retries run after *any* skip
/// (windy/gusty/no-data), not just no-data, so a morning that calms within the
/// window still rings (late) — see [NivaatEngine].
class CheckCascade {
  CheckCascade._();

  static const List<int> ladderMinutesBefore = [
    60, 30, 15, 10, 5, 2, 1, 0,
  ];

  /// Choices offered in the alarm editor.
  static const List<int> retryMinutesOptions = [30, 60];

  /// Developer-only extras (2026-08-06, Samyak). A one-minute window plays a
  /// whole morning out in a minute, which is how the cascade gets tested by
  /// hand — and is nothing to offer a real user, since a minute is barely
  /// room for the wind to drop. Behind the seven-tap gate (`DevMode`).
  static const List<int> devRetryMinutesOptions = [1];

  /// What the editor renders, ascending.
  ///
  /// The ordinary options, the dev ones while the gate is open, and [selected]
  /// itself either way: an alarm saved at 1m with dev mode on must still show
  /// what it is set to after the gate closes, or the control would draw with
  /// nothing selected and quietly misrepresent the alarm. It heals on its own
  /// — pick another value and the stray option is gone on the next build.
  static List<int> retryOptionsFor({
    required bool devMode,
    required int selected,
  }) =>
      <int>{
        ...retryMinutesOptions,
        if (devMode) ...devRetryMinutesOptions,
        selected,
      }.toList()
        ..sort();

  /// Default post-alarm retry window when the alarm doesn't pick another.
  static const int retryCapMinutesAfter = 30;

  /// The next moment a check should run, strictly after [now], for an alarm
  /// firing at [alarmAt]. Returns null when the cascade is over (past the retry
  /// cap). [retryCapMinutes] is per-alarm ([NivaatAlarm.retryMinutesAfter]) and
  /// post-T retries always run to it — the engine stops early by finalising the
  /// occurrence once it rings.
  static DateTime? nextCheckTime(
    DateTime now,
    DateTime alarmAt, {
    int retryCapMinutes = retryCapMinutesAfter,
  }) {
    DateTime? best;
    for (final m in ladderMinutesBefore) {
      final t = alarmAt.subtract(Duration(minutes: m));
      if (t.isAfter(now) && (best == null || t.isBefore(best))) best = t;
    }
    if (best != null) return best;
    // Post-alarm minute-by-minute retries, capped. While still before the
    // cap, book the next minute — or the cap itself when a +1m step would
    // overshoot. Without that clamp, an off-minute wake in the last minute
    // (or any evaluate between T and T+1m on a 1-min window) returned null
    // and the engine finalised early (2026-07-26).
    final cap = alarmAt.add(Duration(minutes: retryCapMinutes));
    if (!now.isBefore(cap)) return null;
    final next = now.add(const Duration(minutes: 1));
    return next.isAfter(cap) ? cap : next;
  }
}
