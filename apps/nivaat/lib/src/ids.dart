/// THE ID MAP for Nivaat. Every scheduled thing — rings, wind checks,
/// notification cards — gets its number here and nowhere else, so the whole
/// layout is readable in one place and `test/ids_test.dart` can assert the
/// blocks never overlap.
///
/// Layout — 10000-wide blocks, decodable by division
/// (`id ~/ 10000` = which kind, `id % 10000` = which alarm):
///
///      10000 + alarmId   ring armed for the occurrence's own time
///      20000 + alarmId   LATE ring, armed after T inside the retry window
///      30000 + alarmId   the morning's card
///      40000 + alarmId   pre-arm for the NEXT occurrence, written at roll-on
///     100000 + alarmId   wind check, rung 0 (T-24h)
///     110000 + alarmId   wind check, rung 1 (T-12h)
///        ... one block per rung ...
///     180000 + alarmId   wind check, rung 8 (T-0), reused by post-T retries
///
/// One card per morning (2026-07-26): it posts at T as "Still checking" and
/// is rewritten in place to "Skipped" / "Cancelled" as the morning resolves,
/// so the old 50000 "skipped" block went away. 50000 is now [NivaatIds.nextRing]
/// — a deliberate reuse of a freed number, not an oversight. Nothing sat above
/// it, so nothing renumbered, and a card already posted under the old meaning
/// is not a case this repo carries (see CLAUDE.md on the no-migration policy).
///
/// **A block's width must exceed the largest index it can ever hold** (see
/// CLAUDE.md). The index here is an alarm id from `nextAlarmId()`, a PERSISTED
/// counter that only ever climbs (REVIEW #9), so the blocks are 10000 wide
/// (Arunoday's are 1000 — its index is a bounded 0..6 day-slot, a different
/// domain and so a different answer to the same rule).
///
/// Two of these offsets are load-bearing, not cosmetic: the `alarm` package
/// posts its Android ring notification with `startForeground(id, ...)` — its
/// notification id IS the alarm id — so a card sharing that number would
/// erase the ring's own card and its Stop button.
library;

import 'package:core/core.dart';

class NivaatIds {
  NivaatIds._();

  /// The largest alarm id the blocks can hold without touching. Asserted by
  /// `ids_test.dart`; far beyond anything `nextAlarmId()` can reach in
  /// practice (it hands out 1, 2, 3, …).
  ///
  /// It is also a real ceiling, not just a bound: `NivaatController.nextAlarmId`
  /// stops at this number and falls back to the smallest id no live alarm
  /// holds, because the counter behind it only climbs (REVIEW #9 · #21).
  static const int maxAlarmId = 9999;

  static const int ringBlock = 10000;
  static const int lateRingBlock = 20000;
  static const int cardBlock = 30000;
  static const int nextRingBlock = 40000;

  /// Where the per-rung check blocks start. Renumbered 2026-08-25 when the
  /// single chained check became one booking per rung — the old 30000 check
  /// block was freed and the card and next-ring blocks moved down into the
  /// gap, so the layout stays contiguous rather than carrying a hole.
  ///
  /// Safe to renumber precisely because these ids are **ephemeral**: they are
  /// recomputed from scratch on every resync and never persisted as user data.
  static const int firstCheckBlock = 100000;

  /// The ring armed for an occurrence's own scheduled time — the pre-arm the
  /// ladder commits at T-1h, T-30m, … Re-deciding the same occurrence rewrites
  /// this same number, which is exactly what you want: eight ladder rungs must
  /// converge on ONE armed ring, not scatter eight of them.
  static int ring(int alarmId) => ringBlock + alarmId;

  /// The LATE ring: armed at or after T, when a retry inside the retry window
  /// finds the wind has calmed and rings a few seconds from now.
  ///
  /// It needs its own locker because the very pass that arms it then closes
  /// the occurrence and **pre-arms the next one** — and writing a ring evicts
  /// whatever the locker held. Sharing one locker meant that pre-arm cancelled
  /// the late ring about ten seconds before it sounded, while history still
  /// recorded "Rang".
  ///
  /// Split by ROLE, not by the occurrence's calendar day. A day-parity split
  /// looks equivalent but silently fails whenever consecutive occurrences are
  /// an even number of days apart — a Mon+Fri alarm (4 days) lands both on the
  /// same parity and the collision returns.
  static int lateRing(int alarmId) => lateRingBlock + alarmId;

