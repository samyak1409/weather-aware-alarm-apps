import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

import 'ids.dart';
import 'messages.dart';
import 'sound_selection.dart' as sound;

/// App state + alarm orchestration for Arunoday.
///
/// Scheduling model (v1): a rolling window of the next [windowDays] wake and
/// bedtime alarms, resynced on every app open / settings change. Every id
/// comes from [ArunodayIds] — keyed on the alarm's calendar day, so a given
/// day's alarm keeps one id no matter when the resync runs.
class ArunodayController extends ChangeNotifier {
  ArunodayController({
    required this.store,
    required this.scheduler,
  }) {
    scheduler.setHostAlarmEventHandler(_onHostAlarmEvent);
  }

  /// A host moved or dropped one of our alarms — rebuild the window so a
  /// deferral is preserved and a drop is re-armed.
  ///
  /// **Two guards, and both were learned the hard way.**
  ///
  /// `loaded` first: `main` starts the plugin, and `Alarm.init()` replays every
  /// pending native event immediately. Reaching [_arm] before [init] has read
  /// settings means `activeLocation` is still null, and that branch cancels
  /// EVERYTHING — one replayed event at launch would disarm the user's whole
  /// window before the app had finished reading it back.
  ///
  /// Then the re-entrancy guard: [_arm] awaits its own event barrier, so a
  /// handler running inside one and calling [_armWindow] would either recurse
  /// or (once the pass is serialised) queue behind the very job that is
  /// awaiting it. Recording that another pass is owed and letting the current
  /// one finish converges to the same place without either.
  Future<void> _onHostAlarmEvent(HostAlarmEvent event) async {
    // **Dropping the event before `loaded` costs nothing, and that is worth
    // stating rather than leaving to be re-derived.** The bridge marks an
    // event handled when the handler returns without throwing, so returning
    // here does consume it. It is safe only because this handler never reads
    // the event: it triggers a full window rebuild, and `init` runs exactly
    // that rebuild the moment settings finish loading. The information is
    // redundant with the resync that immediately follows.
    //
    // If this handler ever starts acting on `event` itself, that stops being
    // true and the event has to be held rather than swallowed.
    if (!loaded) return;
    if (_armRunning) {
      _armAgain = true;
      return;
    }
    await _armWindow();
  }

  // **This handler is deliberately advisory, and the bridge's retry cannot
  // change that.** A previous version threw when the pass soft-failed, so the
  // event would be deferred and retried — three things were wrong with it.
  //
  // It threw a `StateError`, which is an `Error`; the bridge defers on
  // `Exception`, so nothing was retried and the event was lost harder than
  // before. The `_armRunning` branch returns normally anyway, so an event
  // arriving mid-pass was claimed regardless. And structurally it could never
  // have worked: **every one of Arunoday's barriers is inside `_arm` itself**,
  // so a deferred event is re-run during the very pass that would retry it,
  // burns its three attempts while `_armRunning` is true, and is abandoned.
  //
  // What makes losing it acceptable is the same thing that makes the `loaded`
  // guard acceptable: this handler never reads the event. It asks for a full
  // window rebuild, `_arm` rebuilds from scratch and is idempotent, and app
  // resume / a settings change / a ring ending all run the same rebuild. A
  // failed pass costs promptness, not correctness. If this handler ever starts
  // acting on `event` itself, that stops being true.

  final ArunodayStore store;
  final AlarmScheduler scheduler;

  /// Days of alarms kept armed ahead. Tied to [ArunodayIds.slots]: the id map
  /// needs exactly one locker per day in this window, so the two can never
  /// drift apart.
  static const int windowDays = ArunodayIds.slots;

  ArunodaySettings settings = const ArunodaySettings();
  SleepPlanResult? plan;
  bool loaded = false;

  SavedLocation? get activeLocation => settings.activeLocation;

