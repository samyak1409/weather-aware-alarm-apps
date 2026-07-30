import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/controller.dart';
import 'package:nivaat/src/history_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'silent_fakes.dart';

/// A background check that lands a row while the log is OPEN must show up
/// straight away. Home and the settings row count already listened to the
/// controller; the sheet did not, so the one surface you were staring at was
/// the stale one (2026-07-26). The background isolate is stood in for by
/// writing to the store and then resyncing, exactly as `pingNivaatUiResync`
/// does.

HistoryRecord row(DateTime at, {int alarmId = 1}) => HistoryRecord(
      alarmId: alarmId,
      courtId: 'c1',
      at: at,
      checkedAt: at,
      outcome: CheckOutcome.rang,
      courtSpeedKmh: 3,
      rawGustKmh: 12,
      courtSpeedLimitKmh: 4,
      rawGustLimitKmh: 15,
      volume: 0.88,
    );

void main() {
  const court = SavedLocation(id: 'c1', name: 'Home Court', lat: 12.9, lon: 77.6);
  final first = DateTime(2026, 7, 18, 6, 0);
  final second = DateTime(2026, 7, 19, 6, 0);

  testWidgets('a row landing while the log is open appears without reopening',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = NivaatStore();
    await store.saveCourts([court]);
    await store.upsertHistory(row(first));
    final controller = NivaatController(engine: silentEngine(store));
    await controller.init();

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showHistorySheet(context, controller),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsOneWidget,
        reason: 'the one existing row is showing');

    // The background check lands its row and pings the UI isolate.
    await store.upsertHistory(row(second, alarmId: 2));
    await controller.resync();
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNWidgets(2),
        reason: 'the open sheet must pick up the new row, not wait for reopen');
  });
}
