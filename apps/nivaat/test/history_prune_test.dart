import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'silent_fakes.dart';

/// A history row whose court is gone can't render — the sheet has no name to
/// show. `removeCourt` sweeps a court's log, but a background isolate holding a
/// stale courts list can land its row just *after* that sweep, so every load
/// prunes (2026-07-22). These tests stand in for that isolate by writing
/// straight to the store behind the controller's back.

HistoryRecord row(String courtId, {int alarmId = 1}) => HistoryRecord(
      alarmId: alarmId,
      courtId: courtId,
      at: DateTime(2026, 7, 18, 6, 0),
      checkedAt: DateTime(2026, 7, 18, 6, 0),
      outcome: CheckOutcome.rang,
      courtSpeedKmh: 3,
      rawGustKmh: 12,
      courtSpeedLimitKmh: 4,
      rawGustLimitKmh: 15,
      volume: 0.88,
    );

void main() {
  const live = SavedLocation(id: 'c1', name: 'A', lat: 12.9, lon: 77.6);

  late NivaatStore store;
  late NivaatController controller;

  Future<void> build({List<SavedLocation> courts = const [live]}) async {
    SharedPreferences.setMockInitialValues({});
    store = NivaatStore();
    await store.saveCourts(courts);
    controller = NivaatController(engine: silentEngine(store));
  }

  test('a row whose court is gone is dropped on load', () async {
    await build();
    await store.upsertHistory(row('c1'));
    await store.upsertHistory(row('deleted-court', alarmId: 2));

    await controller.init();

    expect(controller.history.map((h) => h.courtId), ['c1']);
  });

  test('and is deleted for good, not just hidden', () async {
    await build();
    await store.upsertHistory(row('deleted-court'));

    await controller.init();

    expect(await store.loadHistory(), isEmpty,
        reason: 'pruned rows must not linger in storage');
  });

  test('rows with a live court survive untouched', () async {
    await build();
    await store.upsertHistory(row('c1'));

    await controller.init();

    expect(controller.history, hasLength(1));
    expect(await store.loadHistory(), hasLength(1));
  });

  test('with no courts at all, every surviving row is an orphan', () async {
    // Deleting the last court already takes its history with it, so anything
    // left here has no court to render. Safe to prune because `[]` can only
    // mean "nothing saved": `_decodeList` returns it for an absent key and
    // throws on corrupt JSON, so a bad read can't pose as "no courts".
    await build(courts: const []);
    await store.upsertHistory(row('c1'));

    await controller.init();

    expect(await store.loadHistory(), isEmpty);
  });

  test('a background row landing after removeCourt is swept on next load',
      () async {
    await build();
    await controller.init();
    await controller.removeCourt('c1');

    // The isolate was mid-check with a stale courts list: its row arrives
    // after the delete already swept the log.
    await store.upsertHistory(row('c1'));
    expect(await store.loadHistory(), hasLength(1), reason: 'the orphan landed');

    await controller.resync();

    expect(controller.history, isEmpty);
  });

  group('deleting an alarm forgets its forecast verdict (2026-08-30)', () {
    // The verdict outlives the occurrence on purpose — the dot has to keep
    // saying something for tomorrow's alarm all day today — so no cascade
    // teardown reaches it and the delete paths have to sweep it themselves.
    // `nextAlarmId` hands a number back on its fallback path, so a leftover
    // row shows the DEAD alarm's verdict on a freshly created one.
    const alarm = NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1');

    Future<void> withAlarm() async {
      await build();
      await store.saveAlarms(const [alarm]);
      await controller.init();
      await controller.lastEvaluation;
      expect(await store.loadForecasts(), contains(1),
          reason: 'the check recorded a verdict, or this proves nothing');
    }

    test('deleteAlarm clears it', () async {
      await withAlarm();
      await controller.deleteAlarm(1);
      expect(await store.loadForecasts(), isEmpty);
      expect(controller.forecasts, isEmpty);
    });

    test('removeCourt clears it too — it deletes alarms just as surely',
        () async {
      // This is the half that was missing: the sweep landed at the site it was
      // noticed and not at its sibling.
      await withAlarm();
      await controller.removeCourt('c1');
      expect(controller.alarms, isEmpty, reason: 'the court took its alarms');
      expect(await store.loadForecasts(), isEmpty);
      expect(controller.forecasts, isEmpty);
    });
  });

  test('resync before init must not wipe history against the empty courts default',
      () async {
    // Open-during-ring / early resume / ui-resync ping can call resync while
    // `courts` is still `[]` — orphan prune would delete every row (2026-07-23).
    await build();
    await store.upsertHistory(row('c1'));
    expect(controller.loaded, isFalse);

    await controller.resync();

    expect(await store.loadHistory(), hasLength(1),
        reason: 'pre-init resync is a no-op — log stays on disk');
    expect(controller.history, isEmpty,
        reason: 'in-memory history also untouched until init');
  });
}