  /// The pre-arm for the NEXT occurrence, written by the pass that has just
  /// closed the previous one (`NivaatEngine._rollOn`).
  ///
  /// Third locker, and it exists for the same reason as the second. That pass
  /// runs *at* T — which is the very moment [ring]'s own alarm is due but may
  /// not have sounded yet. `Alarm.set` stops any alarm sharing the id before
  /// writing the new one (verified in `alarm 5.6.0`, `lib/alarm.dart:113`), so
  /// a check landing at 06:00:02 finalised the morning and pre-armed tomorrow
  /// **into the same number**, cancelling the ring that was a heartbeat from
  /// waking you — while history recorded `Rang`.
  ///
  /// Handed over to [ring] at that occurrence's own first ladder rung: cancel
  /// this, then arm [ring]. **Cancel-then-set, never set-then-cancel** — two
  /// live alarms for one instant ring twice, whereas the gap cancel-first
  /// leaves is closed by the very next line and re-armed by seven more rungs.
  ///
  /// Split by ROLE like [lateRing], so the same day-parity trap does not apply.
  static int nextRing(int alarmId) => nextRingBlock + alarmId;

  /// EVERY ring locker for [alarmId]. Cancel all of these whenever an alarm is
  /// deleted, disabled, or edited, and ask all of them when checking whether
  /// one is audible — the role you are not currently looking at may still be
  /// holding an armed ring.
  static List<int> allRings(int alarmId) =>
      [ring(alarmId), lateRing(alarmId), nextRing(alarmId)];

  /// The alarm behind a RING id from any of the three lockers, or null when
  /// [id] is not a ring at all.
  ///
  /// For `NivaatEngine`'s orphan sweep, which gets raw numbers back from
  /// `scheduledIds()` and may only cancel rings whose alarm has left the
  /// store. Deliberately returns null for checks and cards: those are not
  /// this scheduler's to cancel, and mistaking one for a ring would cancel by
  /// a number that means something else entirely.
  static int? alarmIdOfRing(int id) {
    for (final block in const [ringBlock, lateRingBlock, nextRingBlock]) {
      // Alarm ids start at 1, so `block` itself is never a valid ring.
      if (id > block && id <= block + maxAlarmId) return id - block;
    }
    return null;
  }

  /// Which locker [id] belongs to, or null when it is not a ring id at all.
  static RingLockerRole? ringRoleOf(int id) {
    if (alarmIdOfRing(id) == null) return null;
    if (id > ringBlock && id <= ringBlock + maxAlarmId) {
      return RingLockerRole.ring;
    }
    if (id > lateRingBlock && id <= lateRingBlock + maxAlarmId) {
      return RingLockerRole.lateRing;
    }
    if (id > nextRingBlock && id <= nextRingBlock + maxAlarmId) {
      return RingLockerRole.nextRing;
    }
    return null;
  }

  /// The wakeup id for one LADDER RUNG.
  ///
  /// **Every pre-T rung is booked up front, each in its own locker** (Samyak,
  /// 2026-08-25). It used to be a chain: one id per alarm, and each check that
  /// fired booked the next into that same number. Nine rungs made that nine
  /// links, and breaking any one of them silently deleted every rung after it
  /// — kill the app mid-fetch at T-6h and T-3h, T-2h, T-1h, T-30m, T-15m and
  /// T-0 were simply never created. The only recoveries were opening the app or
  /// ANOTHER alarm's check firing, so a lone alarm had no backstop at all.
  ///
  /// Independent bookings cost nine cancels per edit and buy the property that
  /// no rung can take its successors down with it. **It does not defeat Doze** —
  /// that throttles firing, not booking — but every gap in the ladder is >=15
  /// minutes, comfortably past Doze's ~9-minute quota, so throttling was never
  /// what was eating them.
  static int check(int alarmId, int rung) =>
      firstCheckBlock + rung * 10000 + alarmId;

  /// The rung post-T retries reuse — the LAST one (T-0).
  ///
  /// Retries are still chained, and correctly so: only one can ever be
  /// outstanding, each is booked by the one before it, and by the time they run
  /// T-0 has long since fired and freed its number. Chaining is only dangerous
  /// where a break loses bookings that were already knowable; here the next
  /// retry is not knowable until this one has decided.
  ///
  /// **Named here rather than spelled out at the one place that books it**
  /// (2026-08-30): `_rungsAhead` wrote `ladder.length - 1` inline, which said
  /// the same thing in a second voice — and left [retryCheck] with no caller
  /// outside the tests, which is how a rule quietly ends up with two homes.
  static int get retryRung => CheckCascade.ladderMinutesBefore.length - 1;

  /// [retryRung]'s locker id, for a caller that wants the number rather than
  /// the index.
  static int retryCheck(int alarmId) => check(alarmId, retryRung);

  /// Every check locker for [alarmId] — cancel all of these on edit or delete.
  static List<int> allChecks(int alarmId) => [
        for (var r = 0; r < CheckCascade.ladderMinutesBefore.length; r++)
          check(alarmId, r),
      ];

  /// The morning's one notification. Posted at T and rewritten in place —
  /// same number throughout, which is what lets a later push replace the
  /// card rather than stack a second one beside it.
  static int card(int alarmId) => cardBlock + alarmId;
}