  /// A16's place-picker refusals, or null to accept. **One copy** (2026-07-31):
  /// home and settings both add locations, and each carried its own inline
  /// pair of these strings — two places to keep in step, which is one more
  /// than none, and neither was reachable by a test where it sat.
  String? placeRefusal(double lat, double lon) {
    if (!Solar.hasDailyDawnAllYear(DateTime.now().year, lat, lon)) {
      return kArunodayNoDawnHere;
    }
    final dup = existingLocationSameDawn(lat, lon);
    return dup == null ? null : arunodaySameDawn(dup.name);
  }

  /// An already-saved location that produces the **same alarm** as (lat, lon),
  /// else null. Two locations are functional duplicates when their civil dawn
  /// matches to the minute all year — distance is the wrong proxy (dawn only
  /// shifts ~1 min per ~25 km of longitude). We sample the solstices (where
  /// latitude-driven divergence is largest) and the equinoxes; matching on
  /// all four means matching year-round.
  SavedLocation? existingLocationSameDawn(double lat, double lon) {
    final y = DateTime.now().year;
    final samples = [
      DateTime(y, 6, 21),
      DateTime(y, 12, 21),
      DateTime(y, 3, 21),
      DateTime(y, 9, 21),
    ];
    for (final l in settings.locations) {
      var same = true;
      for (final d in samples) {
        final a = Solar.civilDawnLocal(d, l.lat, l.lon);
        final b = Solar.civilDawnLocal(d, lat, lon);
        if (a == null ||
            b == null ||
            a.hour * 60 + a.minute != b.hour * 60 + b.minute) {
          same = false;
          break;
        }
      }
      if (same) return l;
    }
    return null;
  }

  /// Fixed bedtime in minutes-after-midnight. The manual adjustment is stored
  /// as a signed *offset from the auto plan* (like the wake offset is from
  /// dawn), so it travels consistently across locations — switch cities and
  /// "1h later than the ideal" stays 1h later than the new ideal.
  double? get bedtimeMinutes {
    final auto = plan?.bedtimeMinutes;
    if (auto == null) return null;
    final off = settings.bedtimeOffsetMinutes;
    return off == null ? auto : (auto + off) % 1440.0;
  }

  /// "Auto" / "Auto +2:00" — how the bedtime relates to the auto plan.
  String get bedtimeModeDescription {
    final off = settings.bedtimeOffsetMinutes;
    return (off == null || off == 0) ? 'Auto' : 'Auto${fmtOffset(off)}';
  }

  /// Civil dawn for [date] at the active location, floored to the minute.
  ///
  /// Quantized at the source: dawn's seconds drift ~±25s/day, and letting
  /// them into wake times made every derived display (picker anchor, ring
  /// moment, TONIGHT math) flicker by one minute. Core stays second-precise;
  /// the app deals only in whole minutes.
  DateTime? dawnOn(DateTime date) {
    final loc = activeLocation;
    if (loc == null) return null;
    final d = Solar.civilDawnLocal(date, loc.lat, loc.lon);
    return d == null ? null : _floorToMinute(d);
  }

  /// Sunrise for [date] at the active location (display only — every alarm
  /// anchors to civil dawn). Minute-floored like [dawnOn].
  DateTime? sunriseOn(DateTime date) {
    final loc = activeLocation;
    if (loc == null) return null;
    final s = Solar.sunriseLocal(date, loc.lat, loc.lon);
    return s == null ? null : _floorToMinute(s);
  }

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Wake time (dawn + permanent offset) for [date], before one-time extras.
  DateTime? baseWakeOn(DateTime date) =>
      dawnOn(date)?.add(Duration(minutes: settings.wakeOffsetMinutes));

  /// Wake time for [date] including a matching one-time extra.
  DateTime? wakeOn(DateTime date) {
    final base = baseWakeOn(date);
    if (base == null) return null;
    if (settings.oneTimeExtraDate == _dateKey(base)) {
      return base.add(Duration(minutes: settings.oneTimeExtraMinutes));
    }
    return base;
  }

  /// The first moment [on] produces in the window strictly after [now],
  /// stepping by [calendarDay] like the resync that arms these (REVIEW #13).
  /// **One walk for both callers**, so the countdown and "+2h tomorrow" can
  /// never disagree about which morning is next.
  DateTime? _firstFuture(DateTime now, DateTime? Function(DateTime) on) {
    for (var i = 0; i <= windowDays; i++) {
      final w = on(calendarDay(now, i));
      if (w != null && w.isAfter(now)) return w;
    }
    return null;
  }

