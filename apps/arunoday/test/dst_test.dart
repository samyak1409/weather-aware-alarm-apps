import 'package:arunoday/src/controller.dart';
import 'package:arunoday/src/ids.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'controller_test.dart' show FakeScheduler;

const _tonk = SavedLocation(id: 'tonk', name: 'Tonk', lat: 26.17, lon: 75.79);

/// **The DST batch, Arunoday half** (REVIEW #11 · #13 · #14).
///
/// Split by what a test can pin, because **a test that only sees "this week"
/// is soft nine months of the year** — a 7-day window opened in August holds
/// no clock change, so an invariant over it passes against the broken code
/// even under `TZ=America/New_York`. The three that take `now` therefore stand
/// on the real 2026 transitions and fail there when reverted:
/// [ArunodayController.nextDailyBedtime] (#14, the reported instant),
/// [ArunodayController.bedtimeWindowAt] (#11, what arms the bedtime) and
/// [ArunodayController.nextWakeAt] (#13, the walk behind the countdown and
/// "+2h tomorrow"). The last test is the cheap net over the call sites.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ArunodayController> armed(FakeScheduler fake) async {
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [_tonk],
      activeLocationId: 'tonk',
    ));
    return c;
  }

  List<DateTime> sorted(Iterable<MapEntry<int, DateTime>> e) =>
      e.map((x) => x.value).toList()..sort();

  test('a bedtime just past midnight rolls to the next DATE (REVIEW #14)',
      () async {
    final c = await armed(FakeScheduler());
    // ~00:15, so 00:30 on the fall-back Sunday is already past it.
    final auto = c.plan!.bedtimeMinutes;
    await c.update(
        c.settings.copyWith(bedtimeOffsetMinutes: () => (15 - auto).round()));
    final bed = c.bedtimeMinutes!.round();
    expect(bed, lessThan(30),
        reason: 'the scenario needs a bedtime already past at 00:30');

    // Was 2026-11-01 23:15 — the same evening, from adding 24 elapsed hours
    // to a day that had 25 of them.
    final at = c.nextDailyBedtime(DateTime(2026, 11, 1, 0, 30))!;
    expect(at.month, 11);
    expect(at.day, 2, reason: 'the next date, not 23:xx tonight');
    expect(at.hour * 60 + at.minute, bed, reason: 'the same clock time');
  });

  test('an ordinary day resolves to today, then tomorrow', () async {
    // The everyday path, so a "fix" that always jumps a day fails here. `now`
    // sits either side of whatever the plan's bedtime is, not at a clock hour
    // that assumes an Indian device — that assumption is one of the three
    // reasons older tests fail under `TZ=America/New_York`, none of them DST
    // (see CLAUDE.md; the third is a real bug, filed).
    final c = await armed(FakeScheduler());
    final bed = c.bedtimeMinutes!.round();
    final day = DateTime(2026, 7, 20); // an ordinary date in every zone
    final tonight = clockTimeOn(day, bed);

    expect(c.nextDailyBedtime(tonight.subtract(const Duration(minutes: 1))),
        tonight);
    expect(c.nextDailyBedtime(tonight.add(const Duration(minutes: 1))),
        clockTimeOn(calendarDay(day, 1), bed));
  });

  test('the bedtime window is one CLOCK time per DATE (REVIEW #11)', () {
    // Pinned to weeks that contain a transition: `midnight + Duration(bed)`
    // gives 23:00 on 8 March and 21:00 on 1 November, and no window opened in
    // August can show that.
    for (final start in [DateTime(2026, 3, 6, 12), DateTime(2026, 10, 30, 12)]) {
      final window = ArunodayController.bedtimeWindowAt(start, 22 * 60);
      expect(window, hasLength(ArunodayController.windowDays));
      expect(
        window.map((d) => '${d.month}-${d.day}').toSet(),
        hasLength(ArunodayController.windowDays),
        reason: 'one per DATE, so no two share a locker (from $start)',
      );
      for (final at in window) {
        expect(at.hour, 22, reason: '$at (window from $start)');
        expect(at.minute, 0, reason: '$at (window from $start)');
      }
    }
  });

  test('nextWake picks the very next morning across a clock change (#13)',
      () async {
    // Pinned for the same reason, and the comparison is computed a different
    // way — every wake in reach, sorted, earliest still ahead — so it cannot
    // agree with a walk that skipped a date.
    final c = await armed(FakeScheduler());
    for (final change in [DateTime(2026, 3, 8), DateTime(2026, 11, 1)]) {
      final wake = c.wakeOn(change)!;
      final eve = clockTimeOn(calendarDay(wake, -1), 23 * 60 + 30);
      final ahead = [
        for (var i = -1; i <= ArunodayController.windowDays; i++)
          c.wakeOn(calendarDay(eve, i))
      ].whereType<DateTime>().where((w) => w.isAfter(eve)).toList()
        ..sort();
      expect(ahead, isNotEmpty, reason: 'from $eve');
      expect(c.nextWakeAt(eve), ahead.first, reason: 'from $eve');
    }
  });

  test('the screen and the scheduler agree about every alarm (#11 · #13)',
      () async {
    // The net over the call sites the pins above cannot reach. The scheduler
    // stepped calendar days while the screen stepped 24-hour blocks, so across
    // a spring-forward night the right alarm was armed and home counted down
    // to the morning after it. `sleepStartMoment` is here too: its step back a
    // day was `subtract(Duration(days: 1))`, which on a fall-back day lands
    // 23:00 the same date and puts one night's sleep an hour out.
    final fake = FakeScheduler();
    final c = await armed(fake);
    final bed = c.bedtimeMinutes!.round();
    final wakes = sorted(fake.scheduled.entries.where((e) => e.key < 2000));
    final beds = sorted(fake.scheduled.entries.where(
        (e) => e.key >= 2000 && e.key < ArunodayIds.bedtimeAgain));
    expect(wakes, isNotEmpty);
    expect(beds, isNotEmpty);
    expect(c.nextWake, wakes.first);
    expect(c.nextBedtimeRing, beds.first);
    for (final at in beds) {
      expect(at.hour * 60 + at.minute, bed, reason: '$at is not a clock time');
    }

    final start = c.sleepStartMoment!;
    expect(start.hour * 60 + start.minute, bed);
    expect(start.isBefore(c.nextWake!), isTrue);
    expect(c.tonightSleepMinutes, c.nextWake!.difference(start).inMinutes);
  });
}
