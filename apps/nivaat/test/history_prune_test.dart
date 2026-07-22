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
