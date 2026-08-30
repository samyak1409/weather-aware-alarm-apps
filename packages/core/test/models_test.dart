import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SavedLocation JSON round-trips (int coords widen to double)', () {
    const loc = SavedLocation(
      id: 'a',
      name: 'Home',
      lat: 26.17,
      lon: 75.79,
      region: 'Rajasthan, India',
    );
    final back = SavedLocation.fromJson(loc.toJson());
    expect(back.id, 'a');
    expect(back.name, 'Home');
    expect(back.lat, 26.17);
    expect(back.lon, 75.79);
    expect(back.source, PlaceSource.search);
    expect(back.region, 'Rajasthan, India');
    // num->double coercion for integer-valued coords.
    final z = SavedLocation.fromJson(
        {'id': 'z', 'name': 'Eq', 'lat': 0, 'lon': 0, 'source': 'search',
         'region': null});
    expect(z.lat, 0.0);
  });

  test('a GPS place round-trips as one, with no region', () {
    const loc = SavedLocation(
      id: 'a',
      name: 'My location',
      lat: 26.17,
      lon: 75.79,
      source: PlaceSource.gps,
    );
    final back = SavedLocation.fromJson(loc.toJson());
    expect(back.source, PlaceSource.gps);
    expect(back.region, isNull);
  });

  test('a blob from before the ⓘ throws rather than being guessed at', () {
    // CLAUDE.md's no-migration policy: neither app has shipped, and clearing
    // app data is the upgrade path. Defaulting an absent `source` to `search`
    // would silently relabel every GPS place ever saved — and the reason this
    // is loud rather than quiet is that the wrong answer is unfalsifiable
    // afterwards: nothing in the row would look wrong.
    expect(
      () => SavedLocation.fromJson(
          {'id': 'a', 'name': 'Home', 'lat': 26.17, 'lon': 75.79}),
      throwsA(anything),
    );
  });

  group('savedLocationDetail — what the ⓘ says (X5)', () {
    test('a searched place adds only what the row does not already show', () {
      // The name is the row. Repeating it here would spend the front of a
      // two-second pill on the word an inch above it (Samyak, 2026-08-15).
      final detail = savedLocationDetail(const SavedLocation(
        id: 'a',
        name: 'Jaipur',
        lat: 26.91,
        lon: 75.79,
        region: 'Rajasthan, India',
      ));
      expect(detail, 'Rajasthan, India');
      expect(detail, isNot(contains('Jaipur')));
    });

    test('a GPS fix says where it came from instead', () {
      expect(
        savedLocationDetail(const SavedLocation(
          id: 'a',
          name: 'Home Court',
          lat: 26.17,
          lon: 75.79,
          source: PlaceSource.gps,
        )),
        'Saved using GPS',
      );
    });

    test('a place with no region has nothing to add, and says nothing', () {
      // Both spellings of "no region": `''` from a geocode result carrying
      // neither admin1 nor country, and null from a place built without one —
      // which is every fixture that omits it, so this branch is exercised
      // constantly rather than being the unreachable case an earlier draft of
      // the dartdoc claimed (2026-08-15).
      const bare = SavedLocation(id: 'a', name: 'Jaipur', lat: 26.91, lon: 75.79);
      expect(bare.region, isNull, reason: 'the constructor default');
      expect(savedLocationDetail(bare), '');
      expect(
        savedLocationDetail(const SavedLocation(
            id: 'a', name: 'Jaipur', lat: 26.91, lon: 75.79, region: '')),
        '',
      );
    });
  });

  group('GeoPlace.toSavedLocation — one conversion, three call sites', () {
    test('a searched place keeps its region', () {
      final saved = const GeoPlace(
        name: 'Jaipur',
        region: 'Rajasthan, India',
        lat: 26.91,
        lon: 75.79,
      ).toSavedLocation();
      expect(saved.source, PlaceSource.search);
      expect(saved.region, 'Rajasthan, India');
      expect(saved.name, 'Jaipur');
    });

    test('a GPS place drops its coordinate stand-in', () {
      // The picker fills `GeoPlace.region` with the coordinates for a GPS
      // pick, and storing that would put the numbers behind an ⓘ whose whole
      // job is to say something the row does not already show.
      final saved = const GeoPlace(
        name: 'My location',
        region: '26.170, 75.790',
        lat: 26.17,
        lon: 75.79,
        source: PlaceSource.gps,
      ).toSavedLocation();
      expect(saved.source, PlaceSource.gps);
      expect(saved.region, isNull);
      expect(savedLocationDetail(saved), 'Saved using GPS');
    });
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
        bedtimeDelayCall: 4,
        bedtimeDelayFromMinute: 1316,
        soundPath: 'assets/sounds/arunoday_dawn.wav',
      );
      final back = ArunodaySettings.fromJson(s.toJson());
      expect(back.wakeOffsetMinutes, 120);
      expect(back.bedtimeOffsetMinutes, -45);
      expect(back.wakeEnabled, isFalse);
      expect(back.oneTimeExtraDate, '2026-07-13');
      expect(back.bedtimeDelayedUntil, DateTime(2026, 7, 13, 22, 46));
      // The re-ring's two pieces of metadata (2026-08-13), and losing either
      // fails in silence rather than loudly: the count resets, so the next
      // push says `Third call` on the fifth; and the mark goes null, which
      // switches the whole "the bedtime moved past it" rule off, since that
      // rule returns early when it has nothing to compare against.
      expect(back.bedtimeDelayCall, 4);
      expect(back.bedtimeDelayFromMinute, 1316);
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
      expect(s.bedtimeDelayCall, 0, reason: 'no chain, no call number');
      expect(s.bedtimeDelayFromMinute, isNull);
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

    test('copyWith keeps the id and changes only what it names', () {
      final e = alarm.copyWith(
          enabled: false, weekdays: const {6, 7}, retryMinutesAfter: 60);
      expect(e.enabled, isFalse);
      expect(e.weekdays, const {6, 7});
      expect(e.retryMinutesAfter, 60);
      expect(e.id, 7); // id is preserved
      expect(e.courtId, 'c1');
    });

    test('an alarm made without settings gets the CONSTRUCTOR defaults', () {
      // Defaults live here and nowhere else. There is no parser to leak a
      // second set into: an alarm is columns now, and every one of them is
      // written on every save.
      const a = NivaatAlarm(id: 9, hour: 6, minute: 0, courtId: 'c');
      expect(a.courtSpeedLimitKmh, WindThresholds.defaultLimit);
      expect(a.retryMinutesAfter, CheckCascade.retryCapMinutesAfter);
      expect(a.weekdays, const {1, 2, 3, 4, 5, 6, 7});
      expect(a.enabled, isTrue);
    });

    test('a stored 1-minute window is still a real cap', () {
      // 1 was the dev-gated option until 2026-08-25 and is 15 now, but the cap
      // is arithmetic on whatever the alarm HOLDS — the gate only decides what
      // is offered (`minuteOptionsFor`, locked in wind_test), never what an
      // already-saved alarm computes. The storage round-trip lives in
      // repos_test now, where the columns are.
      final short = alarm.copyWith(retryMinutesAfter: 1);
      expect(short.retryCapAt(DateTime(2026, 7, 12, 6, 0)),
          DateTime(2026, 7, 12, 6, 1));
    });
  });

  group('HistoryRecord', () {
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

  test('a fresh CheckState comes from the CONSTRUCTOR', () {
    // `ringScheduled` and `cardShown` defaulting to false is exactly how a
    // morning would re-arm a ring or re-post a card it had already done once,
    // so where they come from matters. They come from here — the columns are
    // NOT NULL, so there is no absent-value path left that could invent them,
    // which is what the old `fromJson` guard stood in for. The storage
    // round-trip moved to repos_test.
    final fresh = CheckState(alarmId: 1, alarmAt: DateTime(2026, 7, 13, 6, 0));
    expect(fresh.ringScheduled, isFalse);
    expect(fresh.cardShown, isFalse);
    expect(fresh.pushSeq, 0);
  });
}
