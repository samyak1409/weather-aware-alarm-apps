import 'package:arunoday/src/controller.dart';
import 'package:arunoday/src/ids.dart';
import 'package:arunoday/src/sound_selection.dart' as sound;
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeScheduler implements AlarmScheduler {
  final Map<int, DateTime> scheduled = {};

  /// Notification titles/bodies by id. A1/A2 copy is the only user-facing
  /// string this controller builds, and nothing asserted it before 2026-07-22.
  final Map<int, String> titles = {};
  final Map<int, String> bodies = {};
  final Set<int> ringing = {};

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<bool> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double? volume,
  }) async {
    scheduled[id] = at;
    titles[id] = title;
    bodies[id] = body;
    return true;
  }

  @override
  Future<void> cancel(int id) async {
    scheduled.remove(id);
    titles.remove(id);
    bodies.remove(id); // keep the maps in step, or stale copy lingers
  }

  @override
  Future<Set<int>> scheduledIds() async => (await scheduledAlarms()).keys.toSet();

  @override
  Future<bool> isRinging(int id) async => ringing.contains(id);

  /// True — Arunoday's real scheduler on Android, the platform this fake
  /// stands in for, reports host moves and drops.
  @override
  bool get reportsHostEvents => true;

  @override
  Future<void> applyHostAlarmEvents() async {}

  /// Extra live platform alarms hiding under an id — the iOS shape, where a
  /// refused cancel leaves an older UUID armed beside the newest.
  final Map<int, int> extraHandles = {};

  @override
  Future<Map<int, ScheduledAlarmInfo>> scheduledAlarms() async => {
        for (final e in scheduled.entries)
          e.key: ScheduledAlarmInfo(
            id: e.key,
            dateTime: e.value,
            handles: 1 + (extraHandles[e.key] ?? 0),
          ),
      };

  Future<void> Function(HostAlarmEvent event)? hostHandler;

  @override
  void setHostAlarmEventHandler(
    Future<void> Function(HostAlarmEvent event)? handler,
  ) {
    hostHandler = handler;
  }
}

/// A scheduler whose first plugin call fails. **`scheduledAlarms` is the one
/// every resync reaches**, location or not — it is what both the preserve scan
/// and `_cancelExcept` read. It used to be `scheduledIds`; when that became a
/// view over this, overriding it stopped intercepting anything and this seam
/// silently proved nothing.
class _ThrowingScheduler extends FakeScheduler {
  _ThrowingScheduler(this.error);
  final Object error;

  @override
  Future<Map<int, ScheduledAlarmInfo>> scheduledAlarms() async {
    // ignore: only_throw_errors — test seam for the Exception vs Error policy
    throw error;
  }
}

