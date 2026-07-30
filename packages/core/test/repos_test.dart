import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
      // Everything else survives untouched (compare via JSON for one shot).
      final a = full.toJson()..remove('lastAttemptAt');
      final b = touched.toJson()..remove('lastAttemptAt');
      expect(b, a);
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

    test('refresh() reloads prefs without disturbing stored data', () async {
      // The real point of refresh() — seeing another isolate's writes — needs
      // two isolates and is device territory; here we pin that a reload is
      // non-destructive and safe to call at every resync.
      await store.saveSoundPath('/tones/x.ogg');
      await store.refresh();
      expect(await store.loadSoundPath(), '/tones/x.ogg');
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
  });
}
