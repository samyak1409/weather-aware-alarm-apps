/// Calendar arithmetic for a device whose clock can move under you.
///
/// **Elapsed time is not clock time, and every alarm in this repo means clock
/// time** (REVIEW #10 · #11 · #13 · #14). `Duration` counts elapsed seconds, so
/// on a day the zone changes `+ Duration(days: 1)` is not "tomorrow" — on a
/// fall-back day it can land on the date it started on — and `midnight +
/// Duration(minutes: 1320)` is not "22:00". The `DateTime(y, m, d, h, min)`
/// constructor is the fix: it normalises the broken-down fields as calendar
/// values and only then resolves them against the zone, so it asks for a
/// **wall clock** and gets one. India has no DST, which is the only reason
/// any of this shipped; `TZ=America/New_York flutter test test/dst_test.dart`
/// is where it bites.
///
/// **Two wall clocks a year are not one-to-one with instants, and this asks
/// for wall clocks, so it inherits Dart's answer** (measured, NY 2026). Inside
/// the spring-forward hole a request resolves **forward**: a 02:30 alarm rings
/// at 03:30, and 02:00 and 03:00 share an instant. An ambiguous fall-back time
/// resolves to the **first** pass. Same choices a phone's own clock app makes,
/// no alarm lost, and the only real fix is a zone database — the bugs this
/// file exists for were whole days and whole hours, not this.
library;

/// The calendar day [days] after [from] — local midnight on that date.
///
/// Never `from.add(Duration(days: days))`. Beyond landing on the wrong date,
/// two window slots resolving to ONE date collide on one scheduler id
/// (`ArunodayIds` keys them by calendar day), dropping a day's alarm.
DateTime calendarDay(DateTime from, int days) =>
    DateTime(from.year, from.month, from.day + days);

/// [minutesAfterMidnight] read as a **clock** time on [day]'s calendar date.
/// Overflows into hours and, past 1440, into the following date — as calendar
/// arithmetic, not elapsed time, which is the whole point.
DateTime clockTimeOn(DateTime day, int minutesAfterMidnight) =>
    DateTime(day.year, day.month, day.day, 0, minutesAfterMidnight);
