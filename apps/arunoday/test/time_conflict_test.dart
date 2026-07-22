import 'package:arunoday/src/time_conflict.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('arunodayBedtimeConflictsWithWake: same minute refuses', () {
    expect(
      arunodayBedtimeConflictsWithWake(
        bedtimeMinuteOfDay: 7 * 60,
        wakeMinuteOfDay: 7 * 60,
      ),
      "Bedtime can't be the same as the wake alarm.",
    );
    expect(
      arunodayBedtimeConflictsWithWake(
        bedtimeMinuteOfDay: 22 * 60,
        wakeMinuteOfDay: 7 * 60,
      ),
      isNull,
    );
    expect(
      arunodayBedtimeConflictsWithWake(
        bedtimeMinuteOfDay: 7 * 60,
        wakeMinuteOfDay: null,
      ),
      isNull,
    );
  });

  test('arunodayWakeConflictsWithBedtime: same minute refuses', () {
    final dawn = DateTime(2026, 7, 22, 6, 0); // wake = dawn + offset
    expect(
      arunodayWakeConflictsWithBedtime(
        wakeOffsetMinutes: 60, // → 07:00
        dawn: dawn,
        bedtimeMinuteOfDay: 7 * 60,
      ),
      "Wake time can't be the same as the bedtime.",
    );
    expect(
      arunodayWakeConflictsWithBedtime(
        wakeOffsetMinutes: 0, // → 06:00
        dawn: dawn,
        bedtimeMinuteOfDay: 7 * 60,
      ),
      isNull,
    );
    expect(
      arunodayWakeConflictsWithBedtime(
        wakeOffsetMinutes: 60,
        dawn: dawn,
        bedtimeMinuteOfDay: null,
      ),
      isNull,
    );
  });
}
