import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/alarm_time_conflict.dart';
import 'package:nivaat/src/controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'silent_fakes.dart';

void main() {
  const a = NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1');
  const bSameTime = NivaatAlarm(id: 2, hour: 6, minute: 0, courtId: 'c2');
  const cDiffMinute = NivaatAlarm(id: 3, hour: 6, minute: 1, courtId: 'c1');

  test('nivaatAlarmTimeConflict: same HH:MM refuses (any court)', () {
    expect(nivaatAlarmTimeConflict([a], bSameTime),
        'Another alarm is already at 06:00.');
    expect(nivaatAlarmTimeConflict([a], cDiffMinute), isNull);
  });

  test('nivaatAlarmTimeConflict: editing the same id is fine', () {
    expect(
      nivaatAlarmTimeConflict(
        [a],
        a.copyWith(courtId: 'c2', weekdays: {1, 2, 3}),
      ),
      isNull,
    );
  });

  test('nivaatAlarmTimeConflict: ignores weekdays / enabled', () {
    const disabledOtherDay = NivaatAlarm(
      id: 9,
      hour: 6,
      minute: 0,
      courtId: 'c1',
      enabled: false,
      weekdays: {7}, // Sunday only; [a] is every day
    );
    expect(
      nivaatAlarmTimeConflict([a], disabledOtherDay),
      'Another alarm is already at 06:00.',
    );
  });

  group('NivaatController.upsertAlarm', () {
    late NivaatController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final store = NivaatStore();
      await store.saveCourts([
        const SavedLocation(id: 'c1', name: 'A', lat: 12.9, lon: 77.6),
        const SavedLocation(id: 'c2', name: 'B', lat: 12.91, lon: 77.61),
      ]);
      controller = NivaatController(engine: silentEngine(store));
      await controller.init();
    });

    test('refuses a second alarm at the same clock time', () async {
      expect(await controller.upsertAlarm(a), isTrue);
      expect(controller.alarms, hasLength(1));
      expect(await controller.upsertAlarm(bSameTime), isFalse);
      expect(controller.alarms, hasLength(1), reason: 'collision not persisted');
      expect(controller.alarms.single.id, 1);
    });

    test('allows ±1 minute (intentional multi-court workaround)', () async {
      expect(await controller.upsertAlarm(a), isTrue);
      expect(await controller.upsertAlarm(cDiffMinute), isTrue);
      expect(controller.alarms.map((x) => x.id), [1, 3]);
    });

    test('allows re-saving the same alarm at the same time', () async {
      expect(await controller.upsertAlarm(a), isTrue);
      expect(await controller.upsertAlarm(a.copyWith(courtSpeedLimitKmh: 5)),
          isTrue);
      expect(controller.alarms.single.courtSpeedLimitKmh, 5);
    });
  });
}
