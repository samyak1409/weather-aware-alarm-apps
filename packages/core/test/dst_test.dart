import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

/// **The DST batch, core half** (REVIEW #10 · #11 · #12 · #13 · #14).
///
/// Every assertion is written to be *true in any zone* — "next Sunday is next
/// Sunday", "22:00 is 22:00" — so the file still means something under IST,
/// where it cannot fail. **It bites only where the clocks move**, which is
/// also how each fix was proved: reverted one at a time under
/// `TZ=America/New_York flutter test test/dst_test.dart`, the named test
/// fails. Never "simplify" an expectation to `now.add(Duration(days: 1))` —
/// that puts the bug in the test and it goes quiet everywhere. Dates are the
/// real 2026 US transitions: **8 March** (23 hours) and **1 November** (25).
void main() {
  group('calendar helpers', () {
    test('calendarDay steps DATES — eight steps, eight distinct days', () {
      // The fall-back Sunday: +24h from 00:30 is 23:30 the SAME date, which is
      // how an eight-step walk came to cover only seven days (REVIEW #10).
      final now = DateTime(2026, 11, 1, 0, 30);
      final dates = {
        for (var d = 0; d <= 7; d++)
          '${calendarDay(now, d).month}-${calendarDay(now, d).day}'
      };
      expect(dates.length, 8);
      expect(calendarDay(now, 1), DateTime(2026, 11, 2));
      expect(calendarDay(now, 7), DateTime(2026, 11, 8));
    });

    test('calendarDay crosses a spring-forward night to the next date', () {
      // 2026-03-07 23:30 + 24 elapsed hours is 2026-03-09 00:30 — March 8
      // skipped entirely (REVIEW #13).
      expect(calendarDay(DateTime(2026, 3, 7, 23, 30), 1), DateTime(2026, 3, 8));
    });

    test('calendarDay steps backwards, and over month and year ends', () {
      expect(calendarDay(DateTime(2026, 11, 1, 6), -1), DateTime(2026, 10, 31));
      expect(calendarDay(DateTime(2026, 12, 31, 23), 1), DateTime(2027, 1, 1));
      expect(calendarDay(DateTime(2026, 3, 1, 0, 30), -1), DateTime(2026, 2, 28));
    });

    test('clockTimeOn is a wall clock on both transition days', () {
      // `midnight + Duration(minutes: 1320)` gives 23:00 in spring and 21:00
      // in autumn — Arunoday's bedtime, ringing an hour off (REVIEW #11).
      for (final day in [DateTime(2026, 3, 8), DateTime(2026, 11, 1)]) {
        final at = clockTimeOn(day, 22 * 60);
        expect(at.hour, 22, reason: '$day');
        expect(at.minute, 0, reason: '$day');
        expect(at.day, day.day, reason: '$day');
      }
    });

    test('clockTimeOn past 1440 rolls to the next DATE, not by 24 hours', () {
      expect(clockTimeOn(DateTime(2026, 11, 1), 1440 + 15),
          DateTime(2026, 11, 2, 0, 15));
    });
  });

  group('NivaatAlarm.nextOccurrence (REVIEW #10)', () {
    const sundayNight = NivaatAlarm(
      id: 1,
      hour: 0,
      minute: 15,
      courtId: 'c',
      weekdays: {DateTime.sunday},
    );

    test('a Sunday-only alarm still finds next Sunday on a fall-back Sunday',
        () {
      // The worst half of #10: **null**, which is not "no alarm today" — the
      // engine cancels that alarm's ring and its next check, and on Android
      // checks only ever re-book themselves.
      expect(sundayNight.nextOccurrence(DateTime(2026, 11, 1, 0, 30)),
          DateTime(2026, 11, 8, 0, 15));
    });

    test('a Saturday-night search lands on Sunday, not the Sunday after', () {
      const sundayMorning = NivaatAlarm(
        id: 1,
        hour: 6,
        minute: 0,
        courtId: 'c',
        weekdays: {DateTime.sunday},
      );
      // Was 2026-03-15: a week late, because the day walk stepped Sat → Mon.
      expect(sundayMorning.nextOccurrence(DateTime(2026, 3, 7, 23, 30)),
          DateTime(2026, 3, 8, 6, 0));
    });

    test('a once-a-week alarm resolves from every hour of the year', () {
      // The property behind both cases, swept over 2026 so a transition in
      // any zone is covered without naming its date.
      for (var d = 0; d < 365; d++) {
        final day = calendarDay(DateTime(2026, 1, 1), d);
        for (final h in [0, 3, 12, 23]) {
          final now = clockTimeOn(day, h * 60 + 30);
          final next = sundayNight.nextOccurrence(now);
          expect(next, isNotNull, reason: 'from $now');
          expect(next!.weekday, DateTime.sunday, reason: 'from $now');
          expect(next.hour * 60 + next.minute, 15, reason: 'from $now');
          expect(next.isAfter(now), isTrue, reason: 'from $now');
          expect(next.difference(now).inDays, lessThan(8), reason: 'from $now');
        }
      }
    });
  });

  group('yearly dawn extremes (REVIEW #12)', () {
    // New York — a zone that changes. Jaipur/Tonk cannot show this bug, which
    // is exactly why it shipped.
    const lat = 40.71, lon = -74.01;

    test('the extremes agree with the daily dawn on their own days', () {
      // The plan applied ONE offset — today's — to all 365 days while every
      // daily wake went through `.toLocal()`, so for half the year the auto
      // bedtime was built on dawns an hour from the ones the alarms used, and
      // jumped 60 minutes at each transition while the wake did not move.
      final e = Solar.yearlyDawnExtremes(2026, lat, lon)!;
      final lo = Solar.civilDawnLocal(e.earliestDay, lat, lon)!;
      final hi = Solar.civilDawnLocal(e.latestDay, lat, lon)!;
      expect(lo.hour * 60 + lo.minute, closeTo(e.earliestMinutes, 1),
          reason: 'earliest was ${e.earliestDay}');
      expect(hi.hour * 60 + hi.minute, closeTo(e.latestMinutes, 1),
          reason: 'latest was ${e.latestDay}');
    });

    test('a pinned offset is still honoured — tests depend on that fiction',
        () {
      // The one way to get a machine-independent wall clock out of this, and
      // `solar_test` / `sleep_plan_test` are built on it.
      final ist = Solar.yearlyDawnExtremes(2026, 26.17, 75.79,
          utcOffsetMinutes: 330)!;
      expect(ist.earliestMinutes, closeTo(5 * 60 + 8, 2));
      expect(ist.latestMinutes, closeTo(6 * 60 + 51, 2));
    });
  });
}
