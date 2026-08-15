import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    // Arunoday's settings blob stays on prefs; everything contended is in the
    // database. Both backends are live in this suite, on purpose.
    SharedPreferences.setMockInitialValues({});
    await useInMemoryAppDatabase();
  });

  group('ArunodayStore', () {
    test('load returns defaults when nothing saved', () async {
      final s = await ArunodayStore().load();
      expect(s.locations, isEmpty);
      expect(s.wakeOffsetMinutes, 0);
    });

    test('save then load round-trips', () async {
      final store = ArunodayStore();
      await store.save(const ArunodaySettings(
        locations: [SavedLocation(id: '1', name: 'A', lat: 1, lon: 2)],
        activeLocationId: '1',
        wakeOffsetMinutes: 90,
        bedtimeOffsetMinutes: -30,
      ));
      final back = await store.load();
      expect(back.activeLocationId, '1');
      expect(back.wakeOffsetMinutes, 90);
      expect(back.bedtimeOffsetMinutes, -30);
    });
  });

  group('NivaatStore', () {
    final store = NivaatStore();
    const court = SavedLocation(id: 'c1', name: 'Court', lat: 12.9, lon: 77.6);
    const alarm = NivaatAlarm(id: 7, hour: 6, minute: 0, courtId: 'c1');

    test('courts and alarms round-trip; empty by default', () async {
      expect(await store.loadCourts(), isEmpty);
      expect(await store.loadAlarms(), isEmpty);
      await store.saveCourts([court]);
      await store.saveAlarms([alarm]);
      expect((await store.loadCourts()).single.name, 'Court');
      expect((await store.loadAlarms()).single.id, 7);
      expect((await store.loadAlarms()).single.retryMinutesAfter,
          CheckCascade.retryCapMinutesAfter,
          reason: 'default retry window survives the store');
    });

    test('a court keeps where it came from (X5)', () async {
      // The ⓘ reads these two columns and nothing else, so a court that lost
      // them on the way to disk would go on claiming it was searched for.
      const searched = SavedLocation(
        id: 'c1',
        name: 'Society Court',
        lat: 26.17,
        lon: 75.79,
        region: 'Rajasthan, India',
      );
      const fixed = SavedLocation(
        id: 'c2',
        name: 'Home Court',
        lat: 26.18,
        lon: 75.80,
        source: PlaceSource.gps,
      );
      await store.saveCourts([searched, fixed]);
      final back = await store.loadCourts();
      expect(back[0].source, PlaceSource.search);
      expect(back[0].region, 'Rajasthan, India');
      expect(back[1].source, PlaceSource.gps);
      expect(back[1].region, isNull);
      expect(savedLocationDetail(back[1]), 'Saved using GPS');
    });

    test('per-alarm retryMinutesAfter persists through the store', () async {
      const short = NivaatAlarm(
        id: 7,
        hour: 6,
        minute: 0,
        courtId: 'c1',
        retryMinutesAfter: 1,
      );
      await store.saveAlarms([short]);
      expect((await store.loadAlarms()).single.retryMinutesAfter, 1);

      const hour = NivaatAlarm(
        id: 7,
        hour: 6,
        minute: 0,
        courtId: 'c1',
        retryMinutesAfter: 60,
      );
      await store.saveAlarms([hour]);
      expect((await store.loadAlarms()).single.retryMinutesAfter, 60);
    });

    test('sound path saves, loads, and clears (remove)', () async {
      expect(await store.loadSoundPath(), isNull);
      await store.saveSoundPath('/system/media/audio/alarms/Beep.ogg');
      expect(await store.loadSoundPath(),
          '/system/media/audio/alarms/Beep.ogg');
      await store.saveSoundPath(null);
      expect(await store.loadSoundPath(), isNull);
    });

    test('check state saves, loads, and clears per alarm id', () async {
      expect(await store.loadCheckState(7), isNull);
      await store.saveCheckState(CheckState(
        alarmId: 7,
        alarmAt: DateTime(2026, 7, 13, 6, 0),
        ringScheduled: true,
      ));
      final s = await store.loadCheckState(7);
      expect(s!.ringScheduled, isTrue);
      await store.clearCheckState(7);
      expect(await store.loadCheckState(7), isNull);
    });

    test('CheckState.copyWith keeps every unpassed field', () {
      // Load-bearing for the cascade: a later copyWith (e.g. a no-data retry
      // stamping lastAttemptAt) must never wipe the ring/skip readings.
      final full = CheckState(
        alarmId: 7,
        alarmAt: DateTime(2026, 7, 13, 6, 0),
        ringScheduled: true,
        ringCourtSpeedKmh: 2.4,
        ringRawGustKmh: 9.0,
        ringVolume: 0.85,
        cardShown: true,
        skipCourtSpeedKmh: 7.2,
        skipRawGustKmh: 16.0,
        skipGusty: true,
        lastCheckAt: DateTime(2026, 7, 13, 5, 0),
        lastAttemptAt: DateTime(2026, 7, 13, 5, 30),
      );
      final touched = full.copyWith(lastAttemptAt: DateTime(2026, 7, 13, 6, 1));
      expect(touched.lastAttemptAt, DateTime(2026, 7, 13, 6, 1));
      // Everything else survives untouched. Compared field by field: there is
      // no `toJson` to diff against any more, and listing them is what makes a
      // newly-added field that copyWith forgets show up here.
      expect(touched.alarmId, full.alarmId);
      expect(touched.alarmAt, full.alarmAt);
      expect(touched.ringScheduled, full.ringScheduled);
      expect(touched.ringCourtSpeedKmh, full.ringCourtSpeedKmh);
      expect(touched.ringRawGustKmh, full.ringRawGustKmh);
      expect(touched.ringVolume, full.ringVolume);
      expect(touched.cardShown, full.cardShown);
      expect(touched.skipCourtSpeedKmh, full.skipCourtSpeedKmh);
      expect(touched.skipRawGustKmh, full.skipRawGustKmh);
      expect(touched.skipGusty, full.skipGusty);
      expect(touched.lastCheckAt, full.lastCheckAt);
      expect(touched.pushSeq, full.pushSeq);
    });

    test('check state round-trips every field through the columns', () async {
      // Replaces the old `CheckState.fromJson(toJson())` test: the columns are
      // the storage format now, so this is where a field that never reaches
      // disk gets caught.
      final full = CheckState(
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
        pushSeq: 4,
      );
      await store.saveCheckState(full);
      final back = (await store.loadCheckState(7))!;
      expect(back.alarmAt, DateTime(2026, 7, 13, 6, 0));
      expect(back.alarmAt.isUtc, isFalse,
          reason: 'instants come back in local time, as DateTime.== requires');
      expect(back.ringScheduled, isTrue);
      expect(back.ringCourtSpeedKmh, 3.0);
      expect(back.ringVolume, closeTo(0.875, 0.001));
      expect(back.cardShown, isTrue);
      expect(back.skipCourtSpeedKmh, 5.4);
      expect(back.skipGusty, isTrue);
      expect(back.lastCheckAt, DateTime(2026, 7, 12, 22, 0));
      expect(back.lastAttemptAt, DateTime(2026, 7, 13, 6, 29));
      expect(back.pushSeq, 4);
    });

    test('a pending ring round-trips every field through the columns',
        () async {
      final pending = PendingRing(
        alarmId: 7,
        pluginId: 10007,
        role: RingLockerRole.lateRing,
        occurrenceAt: DateTime(2026, 7, 13, 6, 0),
        scheduledFor: DateTime(2026, 7, 13, 6, 0, 30),
        courtId: 'c1',
        volume: 0.7,
        courtSpeedKmh: 2.2,
        rawGustKmh: 8.8,
        courtSpeedLimitKmh: 4,
        rawGustLimitKmh: 14.667,
        lastCheckAt: DateTime(2026, 7, 13, 5, 55),
        rollOnDone: true,
      );
      await store.savePendingRing(pending);
      final back = (await store.loadPendingRing(7))!;
      expect(back.pluginId, 10007);
      expect(back.role, RingLockerRole.lateRing);
      expect(back.occurrenceAt, DateTime(2026, 7, 13, 6, 0));
      expect(back.scheduledFor, DateTime(2026, 7, 13, 6, 0, 30));
      expect(back.courtId, 'c1');
      expect(back.volume, closeTo(0.7, 0.001));
      expect(back.courtSpeedKmh, 2.2);
      expect(back.rawGustKmh, 8.8);
      expect(back.courtSpeedLimitKmh, 4);
      expect(back.rawGustLimitKmh, closeTo(14.667, 0.001));
      expect(back.lastCheckAt, DateTime(2026, 7, 13, 5, 55));
      expect(back.rollOnDone, isTrue);
      expect((await store.loadAllPendingRings()).single.pluginId, 10007);
    });

    test('upsertHistory: one row per push; a racing double-write converges',
        () async {
      final at = DateTime(2026, 7, 13, 6, 0);
      final cap = at.add(const Duration(minutes: 30));
      HistoryRecord push(int seq,
              {DateTime? watched, DateTime? when, int alarm = 7}) =>
          HistoryRecord(
              alarmId: alarm,
              courtId: 'c1',
              at: when ?? at,
              kind: watched == null
                  ? HistoryKind.outcome
                  : HistoryKind.stillChecking,
              pushSeq: seq,
              watchedUntil: watched,
              outcome: CheckOutcome.skippedWindy);

      // Two isolates handling the SAME push read the same counter, so they
      // write the same number and land on one row.
      await store.upsertHistory(push(1, watched: cap));
      await store.upsertHistory(push(1, watched: cap));
      expect(await store.loadHistory(), hasLength(1),
          reason: 'a double-write of one push converges');

      // The next push is a new row; the first survives it (append-only).
      await store.upsertHistory(push(2));
      var h = await store.loadHistory();
      expect(h, hasLength(2));
      expect(h.first.pushSeq, 2, reason: 'newest prepends');
      expect(h.last.watchedUntil, cap, reason: 'the promise it made stands');

      // Two pushes with IDENTICAL content — Keep checking 30 → 60 → 30 — must
      // both stay. This is exactly why the key cannot be the row's text.
      await store.upsertHistory(push(3, watched: cap));
      final same = await store.loadHistory();
      expect(same, hasLength(3));
      expect(same.where((r) => r.watchedUntil == cap), hasLength(2));

      // Different occurrence / different alarm = new rows whatever the seq.
      await store.upsertHistory(push(1, when: at.add(const Duration(days: 1))));
      await store.upsertHistory(push(1, alarm: 8));
      expect(await store.loadHistory(), hasLength(5));
    });

    test('history prepends newest and is never trimmed', () async {
      // 65 mornings: one past the 60-row ceiling this store used to enforce
      // (removed 2026-07-31 — the log is permanent, per SPEC). The oldest row
      // must still be there, because nothing but a court delete removes one.
      for (var i = 0; i < 65; i++) {
        await store.upsertHistory(HistoryRecord(
          alarmId: i,
          courtId: 'c1',
          at: DateTime(2026, 7, 13, 6, i % 60),
          outcome: CheckOutcome.rang,
          courtSpeedKmh: 1,
          volume: 1,
        ));
      }
      final h = await store.loadHistory();
      expect(h.length, 65, reason: 'nothing is dropped');
      expect(h.first.alarmId, 64, reason: 'newest is first');
      expect(h.last.alarmId, 0, reason: 'the very first row survives');
    });

    test('one morning can push past the old ceiling on its own', () async {
      // The other direction: 65 pushes of a SINGLE occurrence, which is what a
      // morning does when you keep moving the Keep-checking deadline. Distinct
      // pushSeq, so none of them converges onto another.
      for (var i = 0; i < 65; i++) {
        await store.upsertHistory(HistoryRecord(
          alarmId: 7,
          courtId: 'c1',
          at: DateTime(2026, 7, 13, 6, 0),
          kind: HistoryKind.stillChecking,
          pushSeq: i,
          watchedUntil: DateTime(2026, 7, 13, 6, 30),
          outcome: CheckOutcome.skippedWindy,
        ));
      }
      final h = await store.loadHistory();
      expect(h, hasLength(65));
      expect(h.last.pushSeq, 0, reason: 'the morning\'s first promise stands');
    });

    test('removeHistoryForCourt drops every row for that court, keeps others',
        () async {
      // Two rows for c1 (one from an alarm that no longer matters), one for c2.
      for (final (id, courtId) in [(1, 'c1'), (9, 'c1'), (2, 'c2')]) {
        await store.upsertHistory(HistoryRecord(
          alarmId: id,
          courtId: courtId,
          at: DateTime(2026, 7, 13, 6, id),
          outcome: CheckOutcome.rang,
        ));
      }
      await store.removeHistoryForCourt('c1');
      final h = await store.loadHistory();
      expect(h.map((r) => r.courtId), ['c2'],
          reason: 'every c1 row gone, incl. the orphaned-alarm one; c2 kept');
    });

    group('a write survives the other isolate (REVIEW #7)', () {
      // **Both hazards this group used to reproduce are now unreachable by
      // construction, so what it asserts changed.** History was ONE JSON blob,
      // read-modify-written, and this app's two isolates genuinely run at once
      // — the app open at 06:00 while the AlarmManager wakeup fires is the
      // DESIGNED case. The old tests needed a `_StaleCacheStore` (a per-isolate
      // prefs snapshot) and a `_ClobberedOnceStore` (the other isolate saving a
      // whole blob built before ours). Neither has anything to model now: there
      // is no per-isolate cache to go stale, and no writer that rewrites rows
      // it did not author. These pin that.
      final at = DateTime(2026, 7, 13, 6, 0);
      HistoryRecord row(int alarmId, {int pushSeq = 0}) => HistoryRecord(
            alarmId: alarmId,
            courtId: 'c1',
            at: at,
            pushSeq: pushSeq,
            outcome: CheckOutcome.rang,
          );

      test('an upsert touches its own row and no other', () async {
        // The reported bug was the opposite: a foreground holding a snapshot
        // from launch rebuilt the log from before the background check's row
        // existed, and saving it back deleted that row. "A background check
        // writes `Still checking`, you toggle the alarm off, and the row is
        // gone." A statement that names one row cannot do that.
        await NivaatStore().upsertHistory(row(1)); // the background check
        await NivaatStore().upsertHistory(row(2)); // the toggle-off

        expect(
          (await store.loadHistory()).map((r) => r.alarmId).toSet(),
          {1, 2},
          reason: 'the row we never read must survive our write',
        );
      });

      test('the losing side of a same-key race is applied, not dropped',
          () async {
        // The concurrent half. On prefs, another isolate saving a blob built
        // before ours wiped our row outright, and no reload could prevent it —
        // the damage happens after we have read. `INSERT … ON CONFLICT DO
        // UPDATE` has no such window: whoever writes second updates the row
        // rather than replacing a list it built from a stale read.
        await store.upsertHistory(row(2));
        await store.upsertHistory(HistoryRecord(
          alarmId: 2,
          courtId: 'c1',
          at: at,
          pushSeq: 0,
          outcome: CheckOutcome.rang,
          ringDisposition: RingDisposition.missed,
        ));

        final disk = await store.loadHistory();
        expect(disk, hasLength(1), reason: 'same push key converges');
        expect(disk.single.ringDisposition, RingDisposition.missed,
            reason: 'the second write was applied, not discarded');
      });

      test('a corrected row keeps its place in the log', () async {
        // The sheet renders every row in order, so a supersession that jumped
        // to the top would read as a second, later event. The conflict update
        // deliberately leaves `rowSeq` alone.
        await store.upsertHistory(row(1));
        await store.upsertHistory(row(2));
        await store.upsertHistory(HistoryRecord(
          alarmId: 1,
          courtId: 'c1',
          at: at,
          pushSeq: 0,
          outcome: CheckOutcome.rang,
          ringDisposition: RingDisposition.unknown,
        ));

        final ids = (await store.loadHistory()).map((r) => r.alarmId).toList();
        expect(ids, [2, 1], reason: 'the correction did not reorder the log');
      });
    });

    group('transactions', () {
      test('nothing lands when the transaction does not commit', () async {
        // The whole point of the migration in one assertion: a failure part way
        // through leaves no half-written state. On prefs each `setString` was
        // its own commit, so an interrupted sequence left exactly the shapes
        // the engine then had to recover from.
        await expectLater(
          store.transaction(() async {
            await store.saveAlarmIdSeq(9);
            await store.upsertHistory(
              HistoryRecord(
                alarmId: 1,
                courtId: 'c1',
                at: DateTime(2026, 7, 13, 6, 0),
                outcome: CheckOutcome.rang,
              ),
            );
            throw Exception('interrupted');
          }),
          throwsException,
        );

        expect(await store.loadAlarmIdSeq(), isNull);
        expect(await store.loadHistory(), isEmpty);
      });

      test('the id counter and the alarm that spends it land together',
          () async {
        // REVIEW #9's guarantee, structural now. It used to be two writes
        // ordered counter-first, because interrupted between them it is better
        // to skip a number than to leave an alarm with no counter past it —
        // the next alarm created would take its number and inherit its ring,
        // late ring, check, card and cascade state.
        const a = NivaatAlarm(id: 4, hour: 6, minute: 0, courtId: 'c1');
        await store.saveAlarms([a], alarmIdSeq: 5);
        expect(await store.loadAlarmIdSeq(), 5);
        expect((await store.loadAlarms()).single.id, 4);

        // An edit passes no counter, and must leave it exactly where it was.
        await store.saveAlarms([a.copyWith(enabled: false)]);
        expect(await store.loadAlarmIdSeq(), 5);
        expect((await store.loadAlarms()).single.enabled, isFalse);
      });

      test('clearing by occurrence ignores a slot that has moved on', () async {
        // This replaced a load-compare-delete, and the gap in that older shape
        // is exactly where a roll-on writes the NEXT occurrence's state — which
        // the delete would then throw away.
        final today = DateTime(2026, 7, 13, 6, 0);
        final tomorrow = DateTime(2026, 7, 14, 6, 0);
        await store.saveCheckState(
            CheckState(alarmId: 7, alarmAt: tomorrow, ringScheduled: true));
        await store.savePendingRing(PendingRing(
          alarmId: 7,
          pluginId: 10007,
          role: RingLockerRole.ring,
          occurrenceAt: tomorrow,
          scheduledFor: tomorrow,
          courtId: 'c1',
        ));

        await store.clearCheckStateForOccurrence(7, today);
        await store.clearPendingRingForOccurrence(7, today);
        expect((await store.loadCheckState(7))!.alarmAt, tomorrow,
            reason: "today's settle must not delete tomorrow's state");
        expect((await store.loadPendingRing(7))!.occurrenceAt, tomorrow);

        await store.clearCheckStateForOccurrence(7, tomorrow);
        await store.clearPendingRingForOccurrence(7, tomorrow);
        expect(await store.loadCheckState(7), isNull);
        expect(await store.loadPendingRing(7), isNull);
      });
    });
  });
}
