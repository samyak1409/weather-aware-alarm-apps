import 'package:core/core.dart';

/// Refuse message when [candidate] shares HH:MM with another alarm
/// (MESSAGES N20). Court and weekdays do not matter — two rings at the
/// same clock minute are unreliable on both OSes, and multi-court at the
/// same minute is better done as ±1 min. Editing the same id is fine.
String? nivaatAlarmTimeConflict(
  Iterable<NivaatAlarm> existing,
  NivaatAlarm candidate,
) {
  for (final a in existing) {
    if (a.id == candidate.id) continue;
    if (a.hour == candidate.hour && a.minute == candidate.minute) {
      final hh = candidate.hour.toString().padLeft(2, '0');
      final mm = candidate.minute.toString().padLeft(2, '0');
      return 'Another alarm is already at $hh:$mm.';
    }
  }
  return null;
}
