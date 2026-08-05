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

    test('an unsaved install gets the defaults from the CONSTRUCTOR', () {
      // Not from `fromJson`, which no longer fills in missing keys: the only
      // caller is `ArunodayStore.load`, and an absent blob returns
      // `const ArunodaySettings()` without parsing anything (locked in
      // `repos_test`). A half-written map is a bug worth a loud cast error,
      // not a settings screen quietly showing someone else's defaults.
      const s = ArunodaySettings();
      expect(s.locations, isEmpty);
      expect(s.wakeOffsetMinutes, 0);
      expect(s.bedtimeOffsetMinutes, isNull);
      expect(s.wakeEnabled, isTrue);
      expect(s.bedtimeDelayedUntil, isNull);
      expect(() => ArunodaySettings.fromJson(const {}), throwsA(anything),
          reason: 'no migration: the parser reads the shape this build writes');
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
      final e = alarm.copyWith(
          enabled: false, weekdays: const {6, 7}, retryMinutesAfter: 60);
      expect(e.enabled, isFalse);
      expect(e.weekdays, const {6, 7});
      expect(e.retryMinutesAfter, 60);
      expect(e.id, 7); // id is preserved
      final back = NivaatAlarm.fromJson(e.toJson());
      expect(back.enabled, isFalse);
      expect(back.weekdays, const {6, 7});
      expect(back.courtId, 'c1');
      expect(back.retryMinutesAfter, 60);
    });

    test('an alarm made without settings gets the CONSTRUCTOR defaults', () {
      // `fromJson` no longer supplies them — see the ArunodaySettings note
      // above; every alarm on disk was written by this build's `toJson`, which
      // always writes all eight keys.
      const a = NivaatAlarm(id: 9, hour: 6, minute: 0, courtId: 'c');
      expect(a.courtSpeedLimitKmh, WindThresholds.defaultLimit);
      expect(a.retryMinutesAfter, CheckCascade.retryCapMinutesAfter);
      expect(a.weekdays, const {1, 2, 3, 4, 5, 6, 7});
      expect(a.enabled, isTrue);
      expect(
        () => NivaatAlarm.fromJson(
            {'id': 9, 'hour': 6, 'minute': 0, 'courtId': 'c'}),
        throwsA(anything),
        reason: 'no migration: the parser reads the shape this build writes',
      );
    });

    test('retryMinutesAfter round-trips, and the options stay ascending', () {
      final short = alarm.copyWith(retryMinutesAfter: 1);
      expect(short.retryCapAt(DateTime(2026, 7, 12, 6, 0)),
          DateTime(2026, 7, 12, 6, 1));
      expect(NivaatAlarm.fromJson(short.toJson()).retryMinutesAfter, 1);
      expect(
          NivaatAlarm.fromJson(alarm.copyWith(retryMinutesAfter: 60).toJson())
              .retryMinutesAfter,
          60);

      // The editor renders one segment per option in LIST order, so this is
      // what puts "1m 30m 60m" on the screen in that order — reorder the list
      // and the control reorders with it.
      expect(
        CheckCascade.retryMinutesOptions,
        orderedEquals(List.of(CheckCascade.retryMinutesOptions)..sort()),
        reason: 'retryMinutesOptions must stay ascending',
      );
    });
  });

  group('HistoryRecord', () {
    test('JSON round-trips all metrics including stored limits', () {
      final r = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: DateTime(2026, 7, 13, 6, 0),
        kind: HistoryKind.outcome,
        pushSeq: 3,
        checkedAt: DateTime(2026, 7, 12, 22, 0),
        checkingEndedAt: DateTime(2026, 7, 13, 6, 30),
        outcome: CheckOutcome.skippedGusty,
        courtSpeedKmh: 3.0,
        rawGustKmh: 15.6,
        courtSpeedLimitKmh: 4,
        rawGustLimitKmh: 14.667,
        volume: null,
      );
      final back = HistoryRecord.fromJson(r.toJson());
      expect(back.courtId, 'c1');
      expect(back.kind, HistoryKind.outcome);
      expect(back.pushSeq, 3);
      expect(back.checkedAt, DateTime(2026, 7, 12, 22, 0));
      expect(back.checkingEndedAt, DateTime(2026, 7, 13, 6, 30));
      expect(back.outcome, CheckOutcome.skippedGusty);
      expect(back.courtSpeedKmh, 3.0);
      expect(back.rawGustKmh, 15.6);
      expect(back.courtSpeedLimitKmh, 4);
      expect(back.rawGustLimitKmh, closeTo(14.667, 0.001));
      expect(back.volume, isNull);
    });

    test('a still-checking row round-trips its promise', () {
      final r = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: DateTime(2026, 7, 13, 6, 0),
        kind: HistoryKind.stillChecking,
        pushSeq: 1,
        watchedUntil: DateTime(2026, 7, 13, 6, 30),
        outcome: CheckOutcome.skippedWindy,
      );
      final back = HistoryRecord.fromJson(r.toJson());
      expect(back.kind, HistoryKind.stillChecking);
      expect(back.watchedUntil, DateTime(2026, 7, 13, 6, 30));
    });

    test('a row is read the way it was written, or not at all', () {
      // No migration: `kind` and `pushSeq` used to be inferred when absent, and
      // that inference is gone with the builds that needed it. A row missing
      // either is corrupt, and the two are worth failing loudly over — the
      // guessed `kind` decided whether a row read as a promise or a verdict,
      // and a defaulted `pushSeq` of 0 collides with the first real push, which
      // is `upsertHistory`'s dedup key.
      final row = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: DateTime(2026, 7, 13, 6, 0),
        kind: HistoryKind.stillChecking,
        pushSeq: 2,
        watchedUntil: DateTime(2026, 7, 13, 6, 30),
        outcome: CheckOutcome.skippedWindy,
      ).toJson();
      expect(HistoryRecord.fromJson(row).kind, HistoryKind.stillChecking);
      expect(HistoryRecord.fromJson(row).pushSeq, 2);
      expect(() => HistoryRecord.fromJson({...row}..remove('kind')),
          throwsA(anything));
      expect(() => HistoryRecord.fromJson({...row}..remove('pushSeq')),
          throwsA(anything));
    });

    test('a deadline can only sit on a still-checking row', () {
      expect(
        () => HistoryRecord(
          alarmId: 7,
          courtId: 'c1',
          at: DateTime(2026, 7, 13, 6, 0),
          watchedUntil: DateTime(2026, 7, 13, 6, 30),
          outcome: CheckOutcome.skippedWindy,
        ),
        throwsA(isA<AssertionError>()),
        reason: 'kind defaults to outcome, so this pairing is a silent '
            'contradiction — it bit four fixtures the day it landed',
      );
    });

    test('a still-checking row cannot claim it already ended', () {
      // The other half of the pair above, and the same reasoning from the
      // other side: a row that is still promising a deadline has not stopped
      // checking, so carrying an end time is a contradiction, not extra data.
      expect(
        () => HistoryRecord(
          alarmId: 7,
          courtId: 'c1',
          at: DateTime(2026, 7, 13, 6, 0),
          kind: HistoryKind.stillChecking,
          watchedUntil: DateTime(2026, 7, 13, 6, 30),
          checkingEndedAt: DateTime(2026, 7, 13, 6, 12),
          outcome: CheckOutcome.skippedWindy,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('whenChecked is the recorded check time, else falls back to at', () {
      final noneRecorded = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: DateTime(2026, 7, 13, 6, 0),
        outcome: CheckOutcome.rang,
        volume: 1,
      );
      expect(noneRecorded.whenChecked, DateTime(2026, 7, 13, 6, 0));
      // Stale evening check behind a morning ring.
      final stale = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: DateTime(2026, 7, 13, 6, 0),
        checkedAt: DateTime(2026, 7, 12, 22, 0),
        outcome: CheckOutcome.rang,
        volume: 1,
      );
      expect(stale.whenChecked, DateTime(2026, 7, 12, 22, 0));
    });

    test('windGustSummary shows all four whole-km/h numbers', () {
      final r = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: DateTime(2026, 7, 13, 6, 0),
        outcome: CheckOutcome.skippedGusty,
        courtSpeedKmh: 3.0,
        rawGustKmh: 15.6, // rounds to 16, above the ≤15 guard
        courtSpeedLimitKmh: 4,
        rawGustLimitKmh: 14.667,
      );
      expect(r.windGustSummary, 'wind 3 (≤4) · gusts 16 (≤15) km/h');
    });

    test('windGustSummary degrades without stored caps, and on no-data', () {
      // Readings but no caps. The engine always writes both, so this is the
      // getter staying TOTAL over its own nullable fields rather than a shape
      // anything produces — the same call as A6/A7's `—` clocks: keep the
      // guard against a force-unwrap, drop the story that it is for old rows.
      final noCaps = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: DateTime(2026, 7, 13, 6, 0),
        outcome: CheckOutcome.skippedWindy,
        courtSpeedKmh: 7.4,
        rawGustKmh: 14.0,
      );
      expect(noCaps.windGustSummary, 'wind 7 · gusts 14 km/h');
      // No-data skip carries caps but nothing was measured.
      final noData = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: DateTime(2026, 7, 13, 6, 0),
        outcome: CheckOutcome.skippedNoData,
        courtSpeedLimitKmh: 4,
        rawGustLimitKmh: 14.667,
      );
      expect(noData.windGustSummary, '');
    });
  });

  test('CheckState JSON round-trips, incl. committed-ring + skip fields', () {
    final s = CheckState(
      alarmId: 7,
      alarmAt: DateTime(2026, 7, 13, 6, 0),
      ringScheduled: true,
      ringCourtSpeedKmh: 3.0,
      ringRawGustKmh: 12.0,
      ringVolume: 0.875,
      cardShown: true,
      skipCourtSpeedKmh: 5.4,
      skipRawGustKmh: 22.0,
      skipGusty: true,
      lastCheckAt: DateTime(2026, 7, 12, 22, 0),
      lastAttemptAt: DateTime(2026, 7, 13, 6, 29),
    );
    final back = CheckState.fromJson(s.toJson());
    expect(back.alarmId, 7);
    expect(back.alarmAt, DateTime(2026, 7, 13, 6, 0));
    expect(back.ringScheduled, isTrue);
    expect(back.ringCourtSpeedKmh, 3.0);
    expect(back.ringVolume, closeTo(0.875, 0.001));
    expect(back.cardShown, isTrue);
    expect(back.skipCourtSpeedKmh, 5.4);
    expect(back.skipGusty, isTrue);
    expect(back.lastCheckAt, DateTime(2026, 7, 12, 22, 0));
    expect(back.lastAttemptAt, DateTime(2026, 7, 13, 6, 29));

    // A fresh occurrence's state comes from the CONSTRUCTOR, never from a
    // half-written blob: `fromJson` no longer fills in absent flags (no
    // migration), and `ringScheduled`/`cardShown` defaulting to false is
    // exactly how a morning would re-arm a ring or re-post a card it had
    // already done once.
    final fresh = CheckState(alarmId: 1, alarmAt: DateTime(2026, 7, 13, 6, 0));
    expect(fresh.ringScheduled, isFalse);
    expect(fresh.cardShown, isFalse);
    expect(fresh.pushSeq, 0);
    expect(
        () => CheckState.fromJson(
            {'alarmId': 1, 'alarmAt': '2026-07-13T06:00:00.000'}),
        throwsA(anything),
        reason: 'no migration: the parser reads the shape this build writes');
  });
}
