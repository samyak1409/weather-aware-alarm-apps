import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

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

  SavedLocation? get activeLocation => settings.activeLocation;

  /// Fixed bedtime in minutes-after-midnight (override wins over auto plan).
  double? get bedtimeMinutes =>
      settings.bedtimeOverrideMinutes?.toDouble() ?? plan?.bedtimeMinutes;

  /// Civil dawn for [date] at the active location.
  DateTime? dawnOn(DateTime date) {
    final loc = activeLocation;
    if (loc == null) return null;
    return Solar.civilDawnLocal(date, loc.lat, loc.lon);
  }

  /// Wake time (dawn + offset) for [date].
  DateTime? wakeOn(DateTime date) => dawnOn(date)
      ?.add(Duration(minutes: settings.wakeOffsetMinutes));

  /// The next wake alarm moment strictly after now.
  DateTime? get nextWake {
    final now = DateTime.now();
    for (var i = 0; i <= windowDays; i++) {
      final w = wakeOn(now.add(Duration(days: i)));
      if (w != null && w.isAfter(now)) return w;
    }
    return null;
  }

  /// Tonight's sleep duration in minutes: next bedtime -> following wake.
  double? get tonightSleepMinutes {
    final bed = bedtimeMinutes;
    final nw = nextWake;
    if (bed == null || nw == null) return null;
    final wakeM = nw.hour * 60.0 + nw.minute;
    return (wakeM + 1440.0 - bed) % 1440.0;
  }

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

  /// Called on app resume: keeps the rolling window fresh.
  Future<void> resync() => _recomputeAndResync().then((_) => notifyListeners());

  Future<void> _recomputeAndResync() async {
    final loc = activeLocation;
    if (loc == null) {
      plan = null;
      await _cancelAll();
      return;
    }
    plan = SleepPlan.forLocation(
      year: DateTime.now().year,
      latDeg: loc.lat,
      lonDeg: loc.lon,
      wakeOffsetMinutes: settings.wakeOffsetMinutes,
    );

    final now = DateTime.now();
    final wanted = <int, ({DateTime at, String title, String body})>{};

    if (settings.wakeEnabled) {
      for (var i = 0; i <= windowDays; i++) {
        final wake = wakeOn(now.add(Duration(days: i)));
        if (wake != null && wake.isAfter(now)) {
          wanted[1000 + i] = (
            at: wake,
            title: 'Arunoday · dawn',
            body: 'First light at ${loc.name}. Good morning.',
          );
        }
      }
    }

    final bed = bedtimeMinutes;
    if (settings.bedtimeEnabled && bed != null) {
      for (var i = 0; i <= windowDays; i++) {
        final day = now.add(Duration(days: i));
        final at = DateTime(day.year, day.month, day.day)
            .add(Duration(minutes: bed.round()));
        if (at.isAfter(now)) {
          wanted[2000 + i] = (
            at: at,
            title: 'Arunoday · bedtime',
            body: 'Wind down — dawn comes early.',
          );
        }
      }
    }

    final existing = await scheduler.scheduledIds();
    for (final id in existing) {
      if (!wanted.containsKey(id)) await scheduler.cancel(id);
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
