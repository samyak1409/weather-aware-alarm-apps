/// THE ID MAP for Nivaat. Every scheduled thing — rings, wind checks,
/// notification cards — gets its number here and nowhere else, so the whole
/// layout is readable in one place and `test/ids_test.dart` can assert the
/// blocks never overlap.
///
/// Layout — 10000-wide blocks, decodable by division
/// (`id ~/ 10000` = which kind, `id % 10000` = which alarm):
///
///     10000 + alarmId   ring armed for the occurrence's own time
///     20000 + alarmId   LATE ring, armed after T inside the retry window
///     30000 + alarmId   wind check (Android AlarmManager request code)
///     40000 + alarmId   "still checking" notification
///     50000 + alarmId   "skipped" notification
///
/// **A block's width must exceed the largest index it can ever hold** (see
/// CLAUDE.md). The index here is an alarm id from `nextAlarmId()`, which
/// creeps upward across the app's lifetime, so the blocks are 10000 wide
/// (Arunoday's are 1000 — its index is a bounded 0..6 day-slot, a different
/// domain and so a different answer to the same rule).
///
/// Two of these offsets are load-bearing, not cosmetic: the `alarm` package
/// posts its Android ring notification with `startForeground(id, ...)` — its
/// notification id IS the alarm id — so a card sharing that number would
/// erase the ring's own card and its Stop button.
library;

class NivaatIds {
  NivaatIds._();

  /// The largest alarm id the blocks can hold without touching. Asserted by
  /// `ids_test.dart`; far beyond anything `nextAlarmId()` can reach in
  /// practice (it hands out 1, 2, 3, …).
  static const int maxAlarmId = 9999;

  static const int ringBlock = 10000;
  static const int lateRingBlock = 20000;
  static const int checkBlock = 30000;
  static const int headsUpBlock = 40000;
  static const int skipBlock = 50000;

  /// The ring armed for an occurrence's own scheduled time — the pre-arm the
  /// ladder commits at T-1h, T-30m, … Re-deciding the same occurrence rewrites
  /// this same number, which is exactly what you want: eight ladder rungs must
  /// converge on ONE armed ring, not scatter eight of them.
  static int ring(int alarmId) => ringBlock + alarmId;

  /// The LATE ring: armed at or after T, when a retry inside the +30m window
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

  /// BOTH ring lockers for [alarmId]. Cancel all of these whenever an alarm is
  /// deleted, disabled, or edited — the role you are not currently looking at
  /// may still be holding an armed ring.
  static List<int> allRings(int alarmId) =>
      [ring(alarmId), lateRing(alarmId)];

  static int check(int alarmId) => checkBlock + alarmId;

  static int headsUp(int alarmId) => headsUpBlock + alarmId;

  static int skip(int alarmId) => skipBlock + alarmId;
}
