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
        extendedCheckShown: true,
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

    test('upsertHistory: same event converges; heads-up and final stay apart',
        () async {
      final at = DateTime(2026, 7, 13, 6, 0);
      final cap = at.add(const Duration(minutes: 30));
      HistoryRecord row(CheckOutcome outcome,
              {DateTime? watched, DateTime? when, int alarm = 7}) =>
          HistoryRecord(
              alarmId: alarm,
              courtId: 'c1',
              at: when ?? at,
              watchedUntil: watched,
              outcome: outcome);

      // The heads-up snapshot written twice (racing isolates) -> ONE row.
      await store.upsertHistory(row(CheckOutcome.skippedWindy, watched: cap));
      await store.upsertHistory(row(CheckOutcome.skippedWindy, watched: cap));
      var h = await store.loadHistory();
      expect(h, hasLength(1), reason: 'double-write of one event converges');

      // The final outcome is a SEPARATE row — the snapshot survives it
      // (append-only log, user decision 2026-07-20).
      await store.upsertHistory(row(CheckOutcome.rang));
      h = await store.loadHistory();
      expect(h, hasLength(2));
      expect(h.first.outcome, CheckOutcome.rang, reason: 'final prepends');
      expect(h.last.watchedUntil, cap, reason: 'snapshot row still there');

      // A racing double-write of the final converges onto it too.
      await store.upsertHistory(row(CheckOutcome.rang));
      expect(await store.loadHistory(), hasLength(2));

      // Different occurrence / different alarm = new rows.
      await store.upsertHistory(
          row(CheckOutcome.skippedGusty, when: at.add(const Duration(days: 1))));
      await store.upsertHistory(row(CheckOutcome.skippedWindy, alarm: 8));
      expect(await store.loadHistory(), hasLength(4));
    });

    test('refresh() reloads prefs without disturbing stored data', () async {
      // The real point of refresh() — seeing another isolate's writes — needs
      // two isolates and is device territory; here we pin that a reload is
      // non-destructive and safe to call at every resync.
      await store.saveSoundPath('/tones/x.ogg');
      await store.refresh();
      expect(await store.loadSoundPath(), '/tones/x.ogg');
    });

    test('history prepends newest and caps at 60', () async {
      for (var i = 0; i < 65; i++) {
        await store.addHistory(HistoryRecord(
          alarmId: i,
          courtId: 'c1',
          at: DateTime(2026, 7, 13, 6, i % 60),
          outcome: CheckOutcome.rang,
          courtSpeedKmh: 1,
          volume: 1,
        ));
      }
      final h = await store.loadHistory();
      expect(h.length, 60, reason: 'capped at the 60 newest');
      expect(h.first.alarmId, 64, reason: 'newest is first');
      expect(h.last.alarmId, 5, reason: 'oldest kept is #5 (0-4 dropped)');
    });

    test('removeHistoryForCourt drops every row for that court, keeps others',
        () async {
      // Two rows for c1 (one from an alarm that no longer matters), one for c2.
      for (final (id, courtId) in [(1, 'c1'), (9, 'c1'), (2, 'c2')]) {
        await store.addHistory(HistoryRecord(
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
