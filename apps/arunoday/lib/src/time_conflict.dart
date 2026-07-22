// Live wake↔bedtime collision cues for Arunoday's offset dialogs
// (MESSAGES A18). Minute-of-day precision; bedtime may still equal a
// pending AGAIN (that win is handled in the controller, not here).

String? arunodayBedtimeConflictsWithWake({
  required int bedtimeMinuteOfDay,
  int? wakeMinuteOfDay,
}) {
  if (wakeMinuteOfDay == null) return null;
  if (bedtimeMinuteOfDay == wakeMinuteOfDay) {
    return "Bedtime can't be the same as the wake alarm.";
  }
  return null;
}

String? arunodayWakeConflictsWithBedtime({
  required int wakeOffsetMinutes,
  required DateTime dawn,
  int? bedtimeMinuteOfDay,
}) {
  if (bedtimeMinuteOfDay == null) return null;
  final wakeMin =
      ((dawn.hour * 60 + dawn.minute + wakeOffsetMinutes) % 1440 + 1440) %
          1440;
  if (wakeMin == bedtimeMinuteOfDay % 1440) {
    return "Wake time can't be the same as the bedtime.";
  }
  return null;
}
