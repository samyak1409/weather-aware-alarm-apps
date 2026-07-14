import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SavedLocation JSON round-trips (int coords widen to double)', () {
    const loc = SavedLocation(id: 'a', name: 'Home', lat: 26.17, lon: 75.79);
    final back = SavedLocation.fromJson(loc.toJson());
    expect(back.id, 'a');
    expect(back.name, 'Home');
    expect(back.lat, 26.17);
    expect(back.lon, 75.79);
    // num->double coercion for integer-valued coords.
    final z = SavedLocation.fromJson(
        {'id': 'z', 'name': 'Eq', 'lat': 0, 'lon': 0});
    expect(z.lat, 0.0);
  });

  group('ArunodaySettings', () {
    test('activeLocation: explicit, fallback-to-first, and null', () {
      const a = SavedLocation(id: '1', name: 'A', lat: 1, lon: 1);
      const b = SavedLocation(id: '2', name: 'B', lat: 2, lon: 2);
      expect(
        const ArunodaySettings(locations: [a, b], activeLocationId: '2')
            .activeLocation!
            .id,
        '2',
      );
      // Unknown id -> first location.
      expect(
        const ArunodaySettings(locations: [a, b], activeLocationId: 'x')
            .activeLocation!
            .id,
        '1',
      );
      // No locations -> null.
      expect(const ArunodaySettings().activeLocation, isNull);
    });

    test('copyWith nullable fields use the () => value pattern', () {
      const s = ArunodaySettings(bedtimeOffsetMinutes: 60);
      // Not passing the fn keeps the old value.
      expect(s.copyWith(wakeEnabled: false).bedtimeOffsetMinutes, 60);
      // Passing () => null clears it.
      expect(s.copyWith(bedtimeOffsetMinutes: () => null).bedtimeOffsetMinutes,
          isNull);
      // Passing () => value sets it.
      expect(s.copyWith(bedtimeOffsetMinutes: () => -30).bedtimeOffsetMinutes,
          -30);
    });

    test('JSON round-trips every field', () {
      final s = ArunodaySettings(
        locations: const [SavedLocation(id: '1', name: 'A', lat: 1, lon: 2)],
        activeLocationId: '1',
        wakeOffsetMinutes: 120,
        bedtimeOffsetMinutes: -45,
        wakeEnabled: false,
        bedtimeEnabled: false,
        oneTimeExtraMinutes: 60,
        oneTimeExtraDate: '2026-07-13',
        bedtimeDelayedUntil: DateTime(2026, 7, 13, 22, 46),
        soundPath: 'assets/sounds/arunoday_dawn.wav',
      );
      final back = ArunodaySettings.fromJson(s.toJson());
      expect(back.wakeOffsetMinutes, 120);
      expect(back.bedtimeOffsetMinutes, -45);
      expect(back.wakeEnabled, isFalse);
      expect(back.oneTimeExtraDate, '2026-07-13');
      expect(back.bedtimeDelayedUntil, DateTime(2026, 7, 13, 22, 46));
      expect(back.soundPath, 'assets/sounds/arunoday_dawn.wav');
      expect(back.locations.single.name, 'A');
    });

    test('fromJson tolerates a bare/empty map (defaults)', () {
      final s = ArunodaySettings.fromJson(const {});
      expect(s.locations, isEmpty);
      expect(s.wakeOffsetMinutes, 0);
      expect(s.bedtimeOffsetMinutes, isNull);
      expect(s.wakeEnabled, isTrue);
      expect(s.bedtimeDelayedUntil, isNull);
    });
  });

  group('NivaatAlarm', () {
    const alarm = NivaatAlarm(id: 7, hour: 6, minute: 30, courtId: 'c1');

    test('thresholds derive from the court speed limit', () {
      expect(alarm.thresholds.courtSpeedLimitKmh, WindThresholds.defaultLimit);
    });

    test('nextOccurrence: today if still ahead, else the next matching day', () {
      // Wed 2026-07-08 05:00, alarm 06:30 same day is ahead.
      final wed = DateTime(2026, 7, 8, 5, 0);
      expect(alarm.nextOccurrence(wed), DateTime(2026, 7, 8, 6, 30));
      // After today's time -> tomorrow.
      final wedLate = DateTime(2026, 7, 8, 7, 0);
      expect(alarm.nextOccurrence(wedLate), DateTime(2026, 7, 9, 6, 30));
    });

    test('nextOccurrence skips non-selected weekdays; null when never', () {
      // Only Mondays (weekday 1).
      const monOnly = NivaatAlarm(
          id: 1, hour: 6, minute: 0, courtId: 'c', weekdays: {1});
      // From Tue 2026-07-07 -> next Monday 2026-07-13.
      expect(monOnly.nextOccurrence(DateTime(2026, 7, 7, 8)),
          DateTime(2026, 7, 13, 6, 0));
      // Empty weekdays never fires.
      const never =
          NivaatAlarm(id: 2, hour: 6, minute: 0, courtId: 'c', weekdays: {});
      expect(never.nextOccurrence(DateTime(2026, 7, 7)), isNull);
    });

    test('copyWith and JSON round-trip', () {
      final e = alarm.copyWith(enabled: false, weekdays: const {6, 7});
      expect(e.enabled, isFalse);
      expect(e.weekdays, const {6, 7});
      expect(e.id, 7); // id is preserved
      final back = NivaatAlarm.fromJson(e.toJson());
      expect(back.enabled, isFalse);
      expect(back.weekdays, const {6, 7});
      expect(back.courtId, 'c1');
    });

    test('fromJson applies defaults for missing optional fields', () {
      final a = NivaatAlarm.fromJson(
          {'id': 9, 'hour': 6, 'minute': 0, 'courtId': 'c'});
      expect(a.courtSpeedLimitKmh, WindThresholds.defaultLimit);
      expect(a.weekdays, const {1, 2, 3, 4, 5, 6, 7});
      expect(a.enabled, isTrue);
    });
  });

  group('HistoryRecord', () {
    test('JSON round-trips all metrics including stored limits', () {
      final r = HistoryRecord(
        alarmId: 7,
        at: DateTime(2026, 7, 13, 6, 0),
        outcome: CheckOutcome.skippedGusty,
        courtSpeedKmh: 3.0,
        rawGustKmh: 15.6,
        courtSpeedLimitKmh: 4,
        rawGustLimitKmh: 14.667,
        volume: null,
      );
      final back = HistoryRecord.fromJson(r.toJson());
      expect(back.outcome, CheckOutcome.skippedGusty);
      expect(back.courtSpeedKmh, 3.0);
      expect(back.rawGustKmh, 15.6);
      expect(back.courtSpeedLimitKmh, 4);
      expect(back.rawGustLimitKmh, closeTo(14.667, 0.001));
      expect(back.volume, isNull);
    });

    test('windGustSummary shows all four whole-km/h numbers', () {
      final r = HistoryRecord(
        alarmId: 7,
        at: DateTime(2026, 7, 13, 6, 0),
        outcome: CheckOutcome.skippedGusty,
        courtSpeedKmh: 3.0,
        rawGustKmh: 15.6, // rounds to 16, above the ≤15 guard
        courtSpeedLimitKmh: 4,
        rawGustLimitKmh: 14.667,
      );
      expect(r.windGustSummary, 'wind 3 (≤4) · gusts 16 (≤15) km/h');
    });

    test('windGustSummary degrades for old rows and no-data skips', () {
      // Pre-limits row: values but no stored caps.
      final old = HistoryRecord(
        alarmId: 7,
        at: DateTime(2026, 7, 13, 6, 0),
        outcome: CheckOutcome.skippedWindy,
        courtSpeedKmh: 7.4,
        rawGustKmh: 14.0,
      );
      expect(old.windGustSummary, 'wind 7 · gusts 14 km/h');
      // No-data skip carries caps but nothing was measured.
      final noData = HistoryRecord(
        alarmId: 7,
        at: DateTime(2026, 7, 13, 6, 0),
        outcome: CheckOutcome.skippedNoData,
        courtSpeedLimitKmh: 4,
        rawGustLimitKmh: 14.667,
      );
      expect(noData.windGustSummary, '');
    });
  });

  test('CheckState JSON round-trips, incl. committed-ring fields', () {
    final s = CheckState(
      alarmId: 7,
      alarmAt: DateTime(2026, 7, 13, 6, 0),
      hadSuccessfulCheck: true,
      ringScheduled: true,
      ringCourtSpeedKmh: 3.0,
      ringRawGustKmh: 12.0,
      ringVolume: 0.625,
    );
    final back = CheckState.fromJson(s.toJson());
    expect(back.alarmId, 7);
    expect(back.alarmAt, DateTime(2026, 7, 13, 6, 0));
    expect(back.hadSuccessfulCheck, isTrue);
    expect(back.ringScheduled, isTrue);
    expect(back.ringCourtSpeedKmh, 3.0);
    expect(back.ringVolume, closeTo(0.625, 0.001));
    // Old rows without the new keys default cleanly.
    final bare = CheckState.fromJson(
        {'alarmId': 1, 'alarmAt': '2026-07-13T06:00:00.000'});
    expect(bare.hadSuccessfulCheck, isFalse);
    expect(bare.ringScheduled, isFalse);
    expect(bare.ringCourtSpeedKmh, isNull);
  });
}