const tonk = SavedLocation(id: 'tonk', name: 'Tonk', lat: 26.17, lon: 75.79);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a plugin failure at startup costs the alarms, not the screen', () async {
    // REVIEW #15. `init` armed the window BEFORE setting `loaded`, and home
    // renders nothing until then — so one plugin throw left a permanently
    // black app, traced only by a console line.
    final c = ArunodayController(
        store: ArunodayStore(), scheduler: _ThrowingScheduler(Exception('x')));
    var notified = 0;
    c.addListener(() => notified++);
    await c.init();
    expect(c.loaded, isTrue);
    expect(notified, greaterThan(0), reason: 'the screen was told to draw');
  });

  test('the screen is told to draw only once the plan is ready', () async {
    // The other side of #15's reordering: moving `loaded` ahead of the arming
    // must NOT drag `plan` with it. Home reads it for the bedtime clock, so a
    // first frame without it prints `—` and fills it in a moment later — a
    // black screen traded for a flicker.
    final store = ArunodayStore();
    await store.save(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    final c = ArunodayController(store: store, scheduler: FakeScheduler());
    SleepPlanResult? planAtFirstNotify;
    var notified = false;
    c.addListener(() {
      if (notified) return;
      notified = true;
      planAtFirstNotify = c.plan;
    });
    await c.init();
    expect(notified, isTrue);
    expect(planAtFirstNotify, isNotNull);
  });

  test('a programming Error still propagates — but the screen is up first',
      () async {
    // Two halves in one: soft-failing is for Exceptions only, so this escapes
    // — and it escapes AFTER `loaded`, which is the ordering fix. The old
    // order threw first and `loaded` stayed false.
    final c = ArunodayController(
        store: ArunodayStore(), scheduler: _ThrowingScheduler(StateError('b')));
    await expectLater(c.init(), throwsStateError);
    expect(c.loaded, isTrue);
  });

  test('no location -> nothing scheduled', () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    expect(fake.scheduled, isEmpty);
    expect(c.nextWake, isNull);
  });

  test('with a location: rolling window of wake + bedtime alarms', () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));

    final wakeIds = fake.scheduled.keys.where((id) => id < 2000);
    final bedIds = fake.scheduled.keys.where((id) => id >= 2000);
    // 6-7 of each depending on time of day (window is ArunodayIds.slots).
    expect(wakeIds.length, inInclusiveRange(6, 7));
    expect(bedIds.length, inInclusiveRange(6, 7));

    // Every scheduled moment is in the future.
    for (final at in fake.scheduled.values) {
      expect(at.isAfter(DateTime.now()), isTrue);
    }

    // Bedtime falls out of the sleep plan (Tonk: ~22:00 zone).
    expect(c.bedtimeMinutes, isNotNull);
    expect(c.plan!.feasible, isTrue);
  });

  test('disabling wake cancels wake alarms but keeps bedtime', () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    await c.update(c.settings.copyWith(wakeEnabled: false));

    expect(fake.scheduled.keys.where((id) => id < 2000), isEmpty);
    expect(fake.scheduled.keys.where((id) => id >= 2000), isNotEmpty);
  });

  test('existingLocationSameDawn dedups by dawn-to-the-minute, not distance',
      () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    // A spot ~10 km from Tonk: far beyond 1 km, but same dawn to the minute
    // → still a functional duplicate (distance would have missed this).
    expect(c.existingLocationSameDawn(26.20, 75.80)?.id, 'tonk');
    // A clearly different city (Delhi, ~250 km) → different dawn → allowed.
    expect(c.existingLocationSameDawn(28.61, 77.20), isNull);
  });

  test("daily bedtime rolls to tomorrow once tonight's has passed", () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    final bed = c.bedtimeMinutes!.round();
    // The scenario times below assume a pre-midnight evening bedtime.
    expect(bed, inInclusiveRange(21 * 60, 23 * 60), reason: 'Tonk ~22:00 zone');

    // At 06:00, tonight's bedtime is still ahead → today's occurrence.
    expect(c.nextDailyBedtime(DateTime(2026, 7, 20, 6, 0)),
        clockTimeOn(DateTime(2026, 7, 20), bed));

    // At 23:59 it has passed → rolls to tomorrow.
    expect(c.nextDailyBedtime(DateTime(2026, 7, 20, 23, 59)),
        clockTimeOn(DateTime(2026, 7, 21), bed));
  });

  test('nextBedtimeRing is the sooner of the daily bedtime and a pending AGAIN',
      () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    final daily = c.nextBedtimeRing!; // no AGAIN yet → the daily bedtime
    expect(daily.isAfter(DateTime.now()), isTrue);

    final soon = DateTime.now().add(const Duration(minutes: 1));
    await c.update(c.settings.copyWith(bedtimeDelayedUntil: () => soon));
    expect(c.nextBedtimeRing, soon.isBefore(daily) ? soon : daily);
  });

  test('bedtime colliding with a pending re-ring: re-ring wins the slot; '
      'cancelling it restores the daily bedtime', () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));

    final daily = c.nextBedtimeRing!; // next daily bedtime, no AGAIN yet
    // Park a re-ring on that exact minute (what the old validation forbade).
    await c.update(c.settings.copyWith(bedtimeDelayedUntil: () => daily));

    expect(fake.scheduled[ArunodayIds.bedtimeAgain], daily, reason: 're-ring holds the slot');
    final collidingDaily = fake.scheduled.entries
        .where((e) => e.key >= 2000 && e.key < ArunodayIds.bedtimeAgain && e.value == daily);
    expect(collidingDaily, isEmpty,
        reason: 'the daily bedtime that shares the minute is suppressed');

    // Cancel the re-ring → the daily bedtime takes the slot back.
    await c.update(c.settings.copyWith(bedtimeDelayedUntil: () => null));
    expect(fake.scheduled.containsKey(ArunodayIds.bedtimeAgain), isFalse);
    final restored = fake.scheduled.entries
        .where((e) => e.key >= 2000 && e.key < ArunodayIds.bedtimeAgain && e.value == daily);
    expect(restored, isNotEmpty, reason: 'daily bedtime returns, now alone');
  });

  test('an expired one-time wake extra auto-clears on resync', () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    await c.update(c.settings.copyWith(
      oneTimeExtraMinutes: 120,
      oneTimeExtraDate: () => '2020-01-01', // long past
    ));
    await c.resync();
    expect(c.settings.oneTimeExtraDate, isNull);
    expect(c.settings.oneTimeExtraMinutes, 0);
  });

  test('arunodaySoundForVolume falls back to the default, else the selection',
      () {
    sound.selectedSoundPath = null;
    expect(sound.arunodaySoundForVolume(1.0), sound.arunodayDefaultSound);
    sound.selectedSoundPath = '/system/media/audio/alarms/Beep.ogg';
    expect(sound.arunodaySoundForVolume(0.5),
        '/system/media/audio/alarms/Beep.ogg');
    sound.selectedSoundPath = null; // reset for other tests
  });

  test('manual bedtime is a signed offset from the auto plan', () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    final auto = c.plan!.bedtimeMinutes;
    await c.update(c.settings.copyWith(bedtimeOffsetMinutes: () => 60));
    expect(c.bedtimeMinutes, (auto + 60) % 1440);
    expect(c.bedtimeModeDescription, 'Auto+1:00');
  });

  test('one-time extra shifts only the next wake, then auto-clears', () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    // ONE clock sample for every read here. `nextWake` reads `DateTime.now()`
    // per call, so `base` and `shifted` straddling the wake minute (05:32 for
    // Tonk, where `_firstFuture` flips from today's morning to tomorrow's)
    // would compare two different mornings and fail by a day rather than by
    // the 120 minutes under test. `nextWakeAt` is the seam for exactly this.
    // Not midnight: near it the stamp already sits on tomorrow, and a crossing
    // re-bases the window walk onto that same day, so it stays in range.
    final now = DateTime.now();
    final base = c.nextWakeAt(now)!;

    await c.setOneTimeExtra(120);
    final shifted = c.nextWakeAt(now)!;
    expect(shifted.difference(base).inMinutes, 120);

    // Only ONE morning moved — asserted across the whole window rather than on
    // a hand-stepped "day after". `wakeOn`'s argument is a calendar DATE, but
    // the instant it returns can land on a different one (dawn is computed in
    // UTC and converted at the end), so on a device far from the location's
    // longitude `calendarDay(shifted, 1)` is the argument day that produces
    // `shifted` ITSELF and the old assertion read the extra as leaking onto a
    // second morning. Same instant-vs-argument confusion as the bug in
    // `_clearExpiredOneTimers` this test now covers.
    final moved = [
      for (var i = 0; i <= ArunodayController.windowDays; i++)
        calendarDay(now, i),
    ].where((d) => c.wakeOn(d) != c.baseWakeOn(d)).toList();
    expect(moved, hasLength(1), reason: 'exactly one morning carries the extra');
    expect(c.wakeOn(moved.single), shifted);

    // Clearing works via 0.
    await c.setOneTimeExtra(0);
    expect(c.nextWakeAt(now), base);
  });

  test('delayed bedtime schedules the re-ring reminder and expires', () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));

    await c.delayBedtime(const Duration(minutes: 30));
    expect(fake.scheduled.containsKey(ArunodayIds.bedtimeAgain), isTrue);
    expect(
      fake.scheduled[ArunodayIds.bedtimeAgain]!.difference(DateTime.now()).inMinutes,
      inInclusiveRange(28, 30),
    );

    // Mistap recovery: cancelling removes the re-ring entirely.
    await c.cancelBedtimeDelay();
    expect(c.settings.bedtimeDelayedUntil, isNull);
    expect(fake.scheduled.containsKey(ArunodayIds.bedtimeAgain), isFalse);

    // Simulate the reminder having fired: expired timers clear on resync.
    await c.update(c.settings.copyWith(
      bedtimeDelayedUntil: () =>
          DateTime.now().subtract(const Duration(minutes: 1)),
    ));
    await c.resync();
    expect(c.settings.bedtimeDelayedUntil, isNull);
    expect(fake.scheduled.containsKey(ArunodayIds.bedtimeAgain), isFalse);
  });

  test('sleep starts at max(bedtime, AGAIN); a too-late re-ring is ignored',
      () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));

    // No re-ring yet: sleep starts at the daily bedtime.
    final daily = c.sleepStartMoment!;
    expect(daily.isBefore(c.nextWake!), isTrue);

    // A re-ring later than the daily bedtime (just before wake, so future
    // and after the bedtime) wins — sleep-start = max(bedtime, AGAIN).
    final later = c.nextWake!.subtract(const Duration(minutes: 1));
    await c.update(c.settings.copyWith(bedtimeDelayedUntil: () => later));
    expect(c.sleepStartMoment, later);

    // A re-ring AFTER the next wake is nonsense (can't sleep after waking):
    // ignored, sleep falls back to the daily bedtime before the wake.
    await c.update(c.settings.copyWith(
      bedtimeDelayedUntil: () => c.nextWake!.add(const Duration(minutes: 5)),
    ));
    expect(c.sleepStartMoment!.isBefore(c.nextWake!), isTrue);
    expect(c.tonightSleepMinutes! < 12 * 60, isTrue);
  });

  test('resync never cancels an alarm that is mid-ring', () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));

    // A ringing alarm's moment is in the past, so it is never in the wanted
    // window — the old sweep cancelled (= silenced) it on every app resume.
    fake.scheduled[2500] =
        DateTime.now().subtract(const Duration(seconds: 30));
    fake.ringing.add(2500);
    await c.resync();
    expect(fake.scheduled.containsKey(2500), isTrue,
        reason: 'ringing alarm must survive resync');

    fake.ringing.remove(2500);
    await c.resync();
    expect(fake.scheduled.containsKey(2500), isFalse,
        reason: 'once the ring ends, the stale id is swept');
  });

  test('deleting the last location never silences an alarm that is ringing',
      () async {
    // REVIEW #3. Losing the location disarms everything — and that path
    // cancelled unconditionally, twenty lines below the ringing guard the
    // resync loop already had. Delete your last location while the bedtime
    // alarm is sounding and the sound stopped.
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    expect(fake.scheduled, isNotEmpty, reason: 'something to disarm');

    fake.scheduled[2500] =
        DateTime.now().subtract(const Duration(seconds: 30));
    fake.ringing.add(2500);

    await c.update(const ArunodaySettings()); // the last location, deleted

    expect(fake.scheduled.keys, [2500],
        reason: 'every future alarm is disarmed, the audible one is not');

    // And it is not immortal — the next resync after it stops sweeps it.
    fake.ringing.remove(2500);
    await c.resync();
    expect(fake.scheduled, isEmpty);
  });

  test('every user-facing time is a whole minute (dawn quantized)', () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));

    final now = DateTime.now();
    expect(c.dawnOn(now)!.second, 0);
    expect(c.sunriseOn(now)!.second, 0);
    expect(c.nextWake!.second, 0);
    for (final at in fake.scheduled.values) {
      expect(at.second, 0, reason: 'alarms must ring on the minute');
    }
  });

  test('wake offset never moves the auto bedtime', () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    final bed = c.bedtimeMinutes;

    await c.update(c.settings.copyWith(wakeOffsetMinutes: 385)); // +6:25
    expect(c.bedtimeMinutes, bed, reason: 'bedtime anchors to pure dawn');
  });

  test('A1/A2 titles capitalise Dawn/Bedtime; A1 offset hangs off Dawn',
      () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    // Wake ids < 2000, bedtime 2000+. Collect — an empty set must fail here,
    // not pass vacuously.
    List<String> wakeTitles() => [
          for (final e in fake.titles.entries)
            if (e.key < 2000) e.value
        ];
    List<String> bedTitles() => [
          for (final e in fake.titles.entries)
            if (e.key >= 2000 && e.key < ArunodayIds.bedtimeAgain) e.value
        ];
    List<String> wakeBodies() => [
          for (final e in fake.bodies.entries)
            if (e.key < 2000) e.value
        ];

    expect(wakeTitles(), isNotEmpty);
    expect(wakeTitles(), everyElement('Arunoday · Dawn'));
    expect(bedTitles(), isNotEmpty);
    expect(bedTitles(), everyElement('Arunoday · Bedtime'));

    // Offset 0 — the wake IS the dawn, so there's no offset to print at all.
    expect(wakeBodies(), isNotEmpty);
    expect(wakeBodies(), everyElement('First light at Tonk. Good morning.'));

    await c.update(c.settings.copyWith(wakeOffsetMinutes: 20));
    // "Dawn+0:20", never "Dawn +0:20" — word and offset are one value, as in
    // A6's "DAWN+0:20" and A7's "AUTO+0:30" (2026-07-22).
    expect(wakeBodies(), isNotEmpty);
    expect(wakeBodies(), everyElement('Dawn+0:20 at Tonk. Good morning.'));
    expect(wakeTitles(), everyElement('Arunoday · Dawn'));
  });

  test('wake offset shifts nextWake', () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    final base = c.nextWake!;
    await c.update(c.settings.copyWith(wakeOffsetMinutes: 120));
    final shifted = c.nextWake!;
    // +2h offset moves the wake 2h later (modulo crossing into a new day's
    // dawn, which drifts by <2 min).
    final delta = shifted.difference(base).inMinutes;
    expect((delta - 120).abs() <= 3 || (delta - 120 + 1440).abs() <= 5, isTrue,
        reason: 'delta was $delta');
  });

  test('an edit is never mistaken for a host deferral', () async {
    // A deferral exists because the ring TRIED to fire and was refused, so
    // before the alarm's own moment there is nothing to have deferred. Without
    // that test, a plugin time sitting a minute ahead of a future alarm read as
    // a deferral — so nudging wake one minute EARLIER the night before was
    // silently ignored and the alarm went on ringing at the old time.
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    final id = fake.scheduled.keys.firstWhere((k) => k < 2000);
    final old = fake.scheduled[id]!;

    // Move every wake one minute earlier; the plugin still holds the old time,
    // one minute AHEAD of what we now want — the exact shape of a deferral.
    await c.update(c.settings
        .copyWith(wakeOffsetMinutes: c.settings.wakeOffsetMinutes - 1));

    expect(fake.scheduled[id], isNot(old),
        reason: 'the edit must actually move the alarm');
    expect(fake.scheduled[id]!.isBefore(old), isTrue);
  });

  test('a short host deferral IS preserved once the alarm was due', () async {
    // The control for the test above, and the case that is real: the logical
    // minute has arrived, the platform refused the ring and re-armed it ~30s
    // out. The keep-set alone is insufficient here — the schedule loop must
    // also skip preserved ids, or it re-arms at the logical minute and throws
    // the deferral away.
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    final id = fake.scheduled.keys.firstWhere((k) => k < 2000);
    final logical = fake.scheduled[id]!;
    final deferred = logical.add(const Duration(seconds: 30));
    fake.scheduled[id] = deferred;

    await c.syncArmsAt(logical.add(const Duration(seconds: 5)));

    expect(fake.scheduled[id], deferred,
        reason: 'preserved deferral must not be rewritten to the floor minute');
  });

  test('deferral survives resync after logical T but before deferral fires',
      () async {
    // Medium gap: logical minute past drops id from wanted — preserve must
    // still keep a future +30s plugin booking via expectedById.
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    final id = fake.scheduled.keys.firstWhere((k) => k < 2000);
    final logical = fake.scheduled[id]!;
    final deferred = logical.add(const Duration(seconds: 30));
    fake.scheduled[id] = deferred;
    final midWindow = logical.add(const Duration(seconds: 10));
    await c.syncArmsAt(midWindow);
    expect(fake.scheduled[id], deferred,
        reason: 'deferral must stay armed between logical T and T+30s');
  });

  test('an edit that moves wake far away does not preserve a leftover deferral',
      () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    final id = fake.scheduled.keys.firstWhere((k) => k < 2000);
    final stale = fake.scheduled[id]!;
    // Pretend the plugin still holds +30s on the OLD minute after the user
    // pushed wake two hours later — that leftover must be cancelled/re-armed.
    fake.scheduled[id] = stale.add(const Duration(seconds: 30));
    await c.update(c.settings.copyWith(wakeOffsetMinutes: 120));
    final now = fake.scheduled[id];
    expect(now, isNotNull);
    expect(now!.difference(stale).inMinutes.abs(), greaterThan(2),
        reason: 'stale leftover must not be preserved across a real edit');
  });
  test('a host event before init never disarms the window', () async {
    // `main` builds the controller BEFORE starting the plugin, because
    // `Alarm.init()` replays every event the host recorded while no engine was
    // running. Those replays therefore arrive with settings unread — and the
    // no-location branch of `_arm` cancels EVERYTHING, so one of them at launch
    // would have disarmed the user's whole window before the app had finished
    // reading it back.
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    expect(fake.hostHandler, isNotNull,
        reason: 'the handler must be registered by the constructor');
    // Seed the plugin the way a previous run would have left it.
    fake.scheduled[ArunodayIds.bedtimeAgain] =
        DateTime.now().add(const Duration(hours: 5));

    await fake.hostHandler!(HostAlarmEvent(
      id: ArunodayIds.bedtimeAgain,
      kind: HostAlarmEventKind.dropped,
      cause: HostAlarmEventCause.platformRefusal,
      recordedAt: DateTime.now(),
      at: DateTime.now(),
    ));

    expect(c.loaded, isFalse);
    expect(fake.scheduled, isNotEmpty,
        reason: 'an event before init must not reach the cancel-all branch');

    // ...and swallowing it loses nothing, because `init` rebuilds the whole
    // window as soon as settings are read. That is the only reason the early
    // return is allowed to consume the event.
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    expect(fake.scheduled.keys.where((k) => k < 2000), isNotEmpty,
        reason: 'the resync init runs anyway supersedes the dropped event');
  });

  test('a host event after init rebuilds the window', () async {
    // The control for the guard above: once settings are loaded the same event
    // must actually do something, or the guard would be indistinguishable from
    // a handler that had been disconnected.
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    final wakeId = fake.scheduled.keys.firstWhere((k) => k < 2000);
    // The host dropped it: gone from the plugin, and nothing else re-arms it.
    fake.scheduled.remove(wakeId);

    await fake.hostHandler!(HostAlarmEvent(
      id: wakeId,
      kind: HostAlarmEventKind.dropped,
      cause: HostAlarmEventCause.staleAtBoot,
      recordedAt: DateTime.now(),
      at: DateTime.now(),
    ));

    expect(fake.scheduled.containsKey(wakeId), isTrue,
        reason: 'a dropped alarm the config still wants is re-armed');
  });

  test('a deferral that lands during the pass is not cancelled by it',
      () async {
    // The keep-set is computed from a snapshot; a move arriving after it makes
    // an id worth keeping that was not worth keeping when the set was built.
    // Cancelling it there loses the ring for good — its own minute is already
    // past, so nothing puts it back.
    final fake = _MovesDuringCancel();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    final wakeId = fake.scheduled.keys.firstWhere((k) => k < 2000);
    final logical = fake.scheduled[wakeId]!;

    fake.moveOnNextRead = (wakeId, logical.add(const Duration(seconds: 30)));
    await c.syncArmsAt(logical.add(const Duration(seconds: 10)));

    expect(fake.scheduled[wakeId], logical.add(const Duration(seconds: 30)),
        reason: 'the late-arriving deferral survives the cancel loop');
  });

  test('an id hiding a second live alarm is re-armed, never preserved',
      () async {
    // iOS only: `scheduleRing` creates before it cancels, so a refused cancel
    // leaves the OLD alarm armed under the same id (REVIEW #5, deliberate).
    // The newest handle can sit at the right minute while the straggler stays
    // at the one the user edited away from — and `scheduleRing` is the ONLY
    // thing that ever retries those cancels. Preserving skips it, so a
    // "duplicate you can stop" would quietly become permanent.
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    final id = fake.scheduled.keys.firstWhere((k) => k < 2000);
    final logical = fake.scheduled[id]!;

    // Exactly where it should be — but with a straggler underneath it.
    fake.extraHandles[id] = 1;
    fake.titles.remove(id);

    await c.syncArmsAt(logical.subtract(const Duration(minutes: 5)));

    expect(fake.scheduled[id], logical);
    expect(fake.titles[id], isNotNull,
        reason: 'the id was re-armed, which is what retries the failed cancel');
  });

}



/// Applies a host move in the gap between the preserve snapshot and the cancel
/// loop — the window `_cancelExcept`'s re-read exists to cover.
class _MovesDuringCancel extends FakeScheduler {
  (int, DateTime)? moveOnNextRead;

  @override
  Future<Map<int, ScheduledAlarmInfo>> scheduledAlarms() async {
    final move = moveOnNextRead;
    if (move == null) return super.scheduledAlarms();
    // Once: the preserve scan sees the OLD time, the move lands immediately
    // after it, and the cancel loop's own read is the first to see the new one.
    moveOnNextRead = null;
    final snapshot = await super.scheduledAlarms();
    scheduled[move.$1] = move.$2;
    return snapshot;
  }
}
