import 'dart:math' as math;

/// NOAA solar position math (Spencer/Fourier form of the NOAA equations).
///
/// Validated against reference values computed during spec research
/// (see SPEC.md): Jaipur 2026 sunrise 05:32 IST on 10 Jun / 07:17 on 12 Jan,
/// Tonk civil dawn 05:08-06:51, BLR civil dawn 05:29-06:24.
class Solar {
  Solar._();

  /// Zenith angle for sunrise/sunset (includes refraction + solar radius).
  static const double sunriseZenith = 90.833;

  /// Zenith angle for civil dawn/dusk (sun 6 degrees below horizon).
  static const double civilZenith = 96.0;

  /// Minutes after UTC midnight of the morning event (dawn or sunrise) on
  /// [date] (interpreted as a calendar date) at [latDeg]/[lonDeg].
  ///
  /// Returns null in polar conditions where the event does not occur.
  static double? _morningEventUtcMinutes(
    DateTime date,
    double latDeg,
    double lonDeg, {
    required double zenith,
  }) {
    final doy = _dayOfYear(date);
    final gamma = 2 * math.pi / 365.0 * (doy - 1 + 0.5);

    final eqTime = 229.18 *
        (0.000075 +
            0.001868 * math.cos(gamma) -
            0.032077 * math.sin(gamma) -
            0.014615 * math.cos(2 * gamma) -
            0.040849 * math.sin(2 * gamma));

    final decl = 0.006918 -
        0.399912 * math.cos(gamma) +
        0.070257 * math.sin(gamma) -
        0.006758 * math.cos(2 * gamma) +
        0.000907 * math.sin(2 * gamma) -
        0.002697 * math.cos(3 * gamma) +
        0.00148 * math.sin(3 * gamma);

    final latRad = latDeg * math.pi / 180.0;
    final cosHa =
        math.cos(zenith * math.pi / 180.0) / (math.cos(latRad) * math.cos(decl)) -
            math.tan(latRad) * math.tan(decl);
    if (cosHa < -1.0 || cosHa > 1.0) return null;

    final haDeg = math.acos(cosHa) * 180.0 / math.pi;
    return 720.0 - 4.0 * (lonDeg + haDeg) - eqTime;
  }

  /// The morning event as a UTC [DateTime] for the given calendar [date].
  static DateTime? morningEventUtc(
    DateTime date,
    double latDeg,
    double lonDeg, {
    double zenith = civilZenith,
  }) {
    final minutes = _morningEventUtcMinutes(date, latDeg, lonDeg, zenith: zenith);
    if (minutes == null) return null;
    return DateTime.utc(date.year, date.month, date.day)
        .add(Duration(milliseconds: (minutes * 60000).round()));
  }

  /// Civil dawn on [date] at the location, expressed in the device's local
  /// time zone.
  static DateTime? civilDawnLocal(DateTime date, double latDeg, double lonDeg) =>
      morningEventUtc(date, latDeg, lonDeg, zenith: civilZenith)?.toLocal();

  /// Sunrise on [date] at the location, in the device's local time zone.
  static DateTime? sunriseLocal(DateTime date, double latDeg, double lonDeg) =>
      morningEventUtc(date, latDeg, lonDeg, zenith: sunriseZenith)?.toLocal();

  /// Scans every day of [year] and returns the earliest and latest civil dawn
  /// as minutes-after-local-midnight. Never assumes solstices: the real
  /// extremes fall around early June and mid-January (equation of time).
  ///
  /// [utcOffsetMinutes] defaults to the device's current offset; tests pass
  /// it explicitly (e.g. 330 for IST) to stay machine-independent.
  static ({double earliestMinutes, double latestMinutes, DateTime earliestDay,
      DateTime latestDay})? yearlyDawnExtremes(
    int year,
    double latDeg,
    double lonDeg, {
    int? utcOffsetMinutes,
  }) {
    final offset =
        utcOffsetMinutes ?? DateTime.now().timeZoneOffset.inMinutes;
    double? lo, hi;
    DateTime? loDay, hiDay;
    var day = DateTime.utc(year, 1, 1);
    while (day.year == year) {
      final utcMin =
          _morningEventUtcMinutes(day, latDeg, lonDeg, zenith: civilZenith);
      if (utcMin != null) {
        final m = (utcMin + offset) % 1440.0;
        if (lo == null || m < lo) {
          lo = m;
          loDay = day;
        }
        if (hi == null || m > hi) {
          hi = m;
          hiDay = day;
        }
      }
      day = day.add(const Duration(days: 1));
    }
    if (lo == null || hi == null) return null;
    return (
      earliestMinutes: lo,
      latestMinutes: hi,
      earliestDay: loDay!,
      latestDay: hiDay!,
    );
  }

  /// True only if civil dawn occurs on **every** day of [year] at this
  /// location. False in polar regions where the sun doesn't cross the
  /// civil-dawn threshold for part of the year — Arunoday needs a real
  /// daily dawn, so such locations are refused.
  static bool hasDailyDawnAllYear(int year, double latDeg, double lonDeg) {
    var day = DateTime.utc(year, 1, 1);
    while (day.year == year) {
      if (_morningEventUtcMinutes(day, latDeg, lonDeg, zenith: civilZenith) ==
          null) {
        return false;
      }
      day = day.add(const Duration(days: 1));
    }
    return true;
  }

  // From calendar components only: diffing the raw instant against UTC Jan 1
  // shifts the result by one for local-zone inputs (the apps pass local
  // DateTimes) depending on their time of day — which moved dawn by ~1 min
  // between a pre-dawn and a daytime resync of the very same date.
  static int _dayOfYear(DateTime d) => DateTime.utc(d.year, d.month, d.day)
          .difference(DateTime.utc(d.year, 1, 1))
          .inDays +
      1;
}