  /// The next wake alarm moment strictly after [now]. `now` is a parameter for
  /// the same reason [nextDailyBedtime]'s is — it is the only way to pin this
  /// to a clock-change date.
  @visibleForTesting
  DateTime? nextWakeAt(DateTime now) => _firstFuture(now, wakeOn);

  /// The next wake alarm moment strictly after now.
  DateTime? get nextWake => nextWakeAt(DateTime.now());

  /// The bedtime moments the window wants at [now] — one per calendar
  /// **date**, each at the bedtime **clock** time on it (REVIEW #11).
  ///
  /// Both steps are calendar steps; the second is the one that bit, a line
  /// after the day had been chosen correctly. Takes `now` because the arming
  /// loop reads the clock, and this arithmetic is worth pinning to a
  /// transition date rather than to whatever week the tests run in — so **the
  /// arming loop must stay its only caller**, or the pin stops covering what
  /// actually gets armed.
  @visibleForTesting
  static List<DateTime> bedtimeWindowAt(DateTime now, int bedMinutes) => [
        for (var i = 0; i < windowDays; i++)
          clockTimeOn(calendarDay(now, i), bedMinutes)
      ];

  /// Next daily bedtime occurrence strictly after now (ignores AGAIN).
  @visibleForTesting
  DateTime? nextDailyBedtime(DateTime now) {
    final bed = bedtimeMinutes;
    if (bed == null) return null;
    // Both halves are clock arithmetic (REVIEW #14): the same time of day, on
    // today's date and then on the next DATE. Rolling forward 24 elapsed hours
    // aimed a 00:15 bedtime at 23:15 the same evening on a fall-back day.
    var s = clockTimeOn(now, bed.round());
    for (var d = 1; !s.isAfter(now); d++) {
      s = clockTimeOn(calendarDay(now, d), bed.round());
    }
    return s;
  }

  /// The next bedtime alarm to actually *ring* — the sooner of the daily
  /// bedtime and a pending AGAIN. Drives the "IN" countdown.
  DateTime? get nextBedtimeRing {
    final now = DateTime.now();
    final times = <DateTime>[];
    final delayed = settings.bedtimeDelayedUntil;
    if (delayed != null && delayed.isAfter(now)) times.add(delayed);
    final daily = nextDailyBedtime(now);
    if (daily != null) times.add(daily);
    if (times.isEmpty) return null;
    times.sort();
    return times.first;
  }

  /// When you'll actually turn in tonight = the LAST bedtime prompt before
  /// the next wake, i.e. **max(tonight's bedtime, a pending AGAIN)**. If you
  /// pushed bedtime later, that later time is when you sleep.
  DateTime? get sleepStartMoment {
    final w = nextWake;
    final bed = bedtimeMinutes;
    DateTime? daily;
    if (w != null && bed != null) {
      // The bedtime occurrence that pairs with this wake: the latest one
      // strictly before it — clock time on a date, stepped back by date, the
      // same pair of rules as [nextDailyBedtime] (REVIEW #13).
      daily = clockTimeOn(w, bed.round());
      if (!daily.isBefore(w)) {
        daily = clockTimeOn(calendarDay(w, -1), bed.round());
      }
    }
    final now = DateTime.now();
    final d = settings.bedtimeDelayedUntil;
    final again =
        (d != null && d.isAfter(now) && (w == null || d.isBefore(w))) ? d : null;
    if (daily == null) return again;
    if (again == null) return daily;
    return daily.isAfter(again) ? daily : again; // max
  }

  /// Tonight's sleep in minutes: next wake − [sleepStartMoment]. Both
  /// truncated to the minute first so the number agrees with what you'd
  /// subtract from the on-screen clocks (05:21 → 12:01 reads 6h 40m).
  double? get tonightSleepMinutes {
    final w = nextWake;
    final start = sleepStartMoment;
    if (w == null || start == null) return null;
    return _floorToMinute(w)
        .difference(_floorToMinute(start))
        .inMinutes
        .toDouble();
  }

