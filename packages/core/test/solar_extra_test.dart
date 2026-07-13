import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tonkLat = 26.17, tonkLon = 75.79;

  test('civilDawnLocal and sunriseLocal return morning events, dawn < sunrise',
      () {
    final date = DateTime(2026, 7, 11);
    final dawn = Solar.civilDawnLocal(date, tonkLat, tonkLon);
    final sunrise = Solar.sunriseLocal(date, tonkLat, tonkLon);
    expect(dawn, isNotNull);
    expect(sunrise, isNotNull);
    // Civil dawn (sun 6° below) is always before sunrise.
    expect(dawn!.isBefore(sunrise!), isTrue);
    expect(dawn.hour, lessThan(12));
  });

  test('morningEventUtc returns null in polar day (no dawn crossing)', () {
    // North Pole at the June solstice: sun never dips to the dawn threshold.
    expect(
      Solar.morningEventUtc(DateTime.utc(2026, 6, 21), 90, 0),
      isNull,
    );
  });

  group('hasDailyDawnAllYear', () {
    test('true at the equator and mid-latitudes', () {
      expect(Solar.hasDailyDawnAllYear(2026, 0, 0), isTrue);
      expect(Solar.hasDailyDawnAllYear(2026, tonkLat, tonkLon), isTrue);
    });

    test('false at the poles and inside the polar circles', () {
      expect(Solar.hasDailyDawnAllYear(2026, 90, 0), isFalse); // North Pole
      expect(Solar.hasDailyDawnAllYear(2026, -90, 0), isFalse); // South Pole
      expect(Solar.hasDailyDawnAllYear(2026, 69.65, 18.96), isFalse); // Tromsø
    });
  });

  test('yearlyDawnExtremes uses the device offset when none is given', () {
    // Just exercises the default-offset branch without asserting a wall clock.
    final e = Solar.yearlyDawnExtremes(2026, tonkLat, tonkLon);
    expect(e, isNotNull);
    expect(e!.earliestMinutes, lessThan(e.latestMinutes));
  });
}
