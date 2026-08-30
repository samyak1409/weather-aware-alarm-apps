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

/// One 15-minute slot of the play window, already averaged across models.
///
/// **There is no "observed" wind anywhere in this app, and there never was**
/// (2026-08-25, measured). Open-Meteo ships model output, not sensor readings:
/// `current` is byte-identical to the `minutely_15` series indexed at now, and
/// the hourly series is the same numbers again at a coarser step. The old
/// `isForecast` flag said otherwise on the `currentWind` path and **nothing in
/// production ever read it**, so it is gone rather than corrected.
class WindSample {
  const WindSample({
    required this.rawSpeedKmh,
    required this.rawGustKmh,
    required this.slotAt,
  });

  /// 10 m wind speed, km/h — the MEAN across the models that answered.
  final double rawSpeedKmh;

  /// 10 m gusts, km/h — the mean across the same models.
  final double rawGustKmh;

  /// The 15-minute slot this reading **describes**, which is not the moment it
  /// was fetched. It used to be `DateTime.now()` on one path, which was simply
  /// wrong: a check running at 05:45 reads the slot for 06:30, and history
  /// prints these times.
  final DateTime slotAt;

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

/// The verdict for ONE 15-minute slot. Rings only if that slot alone is calm.
///
/// Decide in whole km/h (2026-07-13). The API delivers 0.1-km/h wind, but a
/// heuristic "is it calm enough to play" gate reads cleanest as integers — and
/// rounding BOTH the reading and the limit before a strict `>` makes the
/// decision and the displayed numbers agree by construction (no "skipped at 15
/// vs <=15" contradiction). Cost: <=~0.8 km/h of threshold resolution, always
/// on the lenient side — fine for a guard whose job is to sit above the normal
/// gust band (see SPEC.md "wind model").
WindDecision decideSlot(WindSample sample, WindThresholds thresholds) {
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

/// How harshly a slot was judged. Ordered so `tooWindy` outranks `tooGusty`,
/// matching [decideSlot]'s own precedence — it tests speed before gusts, so a
/// slot that is both reports as windy and the window must say the same thing.
int _severity(WindVerdict v) => switch (v) {
      WindVerdict.tooWindy => 2,
      WindVerdict.tooGusty => 1,
      WindVerdict.ring => 0,
    };

/// The verdict for a whole play window — **every slot must be calm** (Samyak,
/// 2026-08-25).
///
/// Checking one instant was the app's original flaw: it promised a playable
/// *moment* while the user read it as a playable *session*. You are on court
/// from `T + timeUntilPlay` for `minPlayMinutes`, so the wind is checked at
/// every 15-minute slot across that span and the morning rings only if all of
/// them clear.
///
/// **The worst slot decides, and it also carries the volume** — one rule, not
/// two, so the loudness can never disagree with the verdict that produced it.
/// Worst means highest [_severity] first, then highest court speed, so:
/// a failing window reports the slot that failed hardest (and names its time
/// in the card and the log), while a ringing window reports the windiest slot
/// you will actually play in, which is the honest one to set the ramp from.
///
/// Costs real ringing. **Re-measured 2026-08-25** against Open-Meteo's
/// historical forecast archive — the same seven models, averaged the same
/// way, at the same 15-minute resolution — for a 06:00 alarm at Tonk over 365
/// days at limit 6: **84.4%** of occurrences ring on a single instant,
/// **79.5%** across the 30/30 default, **76.4%** across 30/60; in July,
/// 54.8% / 51.6% / 48.4%. That is the flaw being fixed, not a regression.
/// SPEC.md carries the full table, the other limits, and the method, so the
/// numbers can be re-run rather than taken on trust.
///
/// [window] must not be empty — a fetch that returned nothing is a *no-data*
/// morning, which the engine handles by never calling this at all.
WindDecision decide(List<WindSample> window, WindThresholds thresholds) {
  assert(window.isNotEmpty, 'no-data is the caller\'s branch, not a verdict');
  var worst = decideSlot(window.first, thresholds);
  for (final sample in window.skip(1)) {
    final d = decideSlot(sample, thresholds);
    final harsher = _severity(d.verdict) > _severity(worst.verdict);
    final sameButWindier = _severity(d.verdict) == _severity(worst.verdict) &&
        d.sample.courtSpeedKmh > worst.sample.courtSpeedKmh;
    if (harsher || sameButWindier) worst = d;
  }
  return worst;
}

/// The one extra minute value the alarm editor offers behind the developer
/// gate — **shared by every minutes row in the sheet** (2026-08-25, Samyak).
///
/// It was Keep-checking's alone (1m, then 15m from 2026-08-25) until the play
/// window arrived with two more segmented controls. One constant, because a
/// tester wants the SAME shortcut everywhere: three rows each inventing their
/// own dev value is three things to remember.
///
/// **15, not something smaller**, and the reason is Keep checking's: retries
/// land every [CheckCascade.retryStepMinutes], so a shorter window holds no
/// retry at all and would test nothing. It suits the other two for a second
/// reason — Open-Meteo's wind moves on a 15-minute grid, so 15 is the
/// narrowest play window that is still a real window rather than one slot
/// read twice.
const int kDevMinutesOption = 15;

/// What a minutes segmented control renders, ascending.
///
/// The ordinary [base] options, [kDevMinutesOption] while the developer gate
/// is open, and [selected] itself either way: an alarm saved at 15m with dev
/// mode on must still show what it is set to after the gate closes, or the
/// control would draw with nothing selected and quietly misrepresent the
/// alarm. It heals on its own — pick another value and the stray option is
/// gone on the next build.
///
/// One function for all three rows (2026-08-25). Keep checking had this logic
/// to itself; copying it twice for the play window would have been two more
/// places for the gate to drift out of step.
List<int> minuteOptionsFor({
  required List<int> base,
  required bool devMode,
  required int selected,
}) =>
    <int>{
      ...base,
      if (devMode) kDevMinutesOption,
      selected,
    }.toList()
      ..sort();

/// Check cascade (rebuilt 2026-08-25, Samyak). Nine rungs before the alarm —
/// T-24h, -12h, -6h, -3h, -2h, -1h, -30m, -15m, T-0 — then a retry every
/// [retryStepMinutes] up to the per-alarm cap.
///
/// **The rungs are a wake-up-and-network lottery, not a data schedule.** Wind
/// data moves on a 15-minute grid and the *forecast* for your play window is
/// revised only when a model run lands (1-6 hours apart), so consecutive rungs
/// usually read identical numbers. What each rung buys is another chance that
/// the phone wakes AND has a network — and one success arms the ring on the
/// OS, which then fires whether or not the app ever runs again.
///
/// **The old near cluster was wasted.** It ran T-10, -5, -2, -1, T-0: five
/// wake-ups inside ten minutes, against Doze's ~one-per-nine-minutes quota for
/// `allowWhileIdle` alarms off charger. Roughly four of the five were thrown
/// away by the OS. Every gap here is >=15 minutes, so every rung is a ticket
/// that can actually be drawn.
///
/// **T-0 IS the last-second decider** — a ring already armed for T is
/// re-decided on the freshest reading and cancelled if the play window has
/// turned windy since. The reason is that the engine has always done it:
/// `engine_test`'s `turns windy at T-0: ring cancelled` predates this rebuild.
/// (Not the locked fail-safe — `windy -> no ring` is the decision to make when
/// you check, not a duty to disarm. This comment and SPEC both claimed the
/// opposite between 2026-08-25 and 2026-08-30, borrowing SPEC's "better to
/// ring and let the user judge than to over-skip", which is about the DEFAULT
/// WIND LIMIT being the most lenient one. Caught by Cursor Grok 4.6.)
///
/// **Only when the fetch returns.** A failed read at T cannot cancel anything,
/// so a last-second network blip never costs a ring the ladder already decided.
/// The pass is not a no-op: it records the attempt, posts the still-checking
/// card if none is up, and books the next retry — so on a dead-network T that
/// card can sit beside a pre-arm that goes on to sound.
///
/// **Two consequences, both known and both accepted.** On Android the T-0 check
/// and the ring are exact alarms for the same instant, so their order is the
/// platform's to choose: if the ring wins, Rule 1 sees it audible and leaves it
/// alone; if the check wins on a calm morning, it re-arms into the late locker
/// and the alarm sounds ~10s late. On iOS the wakeup's date is a floor rather
/// than a schedule, so the T-0 re-check **may not run at all** and the pre-arm
/// sounds on time.
class CheckCascade {
  CheckCascade._();

  static const List<int> ladderMinutesBefore = [
    1440, 720, 360, 180, 120, 60, 30, 15, 0,
  ];

  /// How far apart post-T retries sit — the same 15 minutes the wind data
  /// itself moves on, so no two retries can read the same slot twice.
  static const int retryStepMinutes = 15;

  /// Choices offered in the alarm editor.
  static const List<int> retryMinutesOptions = [30, 60];

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
    // Post-alarm retries on a FIXED grid off T — every 15 minutes, then the
    // cap itself. Anchoring to `alarmAt` rather than to `now` keeps a late wake
    // on the same slots the wind data uses, and the trailing `cap` covers a
    // window that is not a whole multiple of the step (nothing offered today
    // isn't, but a stored value need not be).
    final cap = alarmAt.add(Duration(minutes: retryCapMinutes));
    if (!now.isBefore(cap)) return null;
    for (var m = retryStepMinutes; m < retryCapMinutes; m += retryStepMinutes) {
      final t = alarmAt.add(Duration(minutes: m));
      if (t.isAfter(now)) return t;
    }
    return cap.isAfter(now) ? cap : null;
  }

}
