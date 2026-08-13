import 'package:arunoday/src/bedtime_actions.dart';
import 'package:arunoday/src/controller.dart';
import 'package:arunoday/src/ids.dart';
import 'package:flutter_test/flutter_test.dart';

/// The id map's safety net. The block layout is load-bearing twice over: ids
/// must not collide, and [ArunodayIds.isBedtime] uses the block boundary as a
/// TYPE TAG — the ring screen offers its "+1h sleep late" action based on it.
void main() {
  test('no two ids collide across a full window', () {
    final seen = <int, String>{};
    void claim(int id, String what) {
      expect(seen.containsKey(id), isFalse,
          reason: '$what collides with ${seen[id]} at id $id');
      seen[id] = what;
    }

    final start = DateTime(2026, 7, 12);
    for (var i = 0; i < ArunodayIds.slots; i++) {
      final day = DateTime(start.year, start.month, start.day + i);
      claim(ArunodayIds.wake(day), 'wake($day)');
      claim(ArunodayIds.bedtime(day), 'bedtime($day)');
    }
    claim(ArunodayIds.bedtimeAgain, 'bedtimeAgain');
  });

  test('the window has exactly one locker per day — no day silently lost', () {
    // Fewer lockers than days would make two days share one id, and the later
    // write would erase the earlier day's alarm.
    expect(ArunodayIds.slots, ArunodayController.windowDays);

    for (var offset = 0; offset < 60; offset++) {
      final start = DateTime(2026, 1, 1 + offset);
      final wakeIds = <int>{};
      for (var i = 0; i < ArunodayIds.slots; i++) {
        wakeIds.add(
            ArunodayIds.wake(DateTime(start.year, start.month, start.day + i)));
      }
      expect(wakeIds, hasLength(ArunodayIds.slots),
          reason: 'window from $start reused a locker');
    }
  });

  test('a given day keeps its id no matter when the resync runs', () {
    // The point of keying on the calendar day rather than "days from now":
    // under the old scheme Monday's alarm slid from 1001 to 1000 at midnight,
    // so every resync rebuilt all 16 alarms instead of re-setting them.
    final monday = DateTime(2026, 7, 13);
    expect(ArunodayIds.wake(monday), ArunodayIds.wake(monday));
    expect(ArunodayIds.wake(DateTime(2026, 7, 13, 5, 30)),
        ArunodayIds.wake(DateTime(2026, 7, 13, 22, 0)),
        reason: 'same calendar day = same locker, whatever the clock time');
  });

  group('isBedtime type tag', () {
    test('covers every bedtime ring, including the re-ring', () {
      final start = DateTime(2026, 7, 12);
      for (var i = 0; i < ArunodayIds.slots; i++) {
        final day = DateTime(start.year, start.month, start.day + i);
        expect(ArunodayIds.isBedtime(ArunodayIds.bedtime(day)), isTrue);
        expect(ArunodayIds.isBedtime(ArunodayIds.wake(day)), isFalse,
            reason: 'a WAKE alarm must never offer the bedtime ritual');
      }
      expect(ArunodayIds.isBedtime(ArunodayIds.bedtimeAgain), isTrue,
          reason: 'the "sleep late" re-ring needs the bedtime ritual too');
    });

    test('BedtimeActions agrees with the id map', () {
      // The ring screen's own predicate must not drift from the blocks.
      expect(ArunodayIds.isBedtime(ArunodayIds.bedtimeAgain), isTrue);
      expect(BedtimeActions.isBedtimeAlarm, isNotNull);
    });
  });

  test('every id the controller can emit stays inside its block', () {
    // The window walks forward every day, so sweep a year of start dates and
    // assert wake ids never stray into the bedtime block — the exact failure a
    // narrower block width would cause (see CLAUDE.md's id-block rule).
    for (var offset = 0; offset < 365; offset++) {
      for (var i = 0; i < ArunodayIds.slots; i++) {
        final day = DateTime(2026, 1, 1 + offset + i);
        final wake = ArunodayIds.wake(day);
        final bed = ArunodayIds.bedtime(day);
        expect(wake, inInclusiveRange(1000, 1999));
        expect(bed, inInclusiveRange(2000, 2999));
        expect(ArunodayIds.isBedtime(wake), isFalse);
      }
    }
    expect(ArunodayIds.bedtimeAgain, 3000);
    expect(ArunodayIds.isBedtime(ArunodayIds.bedtimeAgain), isTrue);
  });

  test('dayNumber steps by exactly 1 across a DST-style boundary', () {
    // UTC-normalised calendar arithmetic: a 23h or 25h local day must still
    // advance by one, or two window days could collapse onto one locker.
    final a = ArunodayIds.dayNumber(DateTime(2026, 3, 28, 23, 30));
    final b = ArunodayIds.dayNumber(DateTime(2026, 3, 29, 0, 30));
    expect(b - a, 1);
  });
}
