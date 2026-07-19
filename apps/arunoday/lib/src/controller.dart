import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

import 'sound_selection.dart' as sound;

/// App state + alarm orchestration for Arunoday.
///
/// Scheduling model (v1): a rolling window of the next [windowDays] wake and
/// bedtime alarms, resynced on every app open / settings change. Wake ids are
/// 1000+dayIndex, bedtime ids 2000+dayIndex.
class ArunodayController extends ChangeNotifier {
  ArunodayController({
    required this.store,
    required this.scheduler,
  });

  final ArunodayStore store;
  final AlarmScheduler scheduler;

  static const int windowDays = 7;

  ArunodaySettings settings = const ArunodaySettings();
  SleepPlanResult? plan;
  bool loaded = false;

  /// The active location has no daily dawn (polar / saved by an old build) —
  /// unusable; home shows a message instead of a broken plan.
  bool activeLocationHasNoDawn = false;

  SavedLocation? get activeLocation => settings.activeLocation;

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

  /// The next wake alarm moment strictly after now.
  DateTime? get nextWake {
    final now = DateTime.now();
    for (var i = 0; i <= windowDays; i++) {
      final w = wakeOn(now.add(Duration(days: i)));
      if (w != null && w.isAfter(now)) return w;
    }
    return null;
  }

  /// Next daily bedtime occurrence strictly after now (ignores AGAIN).
  @visibleForTesting
  DateTime? nextDailyBedtime(DateTime now) {
    final bed = bedtimeMinutes;
    if (bed == null) return null;
    var s = DateTime(now.year, now.month, now.day)
        .add(Duration(minutes: bed.round()));
    while (!s.isAfter(now)) {
      s = s.add(const Duration(days: 1));
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
      // strictly before it.
      daily = DateTime(w.year, w.month, w.day)
          .add(Duration(minutes: bed.round()));
      if (!daily.isBefore(w)) daily = daily.subtract(const Duration(days: 1));
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

  Future<void> init() async {
    settings = await store.load();
    await _recomputeAndResync();
    loaded = true;
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
    final now = DateTime.now();
    DateTime? nextBase;
    for (var i = 0; i <= windowDays; i++) {
      final w = baseWakeOn(now.add(Duration(days: i)));
      if (w != null && w.isAfter(now)) {
        nextBase = w;
        break;
      }
    }
    if (nextBase == null) return;
    await update(settings.copyWith(
      oneTimeExtraMinutes: minutes,
      oneTimeExtraDate: () => minutes == 0 ? null : _dateKey(nextBase!),
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
    sound.selectedSoundPath = settings.soundPath;
    _clearExpiredOneTimers();
    final loc = activeLocation;
    // Re-validate on every load/resync: a location saved by an older build
    // (before the polar guard) or one that lost its daily dawn is unusable —
    // don't render a degenerate plan for it.
    activeLocationHasNoDawn = loc != null &&
        !Solar.hasDailyDawnAllYear(DateTime.now().year, loc.lat, loc.lon);
    if (loc == null || activeLocationHasNoDawn) {
      plan = null;
      await _cancelAll();
      return;
    }
    // Auto bedtime anchors to pure dawn (offset 0): the wake offset moves
    // only the wake alarm, never the bedtime (user decision 2026-07-12).
    plan = SleepPlan.forLocation(
      year: DateTime.now().year,
      latDeg: loc.lat,
      lonDeg: loc.lon,
      wakeOffsetMinutes: 0,
    );

    final now = DateTime.now();
    final wanted = <int, ({DateTime at, String title, String body})>{};

    if (settings.wakeEnabled) {
      for (var i = 0; i <= windowDays; i++) {
        final day = now.add(Duration(days: i));
        final wake = wakeOn(day);
        if (wake != null && wake.isAfter(now)) {
          // "First light" is only honest when the wake IS the dawn.
          final dawn = dawnOn(day);
          final shift = dawn == null ? 0 : wake.difference(dawn).inMinutes;
          wanted[1000 + i] = (
            at: wake,
            title: 'Arunoday · dawn',
            body: shift == 0
                ? 'First light at ${loc.name}. Good morning.'
                : 'Dawn ${fmtOffset(shift)} at ${loc.name}. Good morning.',
          );
        }
      }
    }

    // A pending re-ring (below) wins a same-minute slot: skip the daily bedtime
    // that lands on it so only one alarm sounds. Cancelling the re-ring restores
    // the daily bedtime on the next resync (it's recomputed from scratch).
    final delayed = settings.bedtimeDelayedUntil;
    final reRing = (settings.bedtimeEnabled && delayed != null &&
            delayed.isAfter(now))
        ? _floorToMinute(delayed)
        : null;

    final bed = bedtimeMinutes;
    if (settings.bedtimeEnabled && bed != null) {
      for (var i = 0; i <= windowDays; i++) {
        final day = now.add(Duration(days: i));
        final at = DateTime(day.year, day.month, day.day)
            .add(Duration(minutes: bed.round()));
        if (at.isAfter(now) && at != reRing) {
          wanted[2000 + i] = (
            at: at,
            title: 'Arunoday · bedtime',
            body: 'Wind down — dawn comes early.',
          );
        }
      }
    }

    // "Not sleepy yet" delayed bedtime reminder from the ring screen.
    if (reRing != null) {
      wanted[2999] = (
        at: delayed!,
        title: 'Arunoday · bedtime',
        body: 'Second call — dawn does not snooze.',
      );
    }

    final existing = await scheduler.scheduledIds();
    for (final id in existing) {
      // Never cancel a ringing alarm: its moment is in the past so it can't
      // be in `wanted`, and cancelling silences it — opening the app during
      // a ring must not stop the ring.
      if (!wanted.containsKey(id) && !await scheduler.isRinging(id)) {
        await scheduler.cancel(id);
      }
    }
    for (final e in wanted.entries) {
      await scheduler.scheduleRing(
        id: e.key,
        at: e.value.at,
        title: e.value.title,
        body: e.value.body,
        volume: 1.0,
      );
    }
  }

  Future<void> _cancelAll() async {
    for (final id in await scheduler.scheduledIds()) {
      await scheduler.cancel(id);
    }
  }
}
