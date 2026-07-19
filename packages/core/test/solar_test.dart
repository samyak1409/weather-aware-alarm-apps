import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reference values computed independently (Python, NOAA equations) during
/// spec research on 2026-07-11 — see SPEC.md.
const ist = 330; // IST = UTC+5:30

double minutesIst(DateTime? utc) {
  expect(utc, isNotNull);
  final m = utc!.hour * 60 + utc.minute + utc.second / 60.0 + ist;
  return m % 1440.0;
}

String hhmm(double m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m.round() % 60).toString().padLeft(2, '0')}';

void main() {
  const jaipurLat = 26.9124, jaipurLon = 75.7873;
  const tonkLat = 26.17, tonkLon = 75.79;
  const blrLat = 12.97, blrLon = 77.59;

  group('sunrise (Jaipur 2026)', () {
    test('earliest sunrise ~05:32 on 10 Jun', () {
      final m = minutesIst(Solar.morningEventUtc(
          DateTime.utc(2026, 6, 10), jaipurLat, jaipurLon,
          zenith: Solar.sunriseZenith));
      expect(m, closeTo(5 * 60 + 32, 2), reason: 'got ${hhmm(m)}');
    });

    test('latest sunrise ~07:17 on 12 Jan (NOT the solstice)', () {
      final m = minutesIst(Solar.morningEventUtc(
          DateTime.utc(2026, 1, 12), jaipurLat, jaipurLon,
          zenith: Solar.sunriseZenith));
      expect(m, closeTo(7 * 60 + 17, 2), reason: 'got ${hhmm(m)}');
    });

    test('21 Dec sunrise ~07:12 — solstice is not the latest sunrise', () {
      final m = minutesIst(Solar.morningEventUtc(
          DateTime.utc(2026, 12, 21), jaipurLat, jaipurLon,
          zenith: Solar.sunriseZenith));
      expect(m, closeTo(7 * 60 + 12, 2), reason: 'got ${hhmm(m)}');
    });
  });

  group('civil dawn', () {
    test('Tonk on 11 Jul 2026 ~05:16', () {
      final m = minutesIst(
          Solar.morningEventUtc(DateTime.utc(2026, 7, 11), tonkLat, tonkLon));
      expect(m, closeTo(5 * 60 + 16, 2), reason: 'got ${hhmm(m)}');
    });

    test('BLR on 11 Jul 2026 ~05:37 — 21 min later than Tonk, same clock', () {
      final m = minutesIst(
          Solar.morningEventUtc(DateTime.utc(2026, 7, 11), blrLat, blrLon));
      expect(m, closeTo(5 * 60 + 37, 2), reason: 'got ${hhmm(m)}');
    });
  });

  group('yearly dawn extremes', () {
    test('Tonk 2026: 05:08 (~11 Jun) to 06:51 (~14 Jan), swing ~103 min', () {
      final e = Solar.yearlyDawnExtremes(2026, tonkLat, tonkLon,
          utcOffsetMinutes: ist)!;
      expect(e.earliestMinutes, closeTo(5 * 60 + 8, 2));
      expect(e.latestMinutes, closeTo(6 * 60 + 51, 2));
      expect(e.latestMinutes - e.earliestMinutes, closeTo(103, 3));
      expect(e.earliestDay.month, 6);
      expect(e.latestDay.month, 1);
    });

    test('BLR 2026: swing only ~55 min (closer to equator)', () {
      final e = Solar.yearlyDawnExtremes(2026, blrLat, blrLon,
          utcOffsetMinutes: ist)!;
      expect(e.earliestMinutes, closeTo(5 * 60 + 29, 2));
      expect(e.latestMinutes, closeTo(6 * 60 + 24, 2));
      expect(e.latestMinutes - e.earliestMinutes, closeTo(55, 3));
    });

    test('polar latitude returns null-safe result (no crash)', () {
      // Longyearbyen: no civil dawn for chunks of the year; scan still works.
      final e = Solar.yearlyDawnExtremes(2026, 78.22, 15.65,
          utcOffsetMinutes: 60);
      expect(e, isNotNull); // some days do have dawn
    });
  });

  group('local-date inputs (the apps pass local DateTimes)', () {
    test('same calendar date -> same dawn, whatever the input time of day', () {
      // March: dawn drifts ~1 min/day, so a day-of-year off-by-one is visible.
      // Regression for _dayOfYear diffing the raw instant against UTC Jan 1:
      // on a UTC+ machine the 00:30 input mapped to the PREVIOUS day's number
      // (on UTC− machines, the 23:30 one to the next), moving dawn ~1 min
      // between a pre-dawn and a daytime resync of the same date.
      final ref =
          Solar.morningEventUtc(DateTime.utc(2026, 3, 1), tonkLat, tonkLon);
      for (final local in [
        DateTime(2026, 3, 1, 0, 30),
        DateTime(2026, 3, 1, 12, 0),
        DateTime(2026, 3, 1, 23, 30),
      ]) {
        expect(Solar.morningEventUtc(local, tonkLat, tonkLon), ref,
            reason: 'input at ${local.hour}:${local.minute}');
      }
    });
  });
}