  static DateTime _floorToMinute(DateTime t) =>
      DateTime(t.year, t.month, t.day, t.hour, t.minute);

  /// Loads settings, **shows the screen, and only then arms anything**
  /// (REVIEW #15). Home renders nothing while `!loaded`, so arming first put
  /// every plugin call between the user and their app: one throw and neither
  /// `loaded` nor the notify was reached — a black screen, and `main` launches
  /// this unawaited, so the only trace was a console line.
  ///
  /// **What moves ahead of the screen is only what cannot fail.**
  /// [_recomputePlan] goes first because home reads `plan` for the bedtime
  /// clock; without it the first frame prints `—` and fills it in a moment
  /// later, trading a black screen for a flicker. It touches no plugin, so it
  /// cannot be the throw this is all about.
  Future<void> init() async {
    settings = await store.load();
    _recomputePlan();
    loaded = true;
    notifyListeners();
    await _armWindow();
    notifyListeners();
  }

  Future<void> update(ArunodaySettings next) async {
    settings = next;
    await store.save(next);
    await _recomputeAndResync();
    notifyListeners();
  }

  /// Called on app resume: reload persisted state (a notification action may
  /// have changed it from another isolate) and keep the window fresh.
  Future<void> resync() async {
    settings = await store.load();
    await _recomputeAndResync();
    notifyListeners();
  }

  /// Bedtime-ritual action: "tomorrow only, wake N minutes later".
  /// Applies to the next upcoming wake; auto-clears once it has passed.
  Future<void> setOneTimeExtra(int minutes) async {
    // Shares [nextWakeAt]'s walk (REVIEW #13) — and not display-only here:
    // this stamps `oneTimeExtraDate`, so a skipped date lands "+2h tomorrow"
    // on the wrong morning and leaves the intended one at its normal time.
    final nextBase = _firstFuture(DateTime.now(), baseWakeOn);
    if (nextBase == null) return;
    await update(settings.copyWith(
      oneTimeExtraMinutes: minutes,
      oneTimeExtraDate: () => minutes == 0 ? null : _dateKey(nextBase),
    ));
  }

  /// Bedtime-ritual action: "not sleepy yet" — ring the bedtime again later.
  /// Floored to the minute like every user-facing time.
  Future<void> delayBedtime(Duration delay) async {
    await update(settings.copyWith(
      bedtimeDelayedUntil: () => _floorToMinute(DateTime.now().add(delay)),
    ));
  }

  /// Mistap recovery: cancel a pending "not sleepy" re-ring.
  Future<void> cancelBedtimeDelay() async {
    await update(settings.copyWith(bedtimeDelayedUntil: () => null));
  }

  void _clearExpiredOneTimers() {
    var s = settings;
    final now = DateTime.now();
    if (s.oneTimeExtraDate != null) {
      final parts = s.oneTimeExtraDate!.split('-').map(int.parse).toList();
      final wake = wakeOn(DateTime(parts[0], parts[1], parts[2]));
      if (wake == null || !wake.isAfter(now)) {
        s = s.copyWith(oneTimeExtraMinutes: 0, oneTimeExtraDate: () => null);
      }
    }
    final delayed = s.bedtimeDelayedUntil;
    if (delayed != null && !delayed.isAfter(now)) {
      s = s.copyWith(bedtimeDelayedUntil: () => null);
    }
    if (!identical(s, settings)) {
      settings = s;
      store.save(s); // fire-and-forget persistence of the cleanup
    }
  }

  Future<void> _recomputeAndResync() async {
    _recomputePlan();
    await _armWindow();
  }

  /// The half that touches nothing outside this isolate — the sleep plan and
  /// the expired one-timers — so [init] can run it before the screen appears
  /// (REVIEW #15).
  void _recomputePlan() {
    sound.selectedSoundPath = settings.soundPath;
    _clearExpiredOneTimers();
    final loc = activeLocation;
    // Auto bedtime anchors to pure dawn (offset 0): the wake offset moves
    // only the wake alarm, never the bedtime (user decision 2026-07-12).
    plan = loc == null
        ? null
        : SleepPlan.forLocation(
            year: DateTime.now().year,
            latDeg: loc.lat,
            lonDeg: loc.lon,
            wakeOffsetMinutes: 0,
          );
  }

