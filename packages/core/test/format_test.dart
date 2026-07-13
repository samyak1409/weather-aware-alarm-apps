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
}
