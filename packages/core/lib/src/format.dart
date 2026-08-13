/// Tiny time formatters — no intl dependency for v1.
library;

/// Delay until the next wall-clock minute (:00).
///
/// A countdown that re-aims on this flips when the minute does, rather than a
/// minute after the screen opened — and unlike `Timer.periodic` it cannot
/// drift by however long the app spent suspended. Three screens use it:
/// Nivaat's home and alarm editor, and Arunoday's two settings pickers (one
/// widget). **Arunoday's home is the exception and still runs
/// `Timer.periodic`** — it predates this and has not been converted; it is
/// the one countdown in either app that can sit a minute stale after a long
/// suspend. Lives in core because it stopped being Nivaat's alone on
/// 2026-08-13.
Duration untilNextMinute([DateTime? now]) {
  final n = now ?? DateTime.now();
  final next = DateTime(n.year, n.month, n.day, n.hour, n.minute)
      .add(const Duration(minutes: 1));
  return next.difference(n);
}

String fmtClock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String fmtMinutesOfDay(double minutesAfterMidnight) {
  final m = minutesAfterMidnight.round() % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

String fmtDuration(double minutes) {
  final m = minutes.round();
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

String fmtOffset(int minutes) {
  final sign = minutes < 0 ? '−' : '+';
  final a = minutes.abs();
  return '$sign${a ~/ 60}:${(a % 60).toString().padLeft(2, '0')}';
}

/// All four wind numbers on one line: "wind 3 (≤4) · gusts 16 (≤15) km/h".
/// Everything is whole km/h — the decision rounds the same way (see [decide]),
/// so a shown value can never contradict its limit. The reader sees the full
/// picture (speed & gust, each against its cap) for every outcome, not just the
/// one metric that tripped.
String fmtWindGust(
  double courtSpeedKmh,
  int courtSpeedLimitKmh,
  double rawGustKmh,
  double rawGustLimitKmh,
) =>
    'wind ${courtSpeedKmh.round()} (≤$courtSpeedLimitKmh) · '
    'gusts ${rawGustKmh.round()} (≤${rawGustLimitKmh.round()}) km/h';

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// [weekdays] uses DateTime.weekday values (1 = Mon .. 7 = Sun).
String fmtWeekdays(Set<int> weekdays) {
  if (weekdays.length == 7) return 'Every day';
  if (weekdays.isEmpty) return 'Never';
  if (weekdays.length == 5 && weekdays.containsAll(const {1, 2, 3, 4, 5})) {
    return 'Weekdays';
  }
  if (weekdays.length == 2 && weekdays.containsAll(const {6, 7})) {
    return 'Weekends';
  }
  final sorted = weekdays.toList()..sort();
  return sorted.map((d) => _dayNames[d - 1]).join(' ');
}

String fmtShortDate(DateTime d) =>
    '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';

/// A wind-check time, prefixed with its date only when it falls on a different
/// calendar day from [alarmAt] — so an evening check before a morning alarm
/// reads "17 Jul 22:00", never a bare "22:00" that looks like the alarm day.
String fmtCheckTime(DateTime checkedAt, DateTime alarmAt) {
  final sameDay = checkedAt.year == alarmAt.year &&
      checkedAt.month == alarmAt.month &&
      checkedAt.day == alarmAt.day;
  return sameDay
      ? fmtClock(checkedAt)
      : '${fmtShortDate(checkedAt)} ${fmtClock(checkedAt)}';
}
