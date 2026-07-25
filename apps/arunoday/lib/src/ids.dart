/// THE ID MAP for Arunoday. Every alarm this app schedules gets its number
/// here and nowhere else, so the whole layout is readable in one place and
/// `test/ids_test.dart` can assert the blocks never overlap.
///
/// Layout — 1000-wide blocks, decodable by division
/// (`id ~/ 1000` = which kind, `id % 1000` = which day-slot):
///
///     1000 + slot   wake alarm
///     2000 + slot   bedtime alarm
///     3000          bedtime "not sleepy" re-ring (single — no slot)
///
/// **A block's width must exceed the largest index it can ever hold** (see
/// CLAUDE.md). The index here is a day-slot, provably `0..slots-1`, so 1000
/// is ~140x headroom. Don't compact these to 10/20/30: a wider window would
/// then push a wake id into the bedtime block, and [ArunodayIds.isBedtime]
/// would turn true for a WAKE alarm — putting a "+1h not sleepy" button on
/// the dawn ring screen.
library;

class ArunodayIds {
  ArunodayIds._();

  /// How many days ahead the controller keeps alarms armed — and therefore
  /// how many lockers each block needs. The modulus below MUST equal this:
  /// with fewer lockers than days, two days would share one and the later
  /// write would silently erase the earlier day's alarm.
  static const int slots = 7;

  static const int wakeBlock = 1000;
  static const int bedtimeBlock = 2000;

  /// The "not sleepy — ring bedtime again in an hour" reminder. It sits
  /// inside the bedtime range deliberately: [isBedtime] is what tells the
  /// ring screen to offer the bedtime ritual, and this ring must get it.
  static const int bedtimeAgain = 3000;

  /// Calendar day number. UTC-normalised on purpose — `DateTime.utc(y,m,d)`
  /// is pure calendar arithmetic, so DST days (23h or 25h long) still step by
  /// exactly 1. Same trick core's `Solar._dayOfYear` uses, for the same reason.
  static int dayNumber(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day)
          .difference(DateTime.utc(2020, 1, 1))
          .inDays;

  /// The wake locker for the alarm anchored to calendar day [day].
  ///
  /// Keyed on the DAY, not on "how many days from now". That's what makes the
  /// id stable: Monday's wake is the same number whether the resync runs on
  /// Sunday night or Monday morning. Under the old `1000 + i` scheme every
  /// alarm slid down one locker at each midnight, so every resync tore down
  /// and rebuilt all of them instead of re-setting them in place.
  static int wake(DateTime day) => wakeBlock + dayNumber(day) % slots;

  /// The bedtime locker for calendar day [day]. Stable, like [wake].
  static int bedtime(DateTime day) => bedtimeBlock + dayNumber(day) % slots;

  /// True for every bedtime ring — the daily ones AND the re-ring. Drives the
  /// ring screen's "+1h not sleepy" action, so it must cover [bedtimeAgain].
  static bool isBedtime(int id) => id >= bedtimeBlock && id <= bedtimeAgain;
}
