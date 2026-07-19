import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fmtClock pads hours and minutes', () {
    expect(fmtClock(DateTime(2026, 1, 1, 5, 3)), '05:03');
    expect(fmtClock(DateTime(2026, 1, 1, 23, 59)), '23:59');
  });

  test('fmtMinutesOfDay wraps and pads', () {
    expect(fmtMinutesOfDay(0), '00:00');
    expect(fmtMinutesOfDay(5 * 60 + 3), '05:03');
    expect(fmtMinutesOfDay(1440), '00:00'); // wraps
    expect(fmtMinutesOfDay(1500), '01:00'); // 25:00 -> 01:00
  });

  test('fmtDuration is Hh MMm', () {
    expect(fmtDuration(0), '0h 00m');
    expect(fmtDuration(7 * 60 + 8), '7h 08m');
    expect(fmtDuration(90.6), '1h 31m'); // rounds
  });

  test('fmtOffset signs and pads, with the true-minus glyph', () {
    expect(fmtOffset(0), '+0:00');
    expect(fmtOffset(125), '+2:05');
    expect(fmtOffset(-66), '−1:06'); // U+2212, not hyphen
  });

  test('fmtWeekdays covers every branch', () {
    expect(fmtWeekdays(const {1, 2, 3, 4, 5, 6, 7}), 'Every day');
    expect(fmtWeekdays(const {}), 'Never');
    expect(fmtWeekdays(const {1, 2, 3, 4, 5}), 'Weekdays');
    expect(fmtWeekdays(const {6, 7}), 'Weekends');
    expect(fmtWeekdays(const {1, 3, 5}), 'Mon Wed Fri');
    expect(fmtWeekdays(const {7, 6}), 'Weekends'); // order-independent
  });

  test('fmtShortDate is day + month abbrev', () {
    expect(fmtShortDate(DateTime(2026, 7, 13)), '13 Jul');
    expect(fmtShortDate(DateTime(2026, 1, 1)), '1 Jan');
    expect(fmtShortDate(DateTime(2026, 12, 31)), '31 Dec');
  });

  test('fmtCheckTime adds the date only across a day boundary', () {
    final alarm = DateTime(2026, 7, 18, 6, 0);
    // Same day → time only.
    expect(fmtCheckTime(DateTime(2026, 7, 18, 5, 59), alarm), '05:59');
    // Previous evening → dated, so "22:00" can't read as the alarm day.
    expect(fmtCheckTime(DateTime(2026, 7, 17, 22, 0), alarm), '17 Jul 22:00');
  });

  test('fmtWindGust shows all four numbers as whole km/h', () {
    expect(fmtWindGust(3.0, 4, 15.6, 14.6667),
        'wind 3 (≤4) · gusts 16 (≤15) km/h');
    // Rounding matches the decision's rounding, so a shown value never
    // contradicts its cap: a gust that skips (15.6 > 14.667) shows 16 vs ≤15.
    expect(fmtWindGust(1.8, 4, 6.0, 14.6667),
        'wind 2 (≤4) · gusts 6 (≤15) km/h');
  });
}
