import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/courts.dart';
import 'package:nivaat/src/engine.dart';
import 'package:nivaat/src/home_screen.dart';
import 'package:nivaat/src/skip_notifier.dart';

/// MESSAGES.md N1/N2 — the ring, and every state of the morning's one card,
/// locked as strings.
///
/// These are the only place the user ever reads *why* an alarm did or didn't
/// ring, and until 2026-07-22 nothing asserted them (the fakes in
/// `engine_test` accept a title and drop it). Worked examples match
/// MESSAGES.md exactly: Society Court, limit 4 (gust cap ≤15), alarm 06:00.
///
/// `morning_story_test` covers the same strings end to end, from a real
/// cascade. These cover the shapes that cascade can't reach on demand —
/// gusty, no-data, a deadline across midnight — and pin the builders directly.
void main() {
  final at = DateTime(2026, 7, 18, 6, 0);
  final until = DateTime(2026, 7, 18, 6, 30);

  HistoryRecord record(
    CheckOutcome outcome, {
    double? wind,
    double? gust,
    DateTime? checkedAt,
    DateTime? endedAt,
  }) =>
      HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: at,
        outcome: outcome,
        checkedAt: checkedAt ?? at,
        checkingEndedAt: endedAt,
        courtSpeedKmh: wind,
        rawGustKmh: gust,
        courtSpeedLimitKmh: wind == null ? null : 4,
        rawGustLimitKmh: gust == null ? null : 15,
      );

  const statuses = [
    kNivaatRing,
    kNivaatStillChecking,
    kNivaatSkipped,
    kNivaatCancelled,
  ];

  group('N3 — the Android channel', () {
    // Unasserted until 2026-07-31 (they were private). The name and
    // description are what you read in Android's notification settings when
    // deciding whether to keep hearing this app; the id is persisted, and
    // Android freezes a channel's importance at creation, so renaming the id
    // orphans the live channel and quietly resets the user's choice.
    test('id, name and description', () {
      expect(SkipNotifier.channelId, 'nivaat_alarm_updates');
      expect(SkipNotifier.channelName, 'Alarm updates');
      expect(SkipNotifier.channelDescription,
          "Still checking, and why an alarm didn't ring");
    });

    test('named for the channel, never for one of its states', () {
      // `Skipped alarms` (until 2026-07-22) meant muting the skip
      // explanations also killed the still-checking card — the one still
      // worth acting on. The channel carries all three states of N2.
      for (final state in [kNivaatSkipped, kNivaatCancelled]) {
        expect(SkipNotifier.channelName, isNot(contains(state)));
      }
    });
  });

  group('title — {court} · {HH:MM} · {status}', () {
    test('the ring, and the three states of the morning card', () {
      expect(nivaatNotificationTitle('Society Court', at, kNivaatRing),
          'Society Court · 06:00 · Play! 🏸');
      expect(nivaatNotificationTitle('Society Court', at, kNivaatStillChecking),
          'Society Court · 06:00 · Still checking');
      expect(nivaatNotificationTitle('Society Court', at, kNivaatSkipped),
          'Society Court · 06:00 · Skipped');
      expect(nivaatNotificationTitle('Society Court', at, kNivaatCancelled),
          'Society Court · 06:00 · Cancelled');
    });

    test('statuses are sentence-capitalised — they head a title', () {
      for (final status in statuses) {
        expect(status[0], status[0].toUpperCase());
      }
    });

    test('never names the app — the OS header already does', () {
      for (final status in statuses) {
        expect(nivaatNotificationTitle('Society Court', at, status),
            isNot(contains('Nivaat')));
      }
    });

    test('"Cancelled", never "Stopped" — the ring\'s own button is Stop', () {
      expect(statuses, isNot(contains('Stopped')),
          reason: 'a card titled Stopped reads as "you silenced the alarm"');
    });
  });

  group('checked note — one phrase, three labels', () {
    test('same day as the alarm: time only', () {
      expect(nivaatCheckedNote(DateTime(2026, 7, 18, 5, 59), at),
          ' · last checked 05:59');
    });

    test('across midnight: dated, so it can\'t read as this morning', () {
      expect(nivaatCheckedNote(DateTime(2026, 7, 17, 22, 0), at),
          ' · last checked 17 Jul 22:00');
    });

    test('nothing ever succeeded: "last tried"', () {
      expect(nivaatCheckedNote(at, at, tried: true), ' · last tried 06:00');
    });

    test('the ring says plain "checked" — one check approved it', () {
      expect(nivaatCheckedNote(at, at, ring: true), ' · checked 06:00',
          reason: '"last" would imply other checks that never happened');
    });
  });

  group('still-checking body', () {
    test('windy', () {
      expect(
        nivaatStillCheckingBody(
            record(CheckOutcome.skippedWindy, wind: 6, gust: 18), until),
        'Too windy · wind 6 (≤4) · gusts 18 (≤15) km/h · last checked 06:00 · '
        'watching until 06:30',
      );
    });

    test('the deadline follows the per-alarm retry cap (1-min window)', () {
      expect(
        nivaatStillCheckingBody(
            record(CheckOutcome.skippedWindy, wind: 6, gust: 18),
            at.add(const Duration(minutes: 1))),
        'Too windy · wind 6 (≤4) · gusts 18 (≤15) km/h · last checked 06:00 · '
        'watching until 06:01',
      );
    });

    test('a deadline across midnight carries its date', () {
      final late = DateTime(2026, 7, 22, 23, 49);
      final r = HistoryRecord(
        alarmId: 7,
        courtId: 'c1',
        at: late,
        outcome: CheckOutcome.skippedWindy,
        checkedAt: late,
        courtSpeedKmh: 6,
        rawGustKmh: 18,
        courtSpeedLimitKmh: 4,
        rawGustLimitKmh: 15,
      );
      expect(nivaatStillCheckingBody(r, late.add(const Duration(minutes: 30))),
          endsWith('watching until 23 Jul 00:19'),
          reason: 'a bare 00:19 would look earlier than the 23:49 alarm');
    });

    test('gusty', () {
      expect(
        nivaatStillCheckingBody(
            record(CheckOutcome.skippedGusty, wind: 3, gust: 16), until),
        'Too gusty · wind 3 (≤4) · gusts 16 (≤15) km/h · last checked 06:00 · '
        'watching until 06:30',
      );
    });

    test('no-data — "last tried", and no numbers to show', () {
      expect(
        nivaatStillCheckingBody(record(CheckOutcome.skippedNoData), until),
        "Couldn't reach the wind · last tried 06:00 · watching until 06:30",
      );
    });

    test('is the skipped body plus the deadline', () {
      final r = record(CheckOutcome.skippedWindy, wind: 6, gust: 18);
      expect(nivaatStillCheckingBody(r, until),
          '${nivaatSkippedBody(r)} · watching until 06:30');
    });
  });

  group('skipped body', () {
    final checked = DateTime(2026, 7, 18, 6, 29);

    test('windy', () {
      expect(
        nivaatSkippedBody(record(CheckOutcome.skippedWindy,
            wind: 6, gust: 18, checkedAt: checked)),
        'Too windy · wind 6 (≤4) · gusts 18 (≤15) km/h · last checked 06:29',
      );
    });

    test('gusty', () {
      expect(
        nivaatSkippedBody(record(CheckOutcome.skippedGusty,
            wind: 3, gust: 16, checkedAt: checked)),
        'Too gusty · wind 3 (≤4) · gusts 16 (≤15) km/h · last checked 06:29',
      );
    });

    test('no-data — no numbers', () {
      expect(
        nivaatSkippedBody(record(CheckOutcome.skippedNoData, checkedAt: checked)),
        "Couldn't reach the wind · last tried 06:29",
      );
    });

    test('says how far checking reached when it outlasted the reading', () {
      expect(
        nivaatSkippedBody(record(CheckOutcome.skippedWindy,
            wind: 6, gust: 18, checkedAt: checked, endedAt: until)),
        'Too windy · wind 6 (≤4) · gusts 18 (≤15) km/h · last checked 06:29 · '
        'watched until 06:30',
      );
    });

    test('and stays quiet when they are the same minute', () {
      expect(
        nivaatSkippedBody(record(CheckOutcome.skippedWindy,
            wind: 6, gust: 18, checkedAt: checked, endedAt: checked)),
        'Too windy · wind 6 (≤4) · gusts 18 (≤15) km/h · last checked 06:29',
      );
    });

    test('a ring is never notified — empty body suppresses the card', () {
      expect(nivaatSkippedBody(record(CheckOutcome.rang, wind: 3, gust: 12)), '');
    });
  });

  group('cancelled body', () {
    test('carries the reason it had not rung, plus when you stopped it', () {
      expect(
        nivaatCancelledBody(record(CheckOutcome.skippedWindy,
            wind: 6, gust: 18, endedAt: at.add(const Duration(minutes: 5)))),
        'Too windy · wind 6 (≤4) · gusts 18 (≤15) km/h · last checked 06:00 · '
        'stopped 06:05',
      );
    });

    test('richer than its history row, which has a neighbour to lean on', () {
      final stoppedAt = at.add(const Duration(minutes: 5));
      final r = record(CheckOutcome.skippedWindy,
          wind: 6, gust: 18, endedAt: stoppedAt);
      expect(nivaatCancelledBody(r), contains('wind 6 (≤4)'),
          reason: 'the card stands alone, so it carries the evidence');
      // The row is bare — no numbers AND no freshness clause. Asserted as the
      // whole sub, not just the note: `last checked` leaking back in here is
      // exactly the drift this locks out.
      expect(
        nivaatHistorySub(
          HistoryRecord(
            alarmId: 7,
            courtId: 'c1',
            at: at,
            kind: HistoryKind.cancelled,
            outcome: CheckOutcome.skippedWindy,
            checkedAt: at,
            checkingEndedAt: stoppedAt,
          ),
          'Society Court',
        ),
        'Society Court · 18 Jul · 06:00 · stopped 06:05',
        reason: 'the row sits under the still-checking row that has them',
      );
    });
  });

  group('N20 — delete-court warning', () {
    test('every count variant reads as English', () {
      // The singular was wrong in shipped code ("1 alarm use Society Court")
      // and MESSAGES.md hid it behind an `{n} alarm(s) use {court}` shorthand
      // that never renders — nobody reads the one case the template elides.
      expect(nivaatDeleteCourtWarning('Society Court', 1, 0),
          'Deleting Society Court also deletes 1 alarm. Continue?');
      expect(nivaatDeleteCourtWarning('Society Court', 2, 0),
          'Deleting Society Court also deletes 2 alarms. Continue?');
      expect(
        nivaatDeleteCourtWarning('Society Court', 1, 1),
        'Deleting Society Court also deletes 1 alarm and 1 history entry. '
        'Continue?',
      );
      expect(
        nivaatDeleteCourtWarning('Society Court', 2, 5),
        'Deleting Society Court also deletes 2 alarms and 5 history entries. '
        'Continue?',
      );
      expect(nivaatDeleteCourtWarning('Society Court', 0, 1),
          'Deleting Society Court also deletes 1 history entry. Continue?');
      expect(nivaatDeleteCourtWarning('Society Court', 0, 5),
          'Deleting Society Court also deletes 5 history entries. Continue?');
      // The fourth shape, added 2026-08-15 when the dialog stopped being
      // skipped for a bare court (Samyak). "Nothing to warn about" was the
      // wrong call: the row does not say whether an alarm points here, so the
      // user could not know which of these four they were skipping.
      expect(nivaatDeleteCourtWarning('Society Court', 0, 0),
          'No alarm uses Society Court. Continue?');
      // **One verb over both nouns** (2026-08-15). The old shape was
      // `2 alarms use {court} and will be deleted too, along with 5 history
      // entries`, and the two rewrites weighed against it both said history
      // *uses* a court — which it does not — and needed a plural verb for a
      // compound subject on top. `deletes` governs both, so nothing has to
      // agree with a count.
      expect(nivaatDeleteCourtWarning('Society Court', 2, 5),
          isNot(contains('along with')));
    });
  });

  group('X3 — notifications-off banner, both Nivaat variants', () {
    test('Android names the on-screen Stop it also loses', () {
      expect(
        kNivaatNotificationsOffAndroid,
        'Notifications are off — a ringing alarm shows nothing on screen '
        "(sound only, no Stop), and Nivaat can't tell you when it skips an "
        'alarm for wind, or why.',
      );
    });

    test('iOS drops that clause — AlarmKit draws its own alert', () {
      expect(
        kNivaatNotificationsOffIos,
        "Notifications are off — Nivaat can't tell you when it skips an "
        'alarm for wind, or why.',
      );
      expect(kNivaatNotificationsOffIos, isNot(contains('no Stop')),
          reason: 'the iOS ring is the OS\'s own alert, Stop included');
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
      for (final body in [
        nivaatStillCheckingBody(r, until),
        nivaatSkippedBody(r),
      ]) {
        expect(body, isNot(contains('Society'))); // the title names the court
        expect(body, isNot(contains('will ring')));
        expect(body, isNot(contains('next time')));
        expect(body, isNot(contains('🏸'))); // lives in the ring's status only
      }
    }
  });
}