  /// The half that reaches for the alarm plugin. **Soft-fails** on [Exception]
  /// like Nivaat's `resync` (REVIEW #15) — a hiccup must cost the alarms it
  /// could not arm, never the app, and every resync rebuilds the whole window
  /// from scratch so a failure is not sticky. `Error`s still propagate.
  /// Reads `plan` via [bedtimeMinutes], so [_recomputePlan] runs first.
  /// One arming pass at a time, in order.
  ///
  /// Two overlapping passes each hold their own snapshot of what the plugin
  /// has armed and then cancel against it, so the second undoes what the first
  /// just wrote. Resyncs are triggered from several places at once — app
  /// resume, a settings save, a ring ending, and now a host event — so the
  /// overlap is ordinary rather than exotic.
  Future<void> _armLane = Future<void>.value();
  bool _armRunning = false;
  bool _armAgain = false;

  Future<void> _armWindowAt([DateTime? clock]) {
    final run = _armLane.then((_) => _runArmPasses(clock));
    // Park an error-swallowing copy so one failed pass can't jam the lane.
    _armLane = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _runArmPasses(DateTime? clock) async {
    _armRunning = true;
    try {
      // Bounded: a host event landing mid-pass asks for one more pass, and an
      // event storm must not keep this one running forever.
      var passes = 0;
      do {
        _armAgain = false;
        try {
          await _arm(clock: clock);
        } on Exception catch (e, st) {
          debugPrint('arunoday resync failed (non-fatal): $e\n$st');
        }
        passes++;
      } while (_armAgain && passes < 3);
    } finally {
      _armRunning = false;
    }
  }

  Future<void> _armWindow() => _armWindowAt();

  /// Test seam: resync the alarm window as if wall clock were [now].
  @visibleForTesting
  Future<void> syncArmsAt(DateTime now) => _armWindowAt(now);

  Future<void> _arm({DateTime? clock}) async {
    // Drain host drop/move events before any cancel/re-arm decision.
    await scheduler.applyHostAlarmEvents();

    final loc = activeLocation;
    if (loc == null) {
      await _cancelExcept(const {});
      return;
    }
    final now = clock ?? DateTime.now();
    final wanted = <int, ({DateTime at, String title, String body})>{};
    // Every logical alarm the config still wants — including ones whose minute
    // has passed but a short host deferral may still be live on the plugin.
    final expectedById = <int, DateTime>{};

    if (settings.wakeEnabled) {
      for (var i = 0; i < windowDays; i++) {
        final day = calendarDay(now, i);
        final wake = wakeOn(day);
        if (wake == null) continue;
        final id = ArunodayIds.wake(day);
        expectedById[id] = wake;
        if (wake.isAfter(now)) {
          // "First light" is only honest when the wake IS the dawn.
          final dawn = dawnOn(day);
          final shift = dawn == null ? 0 : wake.difference(dawn).inMinutes;
          wanted[id] = (
            at: wake,
            title: kArunodayWakeTitle,
            body: arunodayWakeBody(loc.name, shift),
          );
        }
      }
    }

    // A pending re-ring (below) wins a same-minute slot: skip the daily bedtime
    // that lands on it so only one alarm sounds. Cancelling the re-ring restores
    // the daily bedtime on the next resync (it's recomputed from scratch).
    final delayed = settings.bedtimeDelayedUntil;
    final reRingMinute = (settings.bedtimeEnabled && delayed != null)
        ? _floorToMinute(delayed)
        : null;
    final reRing = (reRingMinute != null && delayed!.isAfter(now))
        ? reRingMinute
        : null;

    final bed = bedtimeMinutes;
    if (settings.bedtimeEnabled && bed != null) {
      for (final at in bedtimeWindowAt(now, bed.round())) {
        final id = ArunodayIds.bedtime(at);
        expectedById[id] = at;
        if (at.isAfter(now) && at != reRing) {
          // `bedtime()` reads only the date, which `at` still carries.
          wanted[id] = (
            at: at,
            title: kArunodayBedtimeTitle,
            body: kArunodayBedtimeBody,
          );
        }
      }
    }

    // "Not sleepy yet" delayed bedtime reminder from the ring screen.
    if (settings.bedtimeEnabled && delayed != null) {
      expectedById[ArunodayIds.bedtimeAgain] = _floorToMinute(delayed);
      if (delayed.isAfter(now)) {
        wanted[ArunodayIds.bedtimeAgain] = (
          at: delayed,
          title: kArunodayBedtimeTitle,
          body: kArunodayBedtimeAgainBody,
        );
      }
    }

    // Preserve plugin times that still match the logical alarm (or a short
    // host deferral of it). Scan [expectedById], not only [wanted.keys]:
    // after logical T the id drops out of wanted but a +30s deferral must
    // stay in [keep] until it fires.
    //
    // **One snapshot for the whole pass.** Asking the plugin per id was both
    // twenty-odd platform round trips per resync and a moving target — the
    // answers could disagree with each other halfway through, so the set being
    // preserved and the set being cancelled were computed against different
    // worlds.
    final armedNow = await scheduler.scheduledAlarms();
    final preserved = <int>{};
    // Ids whose plugin time may be kept, and the logical time it is judged
    // against. NOT the same as [expectedById]: a daily bedtime whose minute the
    // AGAIN re-ring has taken over is expected in the abstract but must not be
    // preserved, or the suppressed alarm survives from an earlier pass and both
    // sound on the same minute.
    final preservable = <int, DateTime>{};
    final keep = Set<int>.from(wanted.keys);
    // The AGAIN re-ring owns its minute either because it is still ahead of us,
    // or because the platform is holding it (or a short deferral of it) right
    // now. [reRingMinute] above is the same minute — one name for one thing.
    final againInfo = armedNow[ArunodayIds.bedtimeAgain];
    final againOwnsSlot = reRingMinute != null &&
        (delayed!.isAfter(now) ||
            (againInfo != null &&
                _isPreservable(againInfo, reRingMinute, now)));
    for (final entry in expectedById.entries) {
      if (againOwnsSlot &&
          entry.key >= ArunodayIds.bedtimeBlock &&
          entry.key < ArunodayIds.bedtimeAgain &&
          entry.value == reRingMinute) {
        continue; // AGAIN owns this minute — same rule as wanted's at != reRing
      }
      preservable[entry.key] = entry.value;
      final info = armedNow[entry.key];
      if (info == null) continue;
      if (_isPreservable(info, entry.value, now)) {
        preserved.add(entry.key);
        keep.add(entry.key);
      }
    }

    // The cancel loop re-reads each id immediately before destroying it: a move
    // can land between the snapshot above and the cancel, and cancelling a
    // `06:00:30` deferral of a 06:00 alarm whose own minute has passed loses
    // the ring outright — nothing re-arms it, because 06:00 is behind us and
    // never re-enters [wanted].
    await _cancelExcept(
      keep,
      stillWanted: (id, info) {
        final expected = preservable[id];
        return expected != null && _isPreservable(info, expected, now);
      },
    );
    // One more drain and one more snapshot, AFTER the cancels: a move that
    // landed during them makes an id preservable that was not preservable when
    // `preserved` was built, and arming over it would throw the deferral away.
    // One read for the whole loop rather than one per id — asking inside the
    // loop was a full platform round trip per alarm in the window.
    await scheduler.applyHostAlarmEvents();
    final armedAfterCancels = await scheduler.scheduledAlarms();
    for (final e in wanted.entries) {
      if (preserved.contains(e.key)) continue;
      final info = armedAfterCancels[e.key];
      if (info != null && _isPreservable(info, e.value.at, now)) {
        continue;
      }
      // Arunoday records nothing about whether an alarm is armed, so unlike
      // Nivaat it has no claim to withhold — but a failure still means no
      // alarm, and every resync retries. Logged rather than dropped so a
      // "my alarm didn't go off" report has something behind it; on iOS a
      // denial also raises AlarmPermissionBanner, which is the user-facing
      // half.
      final armed = await scheduler.scheduleRing(
        id: e.key,
        at: e.value.at,
        title: e.value.title,
        body: e.value.body,
        // Null, not 1.0: the phone's own alarm volume is the setting, and
        // Arunoday has no reason to have an opinion about it. Passing 1.0 rang
        // a deliberately-quiet phone at full blast and stopped the user
        // turning it down (device-caught 2026-08-05).
        volume: null,
      );
      if (!armed) {
        debugPrint('arunoday could not arm alarm ${e.key} for ${e.value.at}');
      }
    }
  }

  /// Whether [pluginAt] is still the logical [expected] occurrence, or a short
  /// host deferral of it (platform refusal ~+30s) — not a leftover after an
  /// edit that moved the alarm to a different minute.
  bool _isPreservable(
    ScheduledAlarmInfo info,
    DateTime expected,
    DateTime now,
  ) {
    // **One id, more than one live alarm → never preserve.** On iOS a refused
    // cancel keeps its handle, so an id can still resolve to an old alarm at
    // the old minute while the newest sits at the right one. Preserving skips
    // `scheduleRing`, and `scheduleRing` is the only thing that ever retries
    // those failed cancels — so a "duplicate alert you can stop" would quietly
    // become permanent, and the 06:00 the user edited away from keeps ringing.
    // Re-arming instead costs one platform call and clears the stragglers.
    if (info.handles != 1) return false;
    final pluginAt = info.dateTime;
    if (!pluginAt.isAfter(now)) return false;
    final delta = pluginAt.difference(expected);
    // The alarm is exactly where we put it.
    if (delta.inSeconds.abs() <= 1) return true;
    // **A forward deferral, and only once the alarm's own moment has come.**
    // The host defers a ring because it tried to fire and was refused, so
    // before [expected] there is nothing for it to have deferred — a plugin
    // time sitting a minute ahead of a future alarm is not a deferral at all,
    // it is the OLD alarm the user has just edited away from. Without the
    // clock test, nudging wake from 06:00 to 05:59 the night before read as a
    // 60-second deferral of 05:59, and the edit silently did nothing: the
    // alarm went on ringing at 06:00.
    if (delta > Duration.zero &&
        delta <= const Duration(minutes: 2) &&
        !expected.isAfter(now)) {
      return true;
    }
    return false;
  }

  /// Cancels every armed alarm except the ids in [keep] — and except one that
  /// is **sounding right now**.
  ///
  /// A ringing alarm's moment is already past, so it can never be in [keep],
  /// and cancelling it silences it mid-ring. That guard used to live only in
  /// the resync loop; the "no location left" path twenty lines below cancelled
  /// unconditionally, so deleting your last location while the bedtime alarm
  /// was sounding stopped the sound (REVIEW #3). Both paths are this one method
  /// now, which is the actual fix — a second copy of the guard would just be a
  /// second thing to forget.
  ///
  /// Delete/disable clears ids from [keep], so a plugin-future time is still
  /// cancelled — preserve is only for ids the config still wants.
  ///
  /// [stillWanted] is consulted with each id's time **as read at the moment of
  /// cancelling**, which is the one thing [keep] cannot express: [keep] was
  /// computed from a snapshot, and a host move landing after it makes an id
  /// worth keeping that was not worth keeping when the set was built. The gap
  /// is narrowed, not closed — there is no way to make read-and-cancel atomic
  /// across a platform channel — but the drain sits immediately before it, and
  /// a move that still slips through asks for another pass (see
  /// [_onHostAlarmEvent]).
  Future<void> _cancelExcept(
    Set<int> keep, {
    bool Function(int id, ScheduledAlarmInfo info)? stillWanted,
  }) async {
    await scheduler.applyHostAlarmEvents();
    final armed = await scheduler.scheduledAlarms();
    for (final entry in armed.entries) {
      final id = entry.key;
      if (keep.contains(id)) continue;
      if (stillWanted != null && stillWanted(id, entry.value)) {
        continue;
      }
      if (await scheduler.isRinging(id)) continue;
      await scheduler.cancel(id);
    }
  }
}
