import 'package:arunoday/src/controller.dart';
import 'package:arunoday/src/sound_selection.dart' as sound;
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeScheduler implements AlarmScheduler {
  final Map<int, DateTime> scheduled = {};
  final Set<int> ringing = {};

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<void> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double volume,
  }) async {
    scheduled[id] = at;
  }

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);

  @override
  Future<Set<int>> scheduledIds() async => scheduled.keys.toSet();

  @override
  Future<bool> isRinging(int id) async => ringing.contains(id);
}

const tonk = SavedLocation(id: 'tonk', name: 'Tonk', lat: 26.17, lon: 75.79);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

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
    // 7-8 of each depending on time of day.
    expect(wakeIds.length, inInclusiveRange(7, 8));
    expect(bedIds.length, inInclusiveRange(7, 8));

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

  test('a polar active location: no-dawn flag, null plan, alarms cancelled',
      () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));
    expect(fake.scheduled, isNotEmpty);

    const pole = SavedLocation(id: 'sp', name: 'South Pole', lat: -90, lon: 0);
    await c.update(c.settings.copyWith(
      locations: [tonk, pole],
      activeLocationId: () => 'sp',
    ));
    expect(c.activeLocationHasNoDawn, isTrue);
    expect(c.plan, isNull);
    expect(fake.scheduled, isEmpty,
        reason: 'an unusable location cancels all alarms');
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
    final base = c.nextWake!;

    await c.setOneTimeExtra(120);
    final shifted = c.nextWake!;
    expect(shifted.difference(base).inMinutes, 120);

    // Only the one dated wake moved; the day after is unshifted dawn+offset.
    final dayAfter = shifted.add(const Duration(days: 1));
    final baseDayAfter = c.baseWakeOn(dayAfter)!;
    expect(c.wakeOn(dayAfter), baseDayAfter);

    // Clearing works via 0.
    await c.setOneTimeExtra(0);
    expect(c.nextWake, base);
  });

  test('delayed bedtime schedules the 2999 reminder and expires', () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(const ArunodaySettings(
      locations: [tonk],
      activeLocationId: 'tonk',
    ));

    await c.delayBedtime(const Duration(minutes: 30));
    expect(fake.scheduled.containsKey(2999), isTrue);
    expect(
      fake.scheduled[2999]!.difference(DateTime.now()).inMinutes,
      inInclusiveRange(28, 30),
    );

    // Mistap recovery: cancelling removes the re-ring entirely.
    await c.cancelBedtimeDelay();
    expect(c.settings.bedtimeDelayedUntil, isNull);
    expect(fake.scheduled.containsKey(2999), isFalse);

    // Simulate the reminder having fired: expired timers clear on resync.
    await c.update(c.settings.copyWith(
      bedtimeDelayedUntil: () =>
          DateTime.now().subtract(const Duration(minutes: 1)),
    ));
    await c.resync();
    expect(c.settings.bedtimeDelayedUntil, isNull);
    expect(fake.scheduled.containsKey(2999), isFalse);
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
}
