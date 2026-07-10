/// Tiny time formatters — no intl dependency for v1.
library;

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
