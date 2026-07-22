import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/skip_notifier.dart';

/// MESSAGES.md N1/N2/N3 — the three notification cards, locked as strings.
///
/// These are the only place the user ever reads *why* an alarm did or didn't
/// ring, and until 2026-07-22 nothing asserted them (the fakes in
/// `engine_test` accept a title and drop it). Worked examples match
/// MESSAGES.md exactly: Society Court, limit 4 (gust cap ≤15), alarm 06:00.
void main() {
  final at = DateTime(2026, 7, 18, 6, 0);
  final until = DateTime(2026, 7, 18, 6, 30);

  HistoryRecord record(
    CheckOutcome outcome, {
    double? wind,
    double? gust,
    DateTime? checkedAt,
  }) =>
      HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: at,
        outcome: outcome,
        checkedAt: checkedAt ?? at,
        courtSpeedKmh: wind,
        rawGustKmh: gust,
        courtSpeedLimitKmh: wind == null ? null : 4,
        rawGustLimitKmh: gust == null ? null : 15,
      );

  group('title — {court} · {HH:MM} · {status}', () {
    test('N1 / N2 / N3', () {
      expect(nivaatNotificationTitle('Society Court', at, kNivaatRing),
          'Society Court · 06:00 · Play! 🏸');
      expect(nivaatNotificationTitle('Society Court', at, kNivaatStillChecking),
          'Society Court · 06:00 · Still checking');
      expect(nivaatNotificationTitle('Society Court', at, kNivaatSkipped),
          'Society Court · 06:00 · Skipped');
    });

    test('statuses are sentence-capitalised — they head a title', () {
      for (final status in [kNivaatRing, kNivaatStillChecking, kNivaatSkipped]) {
        expect(status[0], status[0].toUpperCase());
      }
    });

    test('never names the app — the OS header already does', () {
      for (final status in [kNivaatRing, kNivaatStillChecking, kNivaatSkipped]) {
        expect(nivaatNotificationTitle('Society Court', at, status),
            isNot(contains('Nivaat')));
      }
    });
  });

  group('checked note — one phrase for all three cards', () {
    test('same day as the alarm: time only', () {
      expect(nivaatCheckedNote(DateTime(2026, 7, 18, 5, 59), at),
          ' · checked 05:59');
    });

    test('across midnight: dated, so it can\'t read as this morning', () {
      expect(nivaatCheckedNote(DateTime(2026, 7, 17, 22, 0), at),
          ' · checked 17 Jul 22:00');
    });

    test('nothing ever succeeded: "last tried"', () {
      expect(nivaatCheckedNote(at, at, tried: true), ' · last tried 06:00');
    });
  });

  group('N2 heads-up body', () {
    test('windy', () {
      expect(
        nivaatExtendedCheckBody(
            record(CheckOutcome.skippedWindy, wind: 6, gust: 18), until),
        'Too windy · wind 6 (≤4) · gusts 18 (≤15) km/h · checked 06:00 · '
        'watching until 06:30',
      );
    });

    test('gusty', () {
      expect(
        nivaatExtendedCheckBody(
            record(CheckOutcome.skippedGusty, wind: 3, gust: 16), until),
        'Too gusty · wind 3 (≤4) · gusts 16 (≤15) km/h · checked 06:00 · '
        'watching until 06:30',
      );
    });

    test('no-data — "last tried", and no numbers to show', () {
      expect(
        nivaatExtendedCheckBody(record(CheckOutcome.skippedNoData), until),
        "Couldn't reach the wind · last tried 06:00 · watching until 06:30",
      );
    });

    test('is N3 plus the watched deadline', () {
      final r = record(CheckOutcome.skippedWindy, wind: 6, gust: 18);
      expect(nivaatExtendedCheckBody(r, until),
          '${nivaatSkipBody(r)} · watching until 06:30');
    });
  });

  group('N3 skip body', () {
    final checked = DateTime(2026, 7, 18, 6, 29);

    test('windy', () {
      expect(
        nivaatSkipBody(record(CheckOutcome.skippedWindy,
            wind: 6, gust: 18, checkedAt: checked)),
        'Too windy · wind 6 (≤4) · gusts 18 (≤15) km/h · checked 06:29',
      );
    });

    test('gusty', () {
      expect(
        nivaatSkipBody(record(CheckOutcome.skippedGusty,
            wind: 3, gust: 16, checkedAt: checked)),
        'Too gusty · wind 3 (≤4) · gusts 16 (≤15) km/h · checked 06:29',
      );
    });

    test('no-data — no numbers', () {
      expect(
        nivaatSkipBody(
            record(CheckOutcome.skippedNoData, checkedAt: checked)),
        "Couldn't reach the wind · last tried 06:29",
      );
    });

    test('a ring is never notified — empty body suppresses the card', () {
      expect(nivaatSkipBody(record(CheckOutcome.rang, wind: 3, gust: 12)), '');
    });
  });

  test('bodies are evidence only — no court, no promise, no sign-off, no 🏸',
      () {
    for (final outcome in [
      CheckOutcome.skippedWindy,
      CheckOutcome.skippedGusty,
      CheckOutcome.skippedNoData,
    ]) {
      final r = record(outcome, wind: 6, gust: 18);
      for (final body in [nivaatExtendedCheckBody(r, until), nivaatSkipBody(r)]) {
        expect(body, isNot(contains('Society'))); // the title names the court
        expect(body, isNot(contains('will ring')));
        expect(body, isNot(contains('next time')));
        expect(body, isNot(contains('🏸'))); // lives in the ring's status only
      }
    }
  });
}
