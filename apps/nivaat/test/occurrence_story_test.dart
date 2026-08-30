import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/controller.dart';
import 'package:nivaat/src/engine.dart';
import 'package:nivaat/src/skip_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine_fakes.dart';

/// Every way one alarm's occurrence can end, as the user actually sees it —
/// the card in the shade and the rows in the log, asserted as whole strings.
///
/// **An occurrence, not "a morning"** (Samyak, 2026-08-25). The codebase used
/// the two as synonyms throughout, which was harmless until it reached the
/// screen — the editor's timeline shipped a `YOUR MORNING` heading above an
/// alarm nothing stops you setting for 15:00. This file's name went with it;
/// the fixtures below are still 06:00 mornings, and the prose still calls them
/// that where that is what they are.
///
/// This file is the catalogue Samyak signed off on (2026-07-26). Counting
/// pushes or rows is not enough: every wording decision in this change lives
/// in a body or a sub, so the assertions are the literal text. If one of these
/// strings has to change, it is a product decision, not a refactor.
///
/// Alarm 06:00 · ≤4 km/h (gust guard ≤15) · Keep checking 30m · Society Court.
void main() {
  const court =
      SavedLocation(id: 'c1', name: 'Society Court', lat: 26.17, lon: 75.79);
  const alarm =
      NivaatAlarm(id: 7, hour: 6, minute: 0, courtId: 'c1', courtSpeedLimitKmh: 4);
  final alarmAt = DateTime(2026, 7, 12, 6, 0);
  final cap = alarmAt.add(const Duration(minutes: 30));

  // wind(9,10) → court 5.4 (>4, windy). wind(5,5) → court 3.0 (calm).
  // **The reason names the slot the numbers came from, not the check time.**
  // A morning is decided across the whole play window, so `Too windy · … ·
  // last checked 06:00` was contradictory: 06:00 may have been calm, and the
  // five came from a slot half an hour later.
  const windyBody = 'Too windy at 06:30 · wind 5 (≤4) · gusts 10 (≤15) km/h';
  // A check at the 06:30 cap would ring ~now, putting you on court at 07:00 —
  // so its window, and its slot, are an hour past the alarm's. Each retry
  // judges its OWN window.
  const windyBodyAtCap =
      'Too windy at 07:00 · wind 5 (≤4) · gusts 10 (≤15) km/h';
  // Case 5/6: the last reading that SUCCEEDED came from the 06:29 check, whose
  // own window opened at 06:59 — and slots sit on the quarter hour, so the one
  // covering your arrival is 06:45. The row quotes the slot behind its
  // numbers, so it stays 06:45 even though checking ran on to the cap.
  const windyBodyFrom0629 =
      'Too windy at 06:45 · wind 5 (≤4) · gusts 10 (≤15) km/h';
  // **History quotes the slot too, now** (2026-08-25). It always carried one —
  // the card had been naming it since the window rule landed — but the column
  // was written and never read back, so every row that went through the
  // database lost it. The card looked right because it reads the record still
  // in memory; the sheet, which can only read from disk, did not.
  //
  // Trailing here, leading on the card: `Too windy at 06:45` reads as a
  // condition of a moment, while `Skipped at 06:45` would read as when the
  // skip was decided — a different fact, and one the sub already carries.
  //
  // Three variants for the same three reasons the card has three: each check
  // judges its OWN window, so a retry's slot is later than T's.
  const windyLine = 'wind 5 (≤4) · gusts 10 (≤15) km/h · at 06:30';
  const windyLineAtCap = 'wind 5 (≤4) · gusts 10 (≤15) km/h · at 07:00';
  const windyLineFrom0629 = 'wind 5 (≤4) · gusts 10 (≤15) km/h · at 06:45';

  late FakeRing ring;
  late FakeChecks checks;
  late FakeApi api;
  late FakeNotifier notifier;
  late NivaatEngine engine;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ring = FakeRing();
    checks = FakeChecks();
    api = FakeApi();
    notifier = FakeNotifier();
    final store = NivaatStore();
    await store.saveCourts([court]);
    await store.saveAlarms([alarm]);
    engine = NivaatEngine(
      store: store,
      scheduler: ring,
      api: api,
      checks: checks,
      notifier: notifier,
    );
  });

  /// Every row for the morning, oldest first — the sheet renders newest first,
  /// but a story reads better forwards.
  Future<List<HistoryRecord>> rows() async {
    final all = await engine.store.loadHistory();
    return all.reversed.toList();
  }

  /// The sheet's own builder, not a copy of it — a hand-rolled version here
  /// passed while the sheet itself still said `checked` (2026-07-26).
  String sub(HistoryRecord h) => nivaatHistorySub(h, court.name);

  Future<List<String>> story() async => [
        for (final h in await rows()) '${nivaatHistoryLine(h)}\n${sub(h)}',
      ];

  Future<void> runAt(DateTime t, {NivaatAlarm a = alarm}) =>
      engine.evaluateAlarm(a, [court], now: t);

  /// Windy at T: the morning opens its card and its first row.
  Future<void> openWindyWindow({DateTime? firstRun}) async {
    api.sample = wind(9.0, 10.0);
    await runAt(alarmAt.subtract(const Duration(minutes: 1)));
    await runAt(firstRun ?? alarmAt);
  }

  group('1-2 — the app never ran inside the window', () {
    test('1 · one row, quoting the reading it had', () async {
      api.sample = wind(9.0, 10.0);
      await runAt(alarmAt.subtract(const Duration(hours: 4))); // 02:00
      await runAt(alarmAt.add(const Duration(minutes: 31)));

      expect(notifier.card!.status, kNivaatSkipped);
      expect(notifier.card!.body, '$windyBody · last checked 02:00');
      expect(await story(), [
        'Skipped · $windyLine\n'
            'Society Court · 12 Jul · 06:00 · last checked 02:00',
      ]);
    });

    test('2 · no reading ever succeeded', () async {
      api.fail = true;
      await runAt(alarmAt.subtract(const Duration(hours: 4)));
      await runAt(alarmAt.add(const Duration(minutes: 31)));

      expect(notifier.card!.status, kNivaatSkipped);
      expect(notifier.card!.body, "Couldn't reach the wind · last tried 02:00");
      expect(await story(), [
        'Skipped (no data)\n'
            'Society Court · 12 Jul · 06:00 · last tried 02:00',
      ]);
    });
  });

  group('3-6 — the window ran', () {
    test('3 · checked every minute, still windy at the cap', () async {
      await openWindyWindow();
      expect(notifier.card!.status, kNivaatStillChecking);
      expect(notifier.card!.body,
          '$windyBody · last checked 06:00 · watching until 06:30');

      for (var m = 1; m <= 30; m++) {
        await runAt(alarmAt.add(Duration(minutes: m)));
      }

      expect(notifier.card!.status, kNivaatSkipped);
      expect(notifier.card!.body, '$windyBodyAtCap · last checked 06:30');
      expect(await story(), [
        'Still checking · $windyLine\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:00 '
            '· watching until 06:30',
        // The CAP check judged this one, and a ring at 06:30 puts you on
        // court at 07:00 — its own window, its own slot. Same reason the card
        // above says `windyBodyAtCap`.
        'Skipped · $windyLineAtCap\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:30',
      ]);
    });

    test('4 · cap check late, still inside the cap MINUTE — same as case 3',
        () async {
      await openWindyWindow();
      for (var m = 1; m <= 29; m++) {
        await runAt(alarmAt.add(Duration(minutes: m)));
      }
      await runAt(cap.add(const Duration(seconds: 40)));

      expect(notifier.card!.body, '$windyBodyAtCap · last checked 06:30',
          reason: 'it read the wind at 06:30:40, which displays as 06:30');
      expect((await rows()).last.kind, HistoryKind.outcome);
      expect(nivaatHistoryNote((await rows()).last), isNull,
          reason: 'checking and the reading ended together — nothing to add');
    });

    test('5 · cap check past the minute — falls back to the 06:29 reading',
        () async {
      await openWindyWindow();
      for (var m = 1; m <= 29; m++) {
        await runAt(alarmAt.add(Duration(minutes: m)));
      }
      await runAt(cap.add(const Duration(minutes: 1, seconds: 10)));

      expect(notifier.card!.body, '$windyBodyFrom0629 · last checked 06:29');
      expect(await story(), [
        'Still checking · $windyLine\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:00 '
            '· watching until 06:30',
        // The last reading that SUCCEEDED came from 06:29, whose window
        // opened at 06:59 — and slots sit on the quarter hour, so 06:45 is
        // the one covering your arrival.
        'Skipped · $windyLineFrom0629\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:29',
      ]);
    });

    test('6 · network blip exactly at the cap — says it still tried', () async {
      await openWindyWindow();
      for (var m = 1; m <= 29; m++) {
        await runAt(alarmAt.add(Duration(minutes: m)));
      }
      api.fail = true;
      await runAt(cap);

      expect(notifier.card!.body,
          '$windyBodyFrom0629 · last checked 06:29 · watched until 06:30',
          reason: 'the 06:30 attempt is the only thing separating 6 from 5');
      expect(await story(), [
        'Still checking · $windyLine\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:00 '
            '· watching until 06:30',
        // Same 06:29 reading as case 5 — the 06:30 attempt reached nothing,
        // so it moved the watched-until and not the numbers.
        'Skipped · $windyLineFrom0629\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:29 '
            '· watched until 06:30',
      ]);
    });
  });

  group('7-9 — the window stopped early', () {
    test('7a · first ran at 06:10, one check, back at 09:00', () async {
      await openWindyWindow(firstRun: alarmAt.add(const Duration(minutes: 10)));
      await runAt(alarmAt.add(const Duration(hours: 3)));

      expect(notifier.card!.status, kNivaatSkipped);
      expect(notifier.card!.body, '$windyBody · last checked 06:10');
      expect(await story(), [
        'Still checking · $windyLine\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:10 '
            '· watching until 06:30',
        'Skipped · $windyLine\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:10',
      ]);
    });

    test('7b · ran 06:00 to 06:10, then stopped', () async {
      await openWindyWindow();
      for (var m = 1; m <= 10; m++) {
        await runAt(alarmAt.add(Duration(minutes: m)));
      }
      await runAt(alarmAt.add(const Duration(hours: 3)));

      expect(notifier.card!.body, '$windyBody · last checked 06:10');
      expect(await story(), [
        'Still checking · $windyLine\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:00 '
            '· watching until 06:30',
        'Skipped · $windyLine\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:10',
      ]);
    });

    test('9 · the app has not come back — the row still reads present tense',
        () async {
      await openWindyWindow(firstRun: alarmAt.add(const Duration(minutes: 10)));

      expect(notifier.card!.status, kNivaatStillChecking);
      expect(await story(), [
        'Still checking · $windyLine\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:10 '
            '· watching until 06:30',
      ]);
    });
  });

  group('10-11 — it rang', () {
    test('10 · wind drops at 06:07, rings late, card gives way to the ring',
        () async {
      await openWindyWindow();
      api.sample = wind(5.0, 5.0);
      final late = alarmAt.add(const Duration(minutes: 7));
      await runAt(late);
      await settleAudibleRing(
        ring: ring,
        engine: engine,
        alarm: alarm,
        courts: [court],
        now: late.add(const Duration(seconds: 10)),
      );

      expect(notifier.cancelled, contains(alarm.id),
          reason: 'the ring is that morning’s notification now');
      expect(notifier.card, isNull);
      expect(await story(), [
        'Still checking · $windyLine\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:00 '
            '· watching until 06:30',
        'Rang (vol. 85%) · wind 3 (≤4) · gusts 5 (≤15) km/h · at 06:30\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:07',
      ]);
    });

    test('11 · calm all along — one row, no card at all', () async {
      api.sample = wind(5.0, 5.0);
      await runAt(alarmAt.subtract(const Duration(minutes: 1)));
      await runAt(alarmAt);
      await settleAudibleRing(
        ring: ring,
        engine: engine,
        alarm: alarm,
        courts: [court],
        now: alarmAt.add(const Duration(seconds: 10)),
      );

      expect(notifier.pushes, isEmpty, reason: 'nothing to explain');
      expect(await story(), [
        'Rang (vol. 85%) · wind 3 (≤4) · gusts 5 (≤15) km/h · at 06:30\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:00',
      ]);
    });
  });

  group('12-16 — you ended it', () {
    /// The controller's real order for a toggle or an abandoning edit.
    Future<void> abandonAt(DateTime t, NivaatAlarm edited) async {
      await engine.store.saveAlarms([edited]);
      await engine.abandonOccurrence(alarm, now: t, keepCard: true);
      await runAt(t, a: edited);
    }

    test('12 · toggled off at 06:05 — two rows, card explains', () async {
      await openWindyWindow();
      await abandonAt(
          alarmAt.add(const Duration(minutes: 5)), alarm.copyWith(enabled: false));

      expect(notifier.card!.status, kNivaatCancelled);
      expect(notifier.card!.body, '$windyBody · last checked 06:00 · stopped 06:05');
      expect(await story(), [
        'Still checking · $windyLine\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:00 '
            '· watching until 06:30',
        'Cancelled\n'
            'Society Court · 12 Jul · 06:00 · stopped 06:05',
      ]);
    });

    test('12b · the cancelled ROW is bare, the CARD carries the evidence',
        () async {
      // Locked wording, and the one place the two surfaces deliberately differ
      // (Samyak, 2026-07-26): the row sits directly beside the still-checking
      // row that already holds the numbers and the reading behind them; the
      // card is alone in the shade, so it repeats both. Retries ran on to
      // 06:04 here, so `last checked` really would have said something new —
      // the row drops it anyway.
      await openWindyWindow();
      for (var m = 1; m <= 4; m++) {
        await runAt(alarmAt.add(Duration(minutes: m)));
      }
      await abandonAt(
          alarmAt.add(const Duration(minutes: 5)), alarm.copyWith(enabled: false));

      expect(notifier.card!.body, '$windyBody · last checked 06:04 · stopped 06:05');
      expect(sub((await rows()).last),
          'Society Court · 12 Jul · 06:00 · stopped 06:05');
    });

    test('13 · changed the time at 06:05 — same as a toggle-off', () async {
      await openWindyWindow();
      await abandonAt(
          alarmAt.add(const Duration(minutes: 5)), alarm.copyWith(hour: 7));

      expect(notifier.card!.status, kNivaatCancelled);
      expect((await rows()).last.kind, HistoryKind.cancelled);
      expect((await rows()).last.at, alarmAt,
          reason: 'the row belongs to the morning you abandoned');
    });

    test('14 · Keep checking 30 → 60 — a new row, new deadline, no outcome yet',
        () async {
      await openWindyWindow();
      final longer = alarm.copyWith(retryMinutesAfter: 60);
      await engine.store.saveAlarms([longer]);
      await engine.retainInFlightEdits(alarm, longer,
          now: alarmAt.add(const Duration(minutes: 5)));

      expect(notifier.card!.status, kNivaatStillChecking);
      expect(notifier.card!.body,
          '$windyBody · last checked 06:00 · watching until 07:00');
      expect(await story(), [
        'Still checking · $windyLine\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:00 '
            '· watching until 06:30',
        'Still checking · $windyLine\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:00 '
            '· watching until 07:00',
      ]);
    });

    test('14d · shrinking the window past now ends the morning, quietly and '
        'at once', () async {
      // 30 → 1 at T+2: the new deadline (06:01) is already behind us. The
      // card used to be re-posted — ALERTING — reading `watching until 06:01`
      // at 06:02, with a matching row that is immutable and so stayed in the
      // log for good. A promise the morning has already broken is the exact
      // thing the one-card model exists to prevent (found in review,
      // 2026-07-31).
      await openWindyWindow();
      final shorter = alarm.copyWith(retryMinutesAfter: 1);
      await engine.store.saveAlarms([shorter]);
      final t = alarmAt.add(const Duration(minutes: 2));
      await engine.retainInFlightEdits(alarm, shorter, now: t);

      expect(notifier.card!.status, kNivaatSkipped,
          reason: 'the window is simply over — not a cancellation');
      expect(await story(), [
        'Still checking · $windyLine\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:00 '
            '· watching until 06:30',
        'Skipped · $windyLine\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:00',
      ]);

      // No row may promise a deadline that had already passed when it was
      // written — the general rule, asserted rather than the one instance.
      for (final h in await rows()) {
        final until = h.watchedUntil;
        if (until == null) continue;
        expect(t.isBefore(until), isTrue,
            reason: 'row ${h.pushSeq} promised $until at $t');
      }

      // The follow-up evaluate has nothing left to close.
      await engine.evaluateAlarm(shorter, [court], now: t);
      expect(await rows(), hasLength(2));
    });

    test('14c · raising the limit AND the window keeps decision-time numbers',
        () async {
      // The natural edit while staring at "Still checking, too windy": loosen
      // the limit and extend the window in one Save. Rebuilding the card from
      // the edited alarm put the new limit beside the old reading — "Too windy
      // · wind 5 (≤20)", a card arguing with itself, in the one scenario this
      // whole feature exists to serve (found in review, 2026-07-26).
      await openWindyWindow();
      final edited =
          alarm.copyWith(courtSpeedLimitKmh: 6, retryMinutesAfter: 60);
      await engine.store.saveAlarms([edited]);
      await engine.retainInFlightEdits(alarm, edited,
          now: alarmAt.add(const Duration(minutes: 5)));

      expect(notifier.card!.body,
          '$windyBody · last checked 06:00 · watching until 07:00',
          reason: 'only the deadline moved; the evidence is untouched');
      expect(notifier.card!.body, isNot(contains('≤6')));
      expect((await rows()).last.courtSpeedLimitKmh, 4,
          reason: 'the row keeps the limit the reading was judged against');
    });

    test('14b · editing back again leaves all three rows', () async {
      await openWindyWindow();
      final longer = alarm.copyWith(retryMinutesAfter: 60);
      await engine.store.saveAlarms([longer]);
      await engine.retainInFlightEdits(alarm, longer,
          now: alarmAt.add(const Duration(minutes: 5)));
      await engine.store.saveAlarms([alarm]);
      await engine.retainInFlightEdits(longer, alarm,
          now: alarmAt.add(const Duration(minutes: 6)));

      expect(
        [for (final h in await rows()) nivaatHistoryNote(h)],
        ['watching until 06:30', 'watching until 07:00', 'watching until 06:30'],
        reason: 'rows 1 and 3 are identical text — only pushSeq keeps them apart',
      );
      expect([for (final h in await rows()) h.pushSeq], [1, 2, 3]);
    });

    test('15 · deleted at 06:05 — row still closes, card does not', () async {
      await openWindyWindow();
      await engine.store.saveAlarms([]);
      await engine.abandonOccurrence(alarm,
          now: alarmAt.add(const Duration(minutes: 5)));
      await runAt(alarmAt.add(const Duration(minutes: 5)),
          a: alarm.copyWith(enabled: false));

      expect(notifier.card, isNull, reason: 'no card for an alarm that is gone');
      expect(notifier.cancelled, contains(alarm.id));
      expect(await story(), [
        'Still checking · $windyLine\n'
            'Society Court · 12 Jul · 06:00 · last checked 06:00 '
            '· watching until 06:30',
        'Cancelled\n'
            'Society Court · 12 Jul · 06:00 · stopped 06:05',
      ]);
    });

    test('16 · court gone — card down, and the log is swept by the caller',
        () async {
      await openWindyWindow();
      await engine.evaluateAlarm(alarm.copyWith(enabled: false), const [],
          now: alarmAt.add(const Duration(minutes: 5)));

      expect(notifier.card, isNull);
      expect(notifier.cancelled, contains(alarm.id));
      expect((await rows()).length, 1,
          reason: 'no cancelled row — removeCourt deletes this log anyway');
    });

    test('cancelling before T leaves no trace', () async {
      api.sample = wind(9.0, 10.0);
      await runAt(alarmAt.subtract(const Duration(minutes: 1)));
      await engine.abandonOccurrence(alarm,
          now: alarmAt.subtract(const Duration(seconds: 30)), keepCard: true);

      expect(notifier.pushes, isEmpty);
      expect(await rows(), isEmpty,
          reason: 'a window that never opened has nothing to explain');
    });
  });

  group('through the controller', () {
    /// `init()` resyncs against the REAL clock, which books a check for the
    /// next occurrence after today — 2026-07-12 is long past. Clear that state
    /// so the morning under test starts from nothing.
    Future<NivaatController> freshController() async {
      final c = NivaatController(engine: engine);
      await c.init();
      await engine.store.clearCheckState(alarm.id);
      return c;
    }

    test('raising the limit mid-window still rings this morning', () async {
      // init() resyncs against the REAL clock, which would finalise a
      // 2026-07-12 morning before the test even starts. Build it first.
      final controller = await freshController();
      await openWindyWindow();

      api.sample = wind(5.0, 5.0);
      final t = alarmAt.add(const Duration(minutes: 5));
      expect(
          await controller.upsertAlarm(alarm.copyWith(courtSpeedLimitKmh: 6),
              now: t),
          isTrue);
      await controller.lastEvaluation;
      await settleAudibleRing(
        ring: ring,
        engine: engine,
        alarm: alarm.copyWith(courtSpeedLimitKmh: 6),
        courts: [court],
        now: t.add(const Duration(seconds: 10)),
      );

      expect((await rows()).last.outcome, CheckOutcome.rang,
          reason: 'the continue path kept today alive');
      expect((await rows()).any((h) => h.kind == HistoryKind.cancelled), isFalse);
    });

    test('toggling off mid-window cancels through the controller', () async {
      final controller = await freshController();
      await openWindyWindow();

      final t = alarmAt.add(const Duration(minutes: 5));
      await controller.toggleAlarm(alarm.id, false, now: t);
      await controller.lastEvaluation;

      expect(notifier.card!.status, kNivaatCancelled);
      expect((await rows()).last.kind, HistoryKind.cancelled);
    });
  });
}
