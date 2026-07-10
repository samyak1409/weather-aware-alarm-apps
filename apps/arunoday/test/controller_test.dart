import 'package:arunoday/src/controller.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeScheduler implements AlarmScheduler {
  final Map<int, DateTime> scheduled = {};

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
  Future<bool> isRinging(int id) async => false;
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

  test('bedtime override wins over auto plan', () async {
    final fake = FakeScheduler();
    final c = ArunodayController(store: ArunodayStore(), scheduler: fake);
    await c.init();
    await c.update(ArunodaySettings(
      locations: const [tonk],
      activeLocationId: 'tonk',
      bedtimeOverrideMinutes: 21 * 60 + 30,
    ));
    expect(c.bedtimeMinutes, 21 * 60 + 30);
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
